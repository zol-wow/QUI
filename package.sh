#!/usr/bin/env bash
#
# Package QUI and its sibling addon suite into a distributable zip file.
# Usage: ./package.sh [output_dir] [alias]
#   output_dir - where to write the zip (default: current directory)
#   alias      - optional alternate addon prefix (e.g. QUI5). When set, the
#                zip folders, TOC filenames, dependencies, paths, SavedVariables,
#                and addon identity are rewritten so WoW treats the deploy as a
#                separate addon suite with isolated settings.
#
# The zip contains top-level folders ready to drop into Interface/AddOns:
# QUI/ plus every discovered QUI_*/ sibling addon, or the alias equivalents.

set -euo pipefail

ADDON_DIR="$(cd "$(dirname "$0")" && pwd)"
MAIN_ADDON="QUI"
OUTPUT_DIR="${1:-$(pwd)}"
ALIAS="${2:-}"
DEPLOY_NAME="${ALIAS:-$MAIN_ADDON}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

VERSION=$(grep -m1 '^## Version:' "$ADDON_DIR/$MAIN_ADDON.toc" | sed 's/## Version: *//')
if [[ -z "$VERSION" ]]; then
    echo "Error: could not read version from $MAIN_ADDON.toc" >&2
    exit 1
fi

GIT_SUFFIX=""
if git -C "$ADDON_DIR" rev-parse --git-dir &>/dev/null; then
    BRANCH=$(git -C "$ADDON_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    if [[ -n "$BRANCH" ]]; then
        GIT_SUFFIX="-${BRANCH//\//-}"
    fi
    SHORT_HASH=$(git -C "$ADDON_DIR" rev-parse --short HEAD 2>/dev/null || true)
    if [[ -n "$SHORT_HASH" ]]; then
        GIT_SUFFIX="${GIT_SUFFIX}-${SHORT_HASH}"
    fi
    if ! git -C "$ADDON_DIR" diff --quiet HEAD -- 2>/dev/null; then
        GIT_SUFFIX="${GIT_SUFFIX}-dirty"
    fi
fi

ZIP_NAME="${DEPLOY_NAME}_v${VERSION}${GIT_SUFFIX}.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"

cleanup_staging() {
    if [[ -z "${STAGING_ROOT:-}" || ! -d "$STAGING_ROOT" ]]; then
        return
    fi

    case "$STAGING_ROOT" in
        "${TMPDIR:-/tmp}"/*|/tmp/*)
            rm -rf -- "$STAGING_ROOT"
            ;;
        *)
            echo "Warning: refusing to delete unexpected path: $STAGING_ROOT" >&2
            ;;
    esac
}

if [[ ! -x "$ADDON_DIR/copy-all.sh" ]]; then
    echo "Error: copy-all.sh is missing or not executable" >&2
    exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
    echo "Missing required command: zip" >&2
    exit 1
fi

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/qui-package.XXXXXXXX")"
readonly STAGING_ROOT
trap cleanup_staging EXIT

echo "Packaging $DEPLOY_NAME v${VERSION}${GIT_SUFFIX} ..."

copy_args=(beta)
if [[ -n "$ALIAS" ]]; then
    copy_args+=("$ALIAS")
fi
QUI_ADDONS_DIR="$STAGING_ROOT" "$ADDON_DIR/copy-all.sh" "${copy_args[@]}"

DEPLOY_DIR_NAMES=("$DEPLOY_NAME")
while IFS= read -r deploy_dir; do
    deploy_basename="$(basename "$deploy_dir")"
    if [[ "$deploy_basename" == "${DEPLOY_NAME}_Debug" || "$deploy_basename" == "${DEPLOY_NAME}_Logger" ]]; then
        continue
    fi
    DEPLOY_DIR_NAMES+=("$deploy_basename")
done < <(find "$STAGING_ROOT" -maxdepth 1 -type d -name "${DEPLOY_NAME}_*" -print | sort)

for forbidden_dir in tests tools docs .git .github; do
    if find "$STAGING_ROOT" -type d -name "$forbidden_dir" -print | head -n 1 | grep -q .; then
        echo "Error: non-runtime directory would be packaged: $forbidden_dir" >&2
        exit 1
    fi
done

rm -f "$ZIP_PATH"
(
    cd "$STAGING_ROOT"
    zip -r "$ZIP_PATH" "${DEPLOY_DIR_NAMES[@]}"
)

echo ""
echo "Created: $ZIP_PATH"
echo "Size:    $(du -h "$ZIP_PATH" | cut -f1)"
echo "Included addon folders:"
for deploy_dir in "${DEPLOY_DIR_NAMES[@]}"; do
    echo "  $deploy_dir"
done
