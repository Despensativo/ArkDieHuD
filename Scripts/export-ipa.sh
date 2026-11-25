#!/usr/bin/env bash
set -euo pipefail

# Gera um arquivo .ipa (sem assinatura) pronto para Sideloadly / AltStore / SideStore
# ou qualquer Apple ID gratuito (Personal Team).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_PATH="${REPO_ROOT}/Examples/SwiftSensorsApp.xcodeproj"
DERIVED_DATA="$(cd "${REPO_ROOT}/.." && pwd)/.build"
DIST_DIR="${REPO_ROOT}/dist"
OUT_IPA="${1:-${DIST_DIR}/ArkDieHuD-unsigned.ipa}"

mkdir -p "$(dirname "${OUT_IPA}")"

echo "🔨 Compilando SwiftSensorsApp (Release, generic/platform=iOS)..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme SwiftSensorsApp \
  -configuration Release \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath "${DERIVED_DATA}" \
  build >/dev/null

APP_BUNDLE="${DERIVED_DATA}/Build/Products/Release-iphoneos/SwiftSensorsApp.app"
if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "❌ Bundle .app não encontrado em: ${APP_BUNDLE}"
  exit 1
fi

STAGING_DIR="$(mktemp -d "${DIST_DIR}/.payload.XXXXXX")"
trap 'rm -rf "${STAGING_DIR}"' EXIT

mkdir -p "${STAGING_DIR}/Payload"
COPYFILE_DISABLE=1 cp -R "${APP_BUNDLE}" "${STAGING_DIR}/Payload/SwiftSensorsApp.app"
find "${STAGING_DIR}" -name "._*" -delete
rm -f "${OUT_IPA}"

ABS_OUT_IPA="$(cd "$(dirname "${OUT_IPA}")" && pwd)/$(basename "${OUT_IPA}")"
(
  cd "${STAGING_DIR}"
  COPYFILE_DISABLE=1 zip -qry "${ABS_OUT_IPA}" Payload
)

echo "✅ IPA gerado com sucesso: ${ABS_OUT_IPA}"
ls -lh "${ABS_OUT_IPA}"
