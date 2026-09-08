#!/bin/bash
# App Store validation (ITMS-90291) requires each *.framework to include:
#   Resources -> Versions/Current/Resources
# (exact relative path). Dart native assets may omit this or use Versions/A/Resources.

set -euo pipefail

APP="${BUILT_PRODUCTS_DIR:?}/${WRAPPER_NAME:-${PRODUCT_NAME:?}.app}"
FW_DIR="${APP}/Contents/Frameworks"
readonly WANT_RESOURCES_LINK="Versions/Current/Resources"

if [[ ! -d "${FW_DIR}" ]]; then
  exit 0
fi

fix_one_framework() {
  local fw="$1"
  [[ -d "${fw}" ]] || return 0

  if [[ -e "${fw}/Resources" ]] && [[ ! -L "${fw}/Resources" ]]; then
    return 0
  fi
  if [[ ! -d "${fw}/Versions" ]]; then
    return 0
  fi

  local ver=""
  if [[ -d "${fw}/Versions/A" ]]; then
    ver="A"
  else
    for d in "${fw}/Versions"/*; do
      [[ -d "${d}" ]] || continue
      local base
      base="$(basename "${d}")"
      [[ "${base}" == "Current" ]] && continue
      ver="${base}"
      break
    done
  fi
  if [[ -z "${ver}" ]] || [[ ! -d "${fw}/Versions/${ver}" ]]; then
    return 0
  fi

  mkdir -p "${fw}/Versions/${ver}/Resources"

  if [[ ! -e "${fw}/Versions/Current" ]]; then
    ln -sf "${ver}" "${fw}/Versions/Current"
  fi

  local need_link=0
  if [[ ! -e "${fw}/Resources" ]]; then
    need_link=1
  elif [[ -L "${fw}/Resources" ]]; then
    local cur
    cur="$(readlink "${fw}/Resources")"
    if [[ "${cur}" != "${WANT_RESOURCES_LINK}" ]]; then
      rm "${fw}/Resources"
      need_link=1
    fi
  fi

  if [[ "${need_link}" -eq 1 ]]; then
    (cd "${fw}" && ln -sf "${WANT_RESOURCES_LINK}" "Resources")
    if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]] && [[ "${CODE_SIGN_IDENTITY:-}" != "-" ]]; then
      /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
        --preserve-metadata=identifier,entitlements,flags \
        --generate-entitlement-der \
        "${fw}"
    fi
  fi
}

shopt -s nullglob
for fw in "${FW_DIR}"/*.framework; do
  fix_one_framework "${fw}"
done
