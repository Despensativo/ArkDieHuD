#!/usr/bin/env bash
# ==============================================================================
# install.sh — Assistente guiado (1 comando) para compilar, assinar e instalar
# o ArkDieHuD direto no seu iPad/iPhone com conta Apple gratuita ou paga.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_XCCONFIG="${SCRIPT_DIR}/Examples/Config/LocalSigning.xcconfig"
PROJECT_PATH="${SCRIPT_DIR}/Examples/SwiftSensorsApp.xcodeproj"
DERIVED_DATA="${DERIVED_DATA:-"$(dirname "${SCRIPT_DIR}")/.build"}"

CHECK_ONLY=0

usage() {
    cat <<'EOF'
Uso: ./install.sh [--check] [--help]

Assistente interativo para instalar o ArkDieHuD no iPad/iPhone a partir do Mac
usando qualquer Apple ID (gratuito ou pago), sem precisar editar arquivos na mão.

Opções:
  --check   Verifica Xcode, SDK iOS, iPad conectado e certificados sem alterar nada
  --help    Exibe esta ajuda

Sem Mac/Xcode?
  Baixe o arquivo pronto `ArkDieHuD-unsigned.ipa` na aba Releases do GitHub e
  instale pelo Sideloadly (Windows/Mac) ou SideStore/AltStore Classic no iPad:
  https://github.com/Despensativo/ArkDieHuD/releases/latest
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check)
            CHECK_ONLY=1
            shift
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

echo "============================================================"
echo "  ArkDieHuD — Assistente de Instalação Guiada (macOS)"
echo "============================================================"
echo ""

# ------------------------------------------------------------------------------
# 1. Verificar Xcode + SDK iOS
# ------------------------------------------------------------------------------
echo "[1/4] Verificando Xcode e SDK do iOS/iPadOS..."
if ! command -v xcodebuild >/dev/null 2>&1 || ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
    echo "❌ Xcode completo (com SDK iPhoneOS) não encontrado neste Mac."
    echo ""
    echo "💡 Você NÃO precisa baixar o Xcode (~10 GB) só para usar o app!"
    echo "   Alternativa leve (Windows ou Mac):"
    echo "   1) Baixe o .ipa pronto:"
    echo "      https://github.com/Despensativo/ArkDieHuD/releases/latest/download/ArkDieHuD-unsigned.ipa"
    echo "   2) Arraste no Sideloadly (ou adicione no SideStore/AltStore Classic) com seu Apple ID gratuito."
    exit 1
fi
IOS_SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "✅ Xcode + iOS SDK pronto (${IOS_SDK_PATH##*/})."
echo ""

# ------------------------------------------------------------------------------
# 2. Detectar iPad / iPhone físico pareado
# ------------------------------------------------------------------------------
echo "[2/4] Procurando iPad/iPhone conectado (USB-C ou Wi-Fi)..."
DEVICES_LINES="$(
    xcrun devicectl list devices --json-output - 2>/dev/null | python3 -c '
import sys, json
raw = sys.stdin.read()
idx = raw.find("{")
if idx == -1:
    sys.exit(0)
data = json.loads(raw[idx:])
devs = data.get("result", {}).get("devices", [])
physical = []
for d in devs:
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    props = d.get("deviceProperties", {})
    if hw.get("reality") != "physical" or conn.get("pairingState") != "paired":
        continue
    ident = d.get("identifier") or ""
    udid = hw.get("udid") or ident
    name = props.get("name", "Dispositivo iOS/iPadOS")
    model = hw.get("productType", "iOS")
    tunnel = conn.get("tunnelState", "unknown")
    transport = conn.get("transportType", "")
    is_wired = 0 if transport == "wired" else 1
    is_conn = 0 if tunnel == "connected" else 1
    is_ipad = 0 if ("ipad" in model.lower() or "ipad" in name.lower()) else 1
    physical.append((is_wired, is_conn, is_ipad, name, model, tunnel, transport, ident, udid))
