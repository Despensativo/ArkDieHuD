#!/usr/bin/env bash
# ==============================================================================
# static-audit.sh — Auditoria estática 100% offline para swift-sensors (iOS/iPadOS)
# Uso: Scripts/static-audit.sh [--summary] [--clean]
# Não altera nenhum arquivo de produção. Retorna 0 se o build compilar sem erros.
# ==============================================================================
set -euo pipefail

SUMMARY_MODE=0
CLEAN_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --summary)
            SUMMARY_MODE=1
            ;;
        --clean)
            CLEAN_BUILD=1
            ;;
        -h|--help)
            echo "Uso: $0 [--summary] [--clean]"
            exit 0
            ;;
        *)
            echo "Opção desconhecida: $arg" >&2
            exit 2
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
DERIVED_DATA="${DERIVED_DATA:-"$(dirname "$REPO_ROOT")/.build"}"

BUILD_LOG="$(mktemp)"
LINT_LOG="$(mktemp)"
trap 'rm -f "$BUILD_LOG" "$LINT_LOG"' EXIT

echo "==[ 1/4 ] Build & Warnings de Compilação (generic/platform=iOS, arm64) =="
BUILD_ACTIONS=("build")
if [ "$CLEAN_BUILD" -eq 1 ]; then
    BUILD_ACTIONS=("clean" "build")
fi

set +e
xcodebuild \
    -project "$REPO_ROOT/Examples/SwiftSensorsApp.xcodeproj" \
    -scheme SwiftSensorsApp \
    -configuration Debug \
    -destination "generic/platform=iOS" \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "$DERIVED_DATA" \
    "${BUILD_ACTIONS[@]}" > "$BUILD_LOG" 2>&1
BUILD_RC=$?
set -e

UNIQUE_WARNINGS="$(grep -E "^[^[:space:]].*:[0-9]+:[0-9]+: warning:" "$BUILD_LOG" | sort -u || true)"
UNIQUE_ERRORS="$(grep -E "(^[^[:space:]].*:[0-9]+:[0-9]+: error:|^error: |\*\* BUILD FAILED \*\*)" "$BUILD_LOG" | sort -u || true)"

WARNING_COUNT=0
if [ -n "$UNIQUE_WARNINGS" ]; then
    WARNING_COUNT="$(printf "%s\n" "$UNIQUE_WARNINGS" | wc -l | tr -d ' ')"
fi

ERROR_COUNT=0
if [ -n "$UNIQUE_ERRORS" ]; then
    ERROR_COUNT="$(printf "%s\n" "$UNIQUE_ERRORS" | wc -l | tr -d ' ')"
fi

if [ "$BUILD_RC" -eq 0 ] && grep -q "\*\* BUILD SUCCEEDED \*\*" "$BUILD_LOG"; then
    echo "Status: BUILD SUCCEEDED | Warnings únicos: $WARNING_COUNT | Erros: $ERROR_COUNT"
else
    echo "Status: BUILD FAILED (rc=$BUILD_RC) | Warnings únicos: $WARNING_COUNT | Erros: $ERROR_COUNT"
fi

if [ "$SUMMARY_MODE" -eq 0 ] && [ "$WARNING_COUNT" -gt 0 ]; then
    printf "%s\n" "$UNIQUE_WARNINGS" | sed "s|$REPO_ROOT/||g"
fi
if [ "$ERROR_COUNT" -gt 0 ]; then
    printf "%s\n" "$UNIQUE_ERRORS" | sed "s|$REPO_ROOT/||g"
fi

echo ""
echo "==[ 2/4 ] Swift-Format Lint Offline =="
set +e
xcrun swift-format lint \
    --configuration "$REPO_ROOT/.swift-format" \
    -r "$REPO_ROOT/Sources/SwiftSensors" "$REPO_ROOT/Examples/SwiftSensorsApp" > "$LINT_LOG" 2>&1
set -e

LINT_TOTAL="$(grep -c ": warning:" "$LINT_LOG" || true)"
echo "Total de avisos swift-format: $LINT_TOTAL"
if [ "$LINT_TOTAL" -gt 0 ]; then
    echo "Top regras:"
    grep ": warning:" "$LINT_LOG" | sed -n 's/.*\[\([A-Za-z0-9_]*\)\].*/\1/p' | sort | uniq -c | sort -rn | head -n 12
    if [ "$SUMMARY_MODE" -eq 0 ]; then
        echo "Top arquivos:"
        grep ": warning:" "$LINT_LOG" | awk -F: '{print $1}' | sed "s|$REPO_ROOT/||g" | sort | uniq -c | sort -rn | head -n 15
    fi
fi

echo ""
echo "==[ 3/4 ] Varredura Estrutural, Riscos e APIs Deprecadas =="

LARGE_FILES="$(find "$REPO_ROOT/Sources/SwiftSensors" "$REPO_ROOT/Examples/SwiftSensorsApp" -name "*.swift" -type f -exec wc -l {} + \
    | awk -v root="$REPO_ROOT/" '{n=$1; $1=""; sub(/^[[:space:]]+/, ""); if ($0 != "total" && n > 300) {sub(root, ""); printf "  %4d linhas  %s\n", n, $0}}' | sort -rn)"
