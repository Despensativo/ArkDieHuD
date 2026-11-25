#!/usr/bin/env bash
# ==============================================================================
# ralph-loop.sh — Ciclo seguro de correção e verificação offline (estilo Ralph Loop)
# Focado em resolver os itens de docs/AUDIT_REPORT.md um módulo por vez (M1..M6),
# com limite máximo de iterações, gate offline iOS e rollback automático via Git.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
DERIVED_DATA="${DERIVED_DATA:-"$(dirname "$REPO_ROOT")/.build"}"
LOG_DIR="${TMPDIR:-/tmp}/swift-sensors-ralph"

CHECK_ONLY=0
CREATE_CHECKPOINT=0
MODULE=""
MAX_ITERATIONS=5
FIX_CMD=""

usage() {
    cat <<EOF
Uso:
  $0 --check-only [--module M1..M6]
  $0 --module <M1..M6> --cmd "<comando>" [--max-iterations 5] [--create-checkpoint]

Opções:
  --check-only         Roda apenas o gate de verificação offline (não altera Git)
  --module <M1..M6>    Módulo alvo em docs/AUDIT_REPORT.md (ex: M1, M2, ..., M6)
  --cmd "<comando>"    Comando executor a rodar em cada iteração do loop
  --max-iterations N   Limite máximo de tentativas (padrão: 5, teto absoluto: 10)
  --create-checkpoint  Cria commit local 'chore: ralph-loop checkpoint' se houver
                       alterações pendentes antes de iniciar o loop
  -h, --help           Mostra esta ajuda

Segurança:
  Sem --check-only e sem --create-checkpoint, o script ABORTA se houver alterações
  não commitadas no repositório para evitar perda de trabalho em rollback.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check-only)
            CHECK_ONLY=1
            shift
            ;;
        --create-checkpoint)
            CREATE_CHECKPOINT=1
            shift
            ;;
        --module)
            [ $# -ge 2 ] || { echo "Erro: --module exige argumento (M1..M6)." >&2; exit 2; }
            MODULE="$2"
            shift 2
            ;;
        --max-iterations)
            [ $# -ge 2 ] || { echo "Erro: --max-iterations exige número inteiro." >&2; exit 2; }
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        --cmd)
            [ $# -ge 2 ] || { echo "Erro: --cmd exige comando entre aspas." >&2; exit 2; }
            FIX_CMD="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Opção desconhecida: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || [ "$MAX_ITERATIONS" -lt 1 ] || [ "$MAX_ITERATIONS" -gt 10 ]; then
    echo "Erro: --max-iterations deve ser inteiro entre 1 e 10 (recebido: $MAX_ITERATIONS)." >&2
    exit 2
fi

if [ -n "$MODULE" ] && ! [[ "$MODULE" =~ ^M[1-6]$ ]]; then
    echo "Erro: módulo inválido '$MODULE'. Use M1, M2, M3, M4, M5 ou M6." >&2
    exit 2
fi

print_module_scope() {
    local mod="$1"
    local report="$REPO_ROOT/docs/AUDIT_REPORT.md"
    if [ -n "$mod" ] && [ -f "$report" ]; then
        echo "🎯 Escopo alvo ($mod em docs/AUDIT_REPORT.md):"
        awk -v target="### $mod " '
            index($0, target) == 1 { show=1 }
            show && /^### M[0-9]+ / && index($0, target) != 1 { exit }
            show { print "  " $0 }
        ' "$report" | head -n 12
        echo ""
    fi
}

run_offline_gate() {
    local log_file="$1"
    local gate_rc=0

    {
        echo "--- [Gate 1/3] Build SwiftSensorsApp (generic/platform=iOS, arm64) ---"
        set +e
        xcodebuild \
            -project "$REPO_ROOT/Examples/SwiftSensorsApp.xcodeproj" \
            -scheme SwiftSensorsApp \
            -configuration Debug \
            -destination "generic/platform=iOS" \
            CODE_SIGNING_ALLOWED=NO \
            -derivedDataPath "$DERIVED_DATA" \
            build
        local build_rc=$?
        set -e

        if [ "$build_rc" -ne 0 ]; then
            echo "FALHA NO GATE: xcodebuild retornou código $build_rc"
            return 1
        fi

        echo "--- [Gate 2/3] Swift-Format Lint nos arquivos Swift alterados ---"
        local changed_swift
        changed_swift="$(
            {
                git -C "$REPO_ROOT" diff --name-only --diff-filter=ACM
                git -C "$REPO_ROOT" ls-files --others --exclude-standard
            } | grep '\.swift$' | sort -u || true
        )"

        if [ -n "$changed_swift" ]; then
            local lint_err=0
            while IFS= read -r rel_file; do
                [ -z "$rel_file" ] && continue
                local full_path="$REPO_ROOT/$rel_file"
                [ -f "$full_path" ] || continue
                set +e
                local lint_out
                lint_out="$(xcrun swift-format lint --configuration "$REPO_ROOT/.swift-format" "$full_path" 2>&1)"
                local lrc=$?
                set -e
                if [ -n "$lint_out" ]; then
                    printf "%s\n" "$lint_out"
                fi
                if [ "$lrc" -ne 0 ] || printf "%s\n" "$lint_out" | grep -q ": error:"; then
                    lint_err=1
                fi
            done <<< "$changed_swift"

            if [ "$lint_err" -ne 0 ]; then
                echo "FALHA NO GATE: erro de sintaxe ou violação crítica no swift-format."
                return 1
            fi
        else
            echo "Nenhum arquivo .swift modificado; validando fachada SwiftSensors.swift."
            xcrun swift-format lint --configuration "$REPO_ROOT/.swift-format" "$REPO_ROOT/Sources/SwiftSensors/SwiftSensors.swift" || true
        fi

        echo "--- [Gate 3/3] Checagem de privacidade/segredos no diff ---"
        local secret_hits
        secret_hits="$(git -C "$REPO_ROOT" diff -U0 -- Sources Examples docs .agents 2>/dev/null \
            | grep -E '^\+' \
            | grep -vE '^\+\+\+' \
            | grep -E '0000[0-9A-F]{4}-[0-9A-F]{16}|-----BEGIN .*PRIVATE KEY-----|(ghp_|github_pat_|sk-[A-Za-z0-9]{20,})' || true)"

        local untracked_hits
        untracked_hits="$(git -C "$REPO_ROOT" ls-files --others --exclude-standard -- Sources Examples docs .agents 2>/dev/null \
            | while IFS= read -r rel_f; do
                [ -f "$REPO_ROOT/$rel_f" ] || continue
                grep -HnE '0000[0-9A-F]{4}-[0-9A-F]{16}|-----BEGIN .*PRIVATE KEY-----|(ghp_|github_pat_|sk-[A-Za-z0-9]{20,})' "$REPO_ROOT/$rel_f" || true
            done || true)"

        if [ -n "$secret_hits" ] || [ -n "$untracked_hits" ]; then
            echo "FALHA NO GATE: possível UDID/token/chave privada detectada no diff ou arquivo novo!"
            return 1
        fi

        if git -C "$REPO_ROOT" diff -U0 -- Examples/SwiftSensorsApp.xcodeproj/project.pbxproj 2>/dev/null \
            | grep -qE '^\+.*DEVELOPMENT_TEAM = [A-Z0-9]{10}'; then
            echo "ℹ️  Aviso (M5 pendente): DEVELOPMENT_TEAM ainda está definido diretamente em project.pbxproj."
        fi

        echo "✅ Gate offline aprovado."
    } > "$log_file" 2>&1 || gate_rc=$?

    cat "$log_file"
    return "$gate_rc"
}