physical.sort()
for _, _, _, name, model, tunnel, transport, ident, udid in physical:
    print(f"{ident}\t{udid}\t{name}\t{model}\t{tunnel}\t{transport}")
'
)"

if [ -z "${DEVICES_LINES}" ]; then
    echo "❌ Nenhum iPad/iPhone físico pareado encontrado."
    echo "👉 Como resolver:"
    echo "   1. Conecte o cabo USB-C entre o Mac e o iPad/iPhone."
    echo "   2. Desbloqueie a tela e toque em 'Confiar neste Computador'."
    echo "   3. Ative Ajustes -> Privacidade e Segurança -> Modo Desenvolvedor no aparelho."
    exit 1
fi

DEVICE_IDS=()
DEVICE_UDIDS=()
DEVICE_LABELS=()
while IFS=$'\t' read -r d_id d_udid d_name d_model d_tunnel d_transport; do
    [ -z "$d_id" ] && continue
    DEVICE_IDS+=("$d_id")
    DEVICE_UDIDS+=("$d_udid")
    t_label="${d_transport:-unknown}"
    DEVICE_LABELS+=("${d_name} (${d_model}, ${t_label}, tunnel=${d_tunnel})")
done <<< "$DEVICES_LINES"

SELECTED_INDEX=0
if [ "${#DEVICE_IDS[@]}" -gt 1 ] && [ "$CHECK_ONLY" -eq 0 ]; then
    echo "Dispositivos encontrados:"
    for i in "${!DEVICE_LABELS[@]}"; do
        echo "  [$((i + 1))] ${DEVICE_LABELS[$i]}"
    done
    read -r -p "👉 Escolha o número do aparelho [1]: " dev_choice
    if [ -n "${dev_choice:-}" ] && [[ "$dev_choice" =~ ^[0-9]+$ ]]; then
        cand=$((dev_choice - 1))
        if [ "$cand" -ge 0 ] && [ "$cand" -lt "${#DEVICE_IDS[@]}" ]; then
            SELECTED_INDEX="$cand"
        fi
    fi
fi

TARGET_DEVICE_ID="${DEVICE_IDS[$SELECTED_INDEX]}"
TARGET_DEVICE_UDID="${DEVICE_UDIDS[$SELECTED_INDEX]}"
TARGET_DEVICE_LABEL="${DEVICE_LABELS[$SELECTED_INDEX]}"
echo "✅ Alvo selecionado: ${TARGET_DEVICE_LABEL}"

if [ "$CHECK_ONLY" -eq 0 ]; then
    LOCK_OUT="$(xcrun devicectl device info lockState --device "$TARGET_DEVICE_ID" 2>&1 || true)"
    if printf "%s" "$LOCK_OUT" | grep -qE "passcodeRequired:[[:space:]]*true"; then
        echo "🔒 A tela do aparelho está bloqueada. Desbloqueie o iPad/iPhone agora."
        read -r -p "Pressione ENTER quando a tela estiver desbloqueada... " _
    fi
fi
echo ""

# ------------------------------------------------------------------------------
# 3. Detectar / Configurar assinatura (Apple ID gratuito ou pago)
# ------------------------------------------------------------------------------
echo "[3/4] Verificando assinatura e certificado no Mac..."
EXISTING_TEAM=""
EXISTING_BUNDLE=""
if [ -f "${LOCAL_XCCONFIG}" ]; then
    EXISTING_TEAM="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "${LOCAL_XCCONFIG}" | tr -d '[:space:]' | head -n 1 || true)"
    EXISTING_BUNDLE="$(sed -n 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=[[:space:]]*//p' "${LOCAL_XCCONFIG}" | tr -d '[:space:]' | head -n 1 || true)"
fi

IDENTITIES_LINES="$(
    security find-identity -v -p codesigning 2>/dev/null | python3 -c '
