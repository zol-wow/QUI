#!/usr/bin/env bash
# Regenerate core/locale/enUS.lua and the single English search cache.
#
# Neither per-locale search caches nor per-locale addon folders exist any more:
#
#   * The cached strings are ns.L keys and QUI_Options localizes them at
#     apply time (GUI:PrepareSearchEntry), so a translated cache would be both
#     redundant and unlocalizable a second time.
#   * The translation overlays are plain root-TOC files (core/locale/<loc>.lua)
#     written by tools/i18n/translate_delta.py. They must load at login —
#     core/locale/locale.lua captures ns.LocaleData.active as an UPVALUE — so
#     there is no TOC of their own left to generate here.
#
# This script therefore only runs the two generators, in order: the key file
# first (historically the step everyone forgot — "enUS" used to mean only the
# enUS SEARCH CACHE, never core/locale/enUS.lua), then the cache.
set -euo pipefail
LUA_BIN="${LUA:-lua}"
LOCALES="deDE esES esMX frFR itIT ptBR ruRU koKR zhCN zhTW"

"${LUA_BIN}" tools/i18n/extract_strings.lua                      # core/locale/enUS.lua

# extract_strings.lua has no SHA-256 available (Lua 5.1 stdlib, nothing
# vendored) so the `-- keyset: <hex>` checksum line -- the fingerprint every
# overlay's positional IDs are checked against -- is stamped on the Python
# side instead, reusing the ONE keyset_checksum() implementation that
# translate_delta.py's overlay writer also calls.
python3 tools/i18n/stamp_enus_keyset.py                          # keyset line

"${LUA_BIN}" tools/generate_search_cache.lua                     # the one English cache

# Overlays are not generated here, but a missing one is a packaging bug worth
# catching early: the TOC lists all ten unconditionally.
missing=""
for loc in ${LOCALES}; do
  [ -f "core/locale/${loc}.lua" ] || missing="${missing} ${loc}"
done
if [ -n "${missing}" ]; then
  echo "ERROR: QUI.toc lists locale overlays that do not exist:${missing}" >&2
  echo "Restore them or run tools/i18n/translate_delta.py for those locales." >&2
  exit 1
fi

echo "generated core/locale/enUS.lua + the enUS search cache; ${LOCALES} overlays present"