mkdir -p "$LOG_DIR"

if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "🔍 Executando verificação offline do Ralph Loop (--check-only)..."
    print_module_scope "$MODULE"
    if run_offline_gate "$LOG_DIR/check-only.log"; then
        echo "✅ Check offline concluído com sucesso."
        exit 0
    else
        echo "❌ Check offline falhou. Consulte: $LOG_DIR/check-only.log" >&2
        exit 1
    fi
fi

if [ -z "$FIX_CMD" ]; then
    echo "Erro: fora do modo --check-only é obrigatório informar --cmd \"<comando>\"." >&2
    usage >&2
    exit 2
fi

if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    if [ "$CREATE_CHECKPOINT" -eq 1 ]; then
        echo "📌 Criando commit de checkpoint local antes do loop..."
        git -C "$REPO_ROOT" add -A
        git -C "$REPO_ROOT" commit -m "chore: ralph-loop checkpoint"
    else
        echo "🛑 ABORTADO POR SEGURANÇA: existem alterações não commitadas no repositório." >&2
        echo "   O rollback automático via Git poderia descartar trabalho em andamento." >&2
        echo "   Faça um commit manual ou passe --create-checkpoint antes de rodar o loop." >&2
        exit 3
    fi
fi

BASELINE_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
echo "🔒 Baseline SHA seguro: $BASELINE_SHA"
echo "🔁 Iniciando Ralph Loop | Módulo: ${MODULE:-TODOS} | Máx iterações: $MAX_ITERATIONS"
print_module_scope "$MODULE"

for iter in $(seq 1 "$MAX_ITERATIONS"); do
    ITER_BASE_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    ITER_LOG="$LOG_DIR/iter-${iter}.log"
    GATE_LOG="$LOG_DIR/iter-${iter}-gate.log"

    echo "=== Iteração $iter / $MAX_ITERATIONS ==="
    set +e
    (
        cd "$REPO_ROOT"
        export RALPH_MODULE="$MODULE"
        export RALPH_ITERATION="$iter"
        export RALPH_REPO_ROOT="$REPO_ROOT"
        export RALPH_AUDIT_REPORT="$REPO_ROOT/docs/AUDIT_REPORT.md"
        eval "$FIX_CMD"
    ) > "$ITER_LOG" 2>&1
    CMD_RC=$?
    set -e

    if [ "$CMD_RC" -ne 0 ]; then
        echo "⚠️  Comando --cmd retornou código $CMD_RC (ver $ITER_LOG). Executando rollback..."
        git -C "$REPO_ROOT" reset --hard "$ITER_BASE_SHA" >/dev/null
        git -C "$REPO_ROOT" clean -fd >/dev/null
        continue
    fi

    if run_offline_gate "$GATE_LOG"; then
        echo ""
        echo "✅ Sucesso na iteração $iter!"
        echo "Arquivos alterados aguardando sua revisão:"
        git -C "$REPO_ROOT" status --short
        exit 0
    else
        echo "⏪ Gate offline falhou na iteração $iter (ver $GATE_LOG). Executando rollback para $ITER_BASE_SHA..."
        git -C "$REPO_ROOT" reset --hard "$ITER_BASE_SHA" >/dev/null
        git -C "$REPO_ROOT" clean -fd >/dev/null
    fi
done

echo "❌ Limite máximo de $MAX_ITERATIONS iterações atingido sem aprovação no gate." >&2
echo "   Estado preservado no baseline seguro ($BASELINE_SHA). Logs em: $LOG_DIR" >&2
exit 1