import sys, re
seen = set()
for line in sys.stdin:
    if "Apple Development:" not in line:
        continue
    m = re.search(r"\"(Apple Development:[^\"]+)\"", line)
    if not m:
        continue
    full = m.group(1)
    tm = re.search(r"\(([A-Z0-9]{10})\)\s*$", full)
    if not tm:
        continue
    tid = tm.group(1)
    if tid not in seen:
        seen.add(tid)
        print(f"{tid}\t{full}")
' || true
)"

if [ "$CHECK_ONLY" -eq 1 ]; then
    if [ -n "${EXISTING_TEAM}" ]; then
        echo "✅ LocalSigning.xcconfig já configurado (Team ID definido localmente)."
    else
        echo "ℹ️  LocalSigning.xcconfig ainda não criado (será gerado ao rodar ./install.sh)."
    fi
    if [ -n "${IDENTITIES_LINES}" ]; then
        COUNT_IDS="$(printf "%s\n" "${IDENTITIES_LINES}" | wc -l | tr -d ' ')"
        echo "✅ ${COUNT_IDS} certificado(s) 'Apple Development' encontrado(s) no Keychain."
    else
        echo "⚠️  Nenhum certificado 'Apple Development' encontrado ainda no Keychain."
        echo "   Para usar Apple ID gratuito: Xcode -> Settings -> Accounts -> '+' -> Manage Certificates -> Apple Development."
    fi
    echo ""
    echo "✅ Verificação concluída."
    exit 0
fi

CHOSEN_TEAM=""
CHOSEN_BUNDLE="${EXISTING_BUNDLE:-}"

if [ -n "${EXISTING_TEAM}" ]; then
    echo "Configuração local detectada em Examples/Config/LocalSigning.xcconfig."
    read -r -p "Deseja usar a assinatura local já configurada? [S/n]: " reuse_ans
    if [ -z "${reuse_ans:-}" ] || [[ "$reuse_ans" =~ ^[SsYy]$ ]]; then
        CHOSEN_TEAM="${EXISTING_TEAM}"
    fi
fi