LARGE_COUNT=0
if [ -n "$LARGE_FILES" ]; then
    LARGE_COUNT="$(printf "%s\n" "$LARGE_FILES" | wc -l | tr -d ' ')"
fi
echo "Arquivos Swift > 300 linhas: $LARGE_COUNT"
if [ "$SUMMARY_MODE" -eq 0 ] && [ "$LARGE_COUNT" -gt 0 ]; then
    printf "%s\n" "$LARGE_FILES"
fi

UNSAFE_HITS="$(grep -rnE --include="*.swift" "unsafeBitCast|@unchecked Sendable|setValue\(.*forKey:|NSLog\(|print\(" "$REPO_ROOT/Sources/SwiftSensors" "$REPO_ROOT/Examples/SwiftSensorsApp" | grep -v ":///" | grep -vE ":[0-9]+:[[:space:]]*///" || true)"
UNSAFE_COUNT=0
if [ -n "$UNSAFE_HITS" ]; then
    UNSAFE_COUNT="$(printf "%s\n" "$UNSAFE_HITS" | wc -l | tr -d ' ')"
fi
echo "Ocorrências de unsafeBitCast / @unchecked Sendable / KVC / NSLog / print: $UNSAFE_COUNT"
if [ "$SUMMARY_MODE" -eq 0 ] && [ "$UNSAFE_COUNT" -gt 0 ]; then
    printf "%s\n" "$UNSAFE_HITS" | sed "s|$REPO_ROOT/|  |g"
fi

EMOJI_HITS="$(grep -rnE --include="*.swift" "🟢|❌|⚡|⚠️|🚀|📊|🔴|🟣" "$REPO_ROOT/Examples/SwiftSensorsApp" || true)"
EMOJI_COUNT=0
if [ -n "$EMOJI_HITS" ]; then
    EMOJI_COUNT="$(printf "%s\n" "$EMOJI_HITS" | wc -l | tr -d ' ')"
fi
echo "Emojis funcionais em Views/Components SwiftUI: $EMOJI_COUNT"
if [ "$SUMMARY_MODE" -eq 0 ] && [ "$EMOJI_COUNT" -gt 0 ]; then
    printf "%s\n" "$EMOJI_HITS" | sed "s|$REPO_ROOT/|  |g"
fi

DEPRECATED_HITS="$(grep -rn --include="*.swift" "\.foregroundColor(" "$REPO_ROOT/Examples/SwiftSensorsApp" || true)"
DEPRECATED_COUNT=0
if [ -n "$DEPRECATED_HITS" ]; then
    DEPRECATED_COUNT="$(printf "%s\n" "$DEPRECATED_HITS" | wc -l | tr -d ' ')"
fi
echo "Usos de .foregroundColor(...) deprecado: $DEPRECATED_COUNT"
if [ "$SUMMARY_MODE" -eq 0 ] && [ "$DEPRECATED_COUNT" -gt 0 ]; then
    printf "%s\n" "$DEPRECATED_HITS" | awk -F: '{print $1}' | sed "s|$REPO_ROOT/||g" | sort | uniq -c | sort -rn | sed 's/^/  /'
fi

echo ""
echo "==[ 4/4 ] Privacidade e Símbolos Potencialmente Órfãos =="
PRIVACY_HITS="$(grep -rnE "0000[0-9A-F]{4}-[0-9A-F]{16}|DEVELOPMENT_TEAM" "$REPO_ROOT/Sources" "$REPO_ROOT/Examples/SwiftSensorsApp.xcodeproj/project.pbxproj" "$REPO_ROOT"/*.sh 2>/dev/null || true)"
PRIVACY_COUNT=0
if [ -n "$PRIVACY_HITS" ]; then
    PRIVACY_COUNT="$(printf "%s\n" "$PRIVACY_HITS" | wc -l | tr -d ' ')"
fi
echo "Identificadores/configurações locais hardcoded fora de xcconfig: $PRIVACY_COUNT"
if [ "$SUMMARY_MODE" -eq 0 ] && [ "$PRIVACY_COUNT" -gt 0 ]; then
    # Mascara valores literais para não vazar identificadores em logs
    printf "%s\n" "$PRIVACY_HITS" | sed -E 's/0000[0-9A-F]{4}-[0-9A-F]{16}/<REDACTED_UDID>/g; s/DEVELOPMENT_TEAM = [A-Z0-9]+/DEVELOPMENT_TEAM = <REDACTED_TEAM>/g' | sed "s|$REPO_ROOT/|  |g"
fi

echo "Referências a símbolos candidatos a revisão/remoção:"
for sym in PerformanceOptimizer PowerSensorsView pushExternalSnapshot MetalFPSMonitor; do
    sym_hits="$(grep -rn --include="*.swift" "$sym" "$REPO_ROOT/Sources/SwiftSensors" "$REPO_ROOT/Examples/SwiftSensorsApp" || true)"
    cnt=0
    if [ -n "$sym_hits" ]; then
        cnt="$(printf "%s\n" "$sym_hits" | wc -l | tr -d ' ')"
    fi
    echo "  - $sym: $cnt ocorrências"
done

if [ "$BUILD_RC" -ne 0 ] || [ "$ERROR_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
