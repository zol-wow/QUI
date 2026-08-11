#!/usr/bin/env python3
"""Every enUS parser must agree with a real Lua load.

Three parsers read core/locale/enUS.lua: translate_delta.read_enus (regex),
assemble_mt.read_enus (a DIFFERENT regex), and the real-Lua loader used by the
overlay migration. Two of them once disagreed -- translate_delta's pattern used
`.` without re.DOTALL, so it dropped every pair whose VALUE contained an
embedded newline, and the 7 keys it lost were never translated in any locale.

Run: python3 tools/i18n/test_enus_parser_agreement.py
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from assemble_mt import read_enus as read_assemble      # noqa: E402
from translate_delta import read_enus as read_delta, lua_bin   # noqa: E402

LUA_COUNT = r'''
local ns = {}
assert(loadfile("core/locale/enUS.lua"))("QUI", ns)
local d = ns.LocaleData.enUS or ns.LocaleData.keys
local n = 0
for _ in pairs(d) do n = n + 1 end
print(n)
'''


def main():
    # lua_bin() resolves $LUA, then lua5.1, then lua on PATH -- the same
    # resolution translate_delta.py and tools/test.sh already use. A
    # hardcoded "lua5.1" here would redden CI, which provisions only
    # `lua`/`luac` (see the LUA constant's docstring in translate_delta.py).
    truth = int(subprocess.run(
        [lua_bin(), "-e", LUA_COUNT], capture_output=True, text=True, check=True
    ).stdout.strip())

    delta = len(read_delta())
    assemble = len(read_assemble())

    failures = []
    if delta != truth:
        failures.append(f"translate_delta.read_enus() -> {delta}, real Lua -> {truth}")
    if assemble != truth:
        failures.append(f"assemble_mt.read_enus() -> {assemble}, real Lua -> {truth}")

    if failures:
        print("FAIL: enUS parsers disagree with a real Lua load", file=sys.stderr)
        for f in failures:
            print("  " + f, file=sys.stderr)
        return 1

    print(f"OK: test_enus_parser_agreement ({truth} keys, all parsers agree)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