if [ -z "${CHOSEN_TEAM}" ]; then
    if [ -n "${IDENTITIES_LINES}" ]; then
        TEAM_IDS=()
        TEAM_LABELS=()
        while IFS=$'\t' read -r tid tlabel; do
            [ -z "$tid" ] && continue
            TEAM_IDS+=("$tid")
            TEAM_LABELS+=("$tlabel")
        done <<< "$IDENTITIES_LINES"

        echo "Certificados Apple Development detectados:"
        for i in "${!TEAM_LABELS[@]}"; do
            echo "  [$((i + 1))] ${TEAM_LABELS[$i]}"
        done
        echo "  [M] Digitar um Team ID manualmente"
        read -r -p "👉 Escolha o certificado [1]: " team_choice
        if [ -z "${team_choice:-}" ]; then
            team_choice="1"
        fi
        if [[ "$team_choice" =~ ^[0-9]+$ ]]; then
            idx=$((team_choice - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#TEAM_IDS[@]}" ]; then
                CHOSEN_TEAM="${TEAM_IDS[$idx]}"
            fi
        fi
    else
        echo "⚠️  Nenhum certificado 'Apple Development' foi encontrado no Keychain."
        echo "   Passo rápido (1x só, funciona com Apple ID gratuito):"
        echo "   1. Abra o Xcode -> Settings (Cmd+,) -> Accounts"
        echo "   2. Clique em '+' -> Apple ID -> faça login com seu Apple ID"
        echo "   3. Clique em 'Manage Certificates...' -> '+' -> 'Apple Development'"
        echo "   4. Ou digite seu Team ID de 10 caracteres abaixo se já souber."
        echo ""
    fi

    if [ -z "${CHOSEN_TEAM}" ]; then
        read -r -p "👉 Informe seu DEVELOPMENT_TEAM (10 caracteres): " manual_team
        CHOSEN_TEAM="$(printf "%s" "${manual_team}" | tr -d '[:space:]')"
    fi

    if [ -z "${CHOSEN_TEAM}" ]; then
        echo "❌ DEVELOPMENT_TEAM não informado. Abortando."
        exit 1
    fi

    CLEAN_USER="$(printf "%s" "${USER:-user}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
    DEFAULT_BUNDLE="${CHOSEN_BUNDLE:-com.${CLEAN_USER:-ark}.ArkDieHuD}"
    read -r -p "👉 Bundle ID único [${DEFAULT_BUNDLE}]: " input_bundle
    CHOSEN_BUNDLE="$(printf "%s" "${input_bundle:-$DEFAULT_BUNDLE}" | tr -d '[:space:]')"

    mkdir -p "$(dirname "${LOCAL_XCCONFIG}")"
    {
        echo "DEVELOPMENT_TEAM = ${CHOSEN_TEAM}"
        if [ -n "${CHOSEN_BUNDLE}" ]; then
            echo "PRODUCT_BUNDLE_IDENTIFIER = ${CHOSEN_BUNDLE}"
        fi
    } > "${LOCAL_XCCONFIG}"
    echo "✅ Salvo localmente em Examples/Config/LocalSigning.xcconfig (ignorado pelo Git)."
fi
echo ""

# ------------------------------------------------------------------------------
# 4. Compilar, Instalar e Abrir no Aparelho
# ------------------------------------------------------------------------------
XCODE_DEST="generic/platform=iOS"
if [ -n "${TARGET_DEVICE_UDID:-}" ]; then
    XCODE_DEST="platform=iOS,id=${TARGET_DEVICE_UDID}"
fi

echo "[4/4] Compilando ArkDieHuD (Release) e assinando para o dispositivo..."
xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme SwiftSensorsApp \
    -configuration Release \
    -destination "${XCODE_DEST}" \
    -allowProvisioningUpdates \
    -derivedDataPath "${DERIVED_DATA}" \
    build

APP_BUNDLE="${DERIVED_DATA}/Build/Products/Release-iphoneos/SwiftSensorsApp.app"
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "❌ App compilado não encontrado em: ${APP_BUNDLE}"
    exit 1
fi

EFFECTIVE_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${APP_BUNDLE}/Info.plist" 2>/dev/null || echo "${CHOSEN_BUNDLE:-com.cristianark.SwiftSensorsApp}")"

echo ""
echo "📲 Instalando no iPad/iPhone (${TARGET_DEVICE_LABEL})..."
if [ -f "${APP_BUNDLE}/embedded.mobileprovision" ]; then
    xcrun devicectl device profile install --device "${TARGET_DEVICE_ID}" "${APP_BUNDLE}/embedded.mobileprovision" >/dev/null 2>&1 || true
fi
xcrun devicectl device install app --device "${TARGET_DEVICE_ID}" "${APP_BUNDLE}"

echo "🚀 Abrindo ArkDieHuD (${EFFECTIVE_BUNDLE_ID})..."
if ! xcrun devicectl device process launch --device "${TARGET_DEVICE_ID}" --terminate-existing "${EFFECTIVE_BUNDLE_ID}"; then
    echo ""
    echo "⚠️  O iPad pode pedir confiança na primeira instalação gratuita:"
    echo "   • No iPad, abra Ajustes -> Geral -> Gestão de VPN e Dispositivo"
    echo "   • Toque no seu Apple ID e depois em 'Confiar'"
    echo "   • Confirme também que Ajustes -> Privacidade e Segurança -> Modo Desenvolvedor está ativo."
    exit 1
fi

echo ""
echo "============================================================"
echo "  ✅ ArkDieHuD instalado e aberto com sucesso!"
echo "============================================================"
echo "💡 Se usou Apple ID gratuito, o app vale por 7 dias."
echo "   Para renovar depois, conecte o aparelho e rode ./install.sh de novo."
