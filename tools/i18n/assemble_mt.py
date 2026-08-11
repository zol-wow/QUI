#!/usr/bin/env python3
"""Assemble subagent-produced translations into QUI_Locale_<loc>/<loc>.lua.

Reads tools/i18n/_mt/out_<loc>_*.json (each a JSON object {english_key: translation}),
merges them per locale, verifies every enUS key is covered, writes the locale file,
runs the format-parity gate, and updates state.json.

Usage:
  python3 tools/i18n/assemble_mt.py deDE          # one locale
  python3 tools/i18n/assemble_mt.py               # all locales with out files
"""
import glob, hashlib, json, os, re, subprocess, sys, tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.i18n.lua_literal import unescape_lua_string
from tools.i18n.translate_delta import lua_bin

ENUS = "core/locale/enUS.lua"
STATE = "tools/i18n/state.json"
MT = "tools/i18n/_mt"


def sha1(s): return hashlib.sha1(s.encode("utf-8")).hexdigest()


def read_enus():
    """The ordered English key list from enUS.lua's `ns.LocaleData.keys` array.

    Rows are `    "key",` since the overlays went positional (they were
    `["key"] = "key"` identity pairs before). `[^"]` rather than `.` on
    purpose: Lua's %q writes an embedded newline as a backslash followed by an
    ACTUAL newline byte, and `.` does not cross a newline without re.DOTALL —
    that blind spot is what once hid 7 real keys from the translation
    pipeline.
    """
    txt = open(ENUS, encoding="utf-8").read()
    keys = re.findall(r'\n    "((?:\\.|[^"])*)",', txt)
    return [unescape_lua_string(k) for k in keys]


def lua_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def write_locale(loc, table):
    # Root-TOC overlay, next to core/locale/enUS.lua. It cannot live in a
    # LoadOnDemand addon: core/locale/locale.lua captures ns.LocaleData.active
    # as an upvalue at login. Format (locale gate + the POSITIONAL translation
    # array as a compiled-on-demand string) is owned by
    # translate_delta.write_locale so the two writers cannot drift — and so
    # the expansion of `table` onto the full enUS key set, which is what makes
    # slot N mean key N, has exactly one implementation.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from translate_delta import write_locale as write_positional_locale
    write_positional_locale(loc, table, "tools/i18n (machine translation)")


def format_gate(table):
    pairs = "return {" + "".join(
        f'[{json.dumps(k, ensure_ascii=False)}]={json.dumps(v, ensure_ascii=False)},' for k, v in table.items()) + "}"
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as tf:
        tf.write(pairs); p = tf.name
    chk = subprocess.run(
        [lua_bin(), "-e",
         f'local V=assert(loadfile("tools/i18n/validate_format.lua"))();'
         f'local d=V.validate(assert(loadfile("{p}"))());'
         f'if #d>0 then for _,x in ipairs(d) do io.stderr:write(x.key.."\\n") end os.exit(1) end'],
        capture_output=True, text=True)
    os.unlink(p)
    return chk.returncode == 0, chk.stderr


def assemble(loc, enus_keys, state):
    files = sorted(glob.glob(f"{MT}/out_{loc}_*.json"))
    if not files:
        print(f"{loc}: no out files, skipping", file=sys.stderr); return False
    table = {}
    for f in files:
        table.update(json.load(open(f, encoding="utf-8")))
    table = {k: v for k, v in table.items() if k in set(enus_keys)}
    missing = [k for k in enus_keys if k not in table]
    if missing:
        print(f"{loc}: MISSING {len(missing)}/{len(enus_keys)} keys "
              f"(first: {missing[0]!r}) — re-run those shards", file=sys.stderr)
        return False
    ok, err = format_gate(table)
    if not ok:
        print(f"{loc}: FORMAT DRIFT:\n{err}", file=sys.stderr); return False
    write_locale(loc, table)
    manifest = {k: sha1(k) for k in enus_keys}
    state[loc] = {k: manifest[k] for k in table}
    print(f"{loc}: assembled {len(table)} keys, format gate OK")
    return True


def main():
    enus_keys = read_enus()
    state = json.load(open(STATE)) if os.path.exists(STATE) else {}
    locs = sys.argv[1:] or sorted(
        {os.path.basename(f).split("_")[1] for f in glob.glob(f"{MT}/out_*_*.json")})
    ok_all = True
    for loc in locs:
        if not assemble(loc, enus_keys, state):
            ok_all = False
    json.dump(state, open(STATE, "w"), indent=2, sort_keys=True)
    sys.exit(0 if ok_all else 1)


if __name__ == "__main__":
    main()
