#!/usr/bin/env python3
"""QUI i18n delta translator.

Reads core/locale/enUS.lua (identity base) + tools/i18n/state.json, computes the
set of new/changed keys per locale, translates ONLY those via translate_fn,
writes QUI_Locale_<loc>/<loc>.lua, and updates state.json.

Usage:
  python3 tools/i18n/translate_delta.py --locales deDE,frFR        # real run
  python3 tools/i18n/translate_delta.py --mock --locales deDE      # offline self-test
The real translator uses the logged-in Codex CLI session.
"""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.i18n.lua_literal import unescape_lua_string
from tools.i18n.translate_gpt_codex import run_codex

LOCALES = ["deDE","esES","esMX","frFR","itIT","ptBR","ruRU","koKR","zhCN","zhTW"]
ENUS = "core/locale/enUS.lua"
STATE = "tools/i18n/state.json"

# Resolved ONCE, mirroring tools/test.sh and tools/check_compile.sh: $LUA wins,
# then lua5.1, then a bare `lua`.
#
# The fallback is not cosmetic. CI provisions Lua with leafo/gh-actions-lua,
# which installs `lua` and `luac` and NEVER a `lua5.1` binary -- which is
# exactly why regen-i18n-base.yml and regen-search-cache.yml apt-get install
# lua5.1 for themselves. Hardcoding "lua5.1" here reddens lua-tests.yml on main
# and on every PR, and reddens release.yml's gates barrier, which leaves a tag
# with ZERO published artifacts.
LUA = os.environ.get("LUA") or shutil.which("lua5.1") or shutil.which("lua")
LUAC = os.environ.get("LUAC") or shutil.which("luac5.1") or shutil.which("luac")


def luac_bin():
    if not LUAC:
        raise SystemExit(
            "no Lua compiler found. Looked at $LUAC, then luac5.1, then luac "
            "on PATH.")
    return LUAC


def lua_bin():
    """The Lua interpreter to shell out to, or a clear error if there is none."""
    if not LUA:
        raise SystemExit(
            "no Lua interpreter found. Looked at $LUA, then lua5.1, then lua on "
            "PATH. WoW runs Lua 5.1 -- prefer lua5.1; a 5.4 binary named `lua` "
            "accepts code that 5.1 rejects (see tools/check_compile.sh).")
    return LUA


def sha1(s): return hashlib.sha1(s.encode("utf-8")).hexdigest()

def read_enus():
    """Parse the generated enUS.lua's key rows into an identity dict.

    enUS.lua ships `ns.LocaleData.keys`, an ordered ARRAY of English strings
    (`    "key",` per row) -- it used to be a keyed identity table, and this
    regex used to read the `["key"] = "value"` shape. The return value is
    unchanged: {key: key}, because enUS was and is an identity mapping.

    Do NOT use this for the positional ID ORDER -- use read_enus_keys(), which
    loads the file through real Lua. This regex USED TO have a blind spot:
    `.` does not cross a newline without re.DOTALL, and Lua's %q writes an
    embedded newline as a backslash followed by an ACTUAL newline byte, so 7
    keys whose text contains a newline never matched here (5721 of 5728).
    Those keys had therefore never entered a translation delta. Fixed by
    passing re.DOTALL below; see tools/i18n/test_enus_parser_agreement.py,
    which pins this function against a real Lua load of enUS.lua and against
    assemble_mt.read_enus() (which used a different, always-correct regex).
    """
    keys = {}
    txt = open(ENUS, encoding="utf-8").read()
    # re.DOTALL is load-bearing: without it, `.` (both in `\\.` and in the
    # negative lookahead `(?!\1).`) does not cross a newline, so this silently
    # dropped every pair whose VALUE contains an embedded newline -- 7 keys
    # that therefore never reached the translation delta in any locale. See
    # tools/i18n/test_enus_parser_agreement.py, which pins this against a real
    # Lua load of enUS.lua.
    for m in re.finditer(r'\n    (["\'])((?:\\.|(?!\1).)*)\1,', txt, re.DOTALL):
        key = unescape_lua_string(m.group(2))
        keys[key] = key  # identity (value == key in enUS)
    return keys


def read_enus_keys(path=ENUS):
    """The ordered `ns.LocaleData.keys` array from an enUS.lua.

    This is the ID assignment: translation N belongs to keys[N]. Loaded by
    actually running the file through Lua -- the same way the WoW client
    loads it -- rather than re-deriving Lua's `%q` escaping rules in a Python
    regex for arbitrary key text (some keys legitimately contain embedded
    newlines, which is exactly what read_enus() above cannot see).

    `path` defaults to the working tree's enUS.lua. tools/i18n/reslot_overlays.py
    passes an OLD copy (extracted from a git ref) to recover the key order the
    committed overlays were written against.

    NUL-joined rather than newline-joined for the same reason: at least one
    real key contains an embedded newline, so newline cannot be the row
    delimiter. A key containing a literal NUL byte is asserted against inside
    the Lua snippet -- addon UI text does not have a legitimate reason to
    contain one.
    """
    # `path` is caller-supplied (reslot_overlays.py passes a tempfile name), so
    # it is escaped before being interpolated into a Lua string literal -- a
    # path containing a quote or a backslash would otherwise terminate the
    # literal and turn the snippet into a syntax error, or worse, into
    # different code.
    quoted = lua_escape(path)
    proc = subprocess.run(
        [lua_bin(), "-e",
         f'local ns = {{}}; assert(loadfile("{quoted}"))("QUI", ns);'
         'local keys = ns.LocaleData and ns.LocaleData.keys;'
         f'assert(type(keys) == "table" and #keys > 0, '
         f'"{quoted}: ns.LocaleData.keys is missing or empty -- run '
         f'tools/i18n/extract_strings.lua");'
         'for i = 1, #keys do '
         'assert(not keys[i]:find("\\0", 1, true), "a key contains a literal NUL byte");'
         'io.write(keys[i], "\\0") '
         'end'],
        capture_output=True, text=True, encoding="utf-8")
    if proc.returncode != 0:
        raise SystemExit(f"reading {path} keys via {lua_bin()} failed:\n{proc.stderr}")
    keys = proc.stdout.split("\0")
    if keys and keys[-1] == "":
        keys.pop()
    return keys


# The `-- keyset: <hex>` line every overlay carries, written by overlay_source.
OVERLAY_KEYSET = re.compile(r"\n-- keyset: ([0-9a-f]+)\n")


def overlay_keyset(loc):
    """The checksum an overlay claims its slots are numbered against, or None."""
    path = overlay_path(loc)
    if not os.path.exists(path):
        return None
    m = OVERLAY_KEYSET.search(open(path, encoding="utf-8").read())
    return m.group(1) if m else None


def read_overlay(loc, enus_keys=None):
    """Read a POSITIONAL overlay back into a {english key: translation} dict.

    Loaded through Lua with the locale gate satisfied, because the table ships
    as a long-bracket string that only exists once loadstring runs -- a regex
    over the file text cannot see it as data, and the positional file has no
    key text in it at all to regex for.

    REFUSES unless the overlay's own `-- keyset:` line matches `enus_keys`.
    Positional data is not self-describing: slot 3000 is just a string, and
    zipping it against the wrong key array re-labels every translation from the
    first point of drift onward -- silently, because the result is still 5,721
    plausible strings. Worse, the obvious repair (merge_translations.py, or a
    real translate_delta run) would then write that mis-zipped dict back out
    with a freshly computed, CORRECT-looking checksum, turning the checksum
    test green over permanently scrambled data. The one thing that can catch
    it is the identity the file already carries, so it is checked here, at the
    only place that turns slots back into keys.

    Held `nil,` slots (keys with no translation) are simply absent from the
    returned dict, which is how every caller already treats an untranslated
    key.
    """
    keys = enus_keys if enus_keys is not None else read_enus_keys()
    path = overlay_path(loc)
    if not os.path.exists(path):
        return {}

    want = keyset_checksum(sorted(keys))
    got = overlay_keyset(loc)
    if got != want:
        raise SystemExit(
            f"{path}: keyset {got or '<absent>'} does not match the key array it is "
            f"being read against ({want}).\n"
            f"  Its slots are numbered for a DIFFERENT enUS key set, so zipping them "
            f"here would silently re-label every translation past the first added or "
            f"removed key.\n"
            f"  Fix: python3 tools/i18n/reslot_overlays.py  (re-numbers all ten "
            f"overlays onto the current core/locale/enUS.lua, preserving every "
            f"translation).")

    proc = subprocess.run(
        [lua_bin(), "-e",
         f'GetLocale = function() return "{loc}" end; QUIDB = nil;'
         f'local ns = {{}}; assert(loadfile("{path}"))("QUI", ns);'
         'local a = ns.LocaleData and ns.LocaleData.active;'
         f'assert(type(a) == "table", "{path}: produced no ns.LocaleData.active table");'
         f'for i = 1, {len(keys)} do local v = a[i]; if v ~= nil then '
         'assert(not v:find("\\0", 1, true), "a translation contains a literal NUL byte");'
         'io.write(i, "\\0", v, "\\0") end end'],
        capture_output=True, text=True, encoding="utf-8")
    if proc.returncode != 0:
        raise SystemExit(f"reading {path} via {lua_bin()} failed:\n{proc.stderr}")
    fields = proc.stdout.split("\0")
    if fields and fields[-1] == "":
        fields.pop()
    out = {}
    for i in range(0, len(fields), 2):
        out[keys[int(fields[i]) - 1]] = fields[i + 1]
    return out

def lua_escape(s): return s.replace("\\","\\\\").replace('"','\\"').replace("\n","\\n")

def keyset_checksum(sorted_keys):
    """Stable fingerprint of the ID assignment.

    Overlays are positional: value N belongs to sorted_keys[N]. Any insertion
    or deletion shifts every later ID, so enUS and all ten overlays must carry
    the SAME checksum or the mapping is corrupt. Hash the joined keys, not the
    count -- two different key sets of equal size must not collide.
    """
    h = hashlib.sha256()
    for k in sorted_keys:
        h.update(k.encode("utf-8"))
        h.update(b"\0")
    return h.hexdigest()[:16]

def overlay_path(loc):
    """The locale overlay is a root-TOC file, next to core/locale/enUS.lua.

    It CANNOT live in a LoadOnDemand addon: core/locale/locale.lua captures
    ns.LocaleData.active as an upvalue at login, so an overlay arriving later
    never reaches ns.L at all. It used to ship as ten LoadOnDemand
    QUI_OptionsSearch_<loc> folders; writing anywhere else produced a file
    nothing loads while the real overlay went untouched.
    """
    return f"core/locale/{loc}.lua"


def overlay_source(loc, table, generator):
    """Emit one overlay chunk: locale gate, then the table as a compiled-on-demand string.

    All ten overlays are listed in QUI.toc, so nine of them load and return
    on every login. As a long-bracket STRING the inactive nine lex one token
    each instead of compiling ~5.7k table fields, and the string is collectable
    the moment the chunk returns: ~36 ms of login compile instead of ~54 ms,
    retaining slightly less. Keep the "]==]" delimiter — a translation may
    legitimately contain "]]".

    `table` must be keyed by the FULL enUS key set, mapping each key to its
    translation or to None. The emitted array is positional -- slot N is
    sorted(table)[N] -- so a caller that passes only the translated subset
    would silently shift every ID after the first gap. write_locale() does
    that expansion; call it rather than this function unless you have already
    expanded (tools/i18n/migrate_overlays_positional.py has).
    """
    lines = ['local want = (QUIDB and QUIDB.global and QUIDB.global.selectedLocale) or GetLocale()',
             f'if want ~= "{loc}" then return end',
             "local ADDON_NAME, ns = ...",
             f"-- GENERATED by {generator} — do not edit by hand.",
             f"-- keyset: {keyset_checksum(sorted(table))}",
             "ns.LocaleData = ns.LocaleData or {}",
             # The long-bracket-string rationale used to be emitted as four
             # comment lines here. The addon tree is kept comment-free
             # (tools/strip_comments.sh) and a generator that emits comments
             # makes its output permanently "stale" against that, so it stays in
             # this function's docstring instead. The banner and the `-- keyset:`
             # line above are emitted deliberately: the first stops an agent
             # hand-editing generated output, the second is the identity
             # read_overlay() refuses to zip positional data without.
             'ns.LocaleData.active = assert(loadstring("return " .. [==[',
             "{"]
    # Positional: slot N is sorted_keys[N]. An untranslated key emits `nil`
    # so the slot is HELD -- omitting it would shift every later ID.
    # Lua arrays truncate at a trailing nil, but ns.L only ever indexes by a
    # known ID and treats a nil slot as "untranslated", so a short tail is safe.
    for k in sorted(table):
        v = table.get(k)
        if v is None:
            lines.append("    nil,")
            continue
        value = lua_escape(v)
        assert "]==]" not in value, f"{loc}: {k!r} contains the long-bracket delimiter"
        lines.append(f'    "{value}",')
    lines.append("}")
    lines.append(f']==], "@core/locale/{loc}.lua"))()\n')
    return "\n".join(lines)


def overlay_bytes(loc, table, generator="tools/i18n/translate_delta.py", keys=None):
    """Render one overlay's complete source text, without touching the disk.

    `table` may be partial (only the keys that actually have a translation).
    The expansion to the full enUS key set happens here, because the file on
    disk is POSITIONAL: every enUS key needs a slot, translated or `nil`, or
    the IDs after the first gap are wrong. This is also what makes the emitted
    `-- keyset:` line equal enUS's own -- both hash the same 5,728 keys.

    `keys` lets a caller supply the enUS key array it has already read. Reading
    it costs a Lua subprocess, so a caller writing all ten overlays should read
    it ONCE and pass it in, rather than paying for ten identical loads -- and,
    more importantly, so that rendering ten files has no failure points left in
    it (see tools/i18n/reslot_overlays.py, which renders all ten before it
    writes any).
    """
    keys = keys if keys is not None else read_enus_keys()
    # A key the caller holds a translation for but enUS no longer has cannot be
    # given a slot -- there is no ID for it. Dropping it is correct (the string
    # is gone from the UI) but it is lost translation work, so say so out loud
    # rather than silently. migrate_overlays_positional.py treats the same
    # condition as a hard error because there it means the OVERLAY is newer
    # than enUS, i.e. the ID mapping itself is suspect.
    orphans = sorted(k for k in table if k not in set(keys))
    if orphans:
        print(f"{loc}: WARNING dropping {len(orphans)} translation(s) whose English key "
              f"is no longer in {ENUS} (no ID to hold them):", file=sys.stderr)
        for k in orphans[:10]:
            print(f"    {k!r}", file=sys.stderr)
        if len(orphans) > 10:
            print(f"    ... and {len(orphans) - 10} more", file=sys.stderr)

    positional = {k: table.get(k) for k in keys}
    return overlay_source(loc, positional, generator)


def write_locale(loc, table, generator="tools/i18n/translate_delta.py"):
    """Render one overlay and write it in place. See overlay_bytes()."""
    open(overlay_path(loc), "w", encoding="utf-8").write(
        overlay_bytes(loc, table, generator))

def real_translate(loc, items):
    # items: list[str] English -> list[str] translations (order-preserved).
    args = argparse.Namespace(
        model=os.environ.get("QUI_I18N_MODEL", "gpt-5.6-luna"),
        reasoning_effort=os.environ.get("QUI_I18N_REASONING_EFFORT", "low"),
        timeout_seconds=int(os.environ.get("QUI_I18N_TIMEOUT_SECONDS", "900")),
    )
    out, BATCH = [], 60
    for i in range(0, len(items), BATCH):
        chunk = items[i:i + BATCH]
        translated = run_codex(loc, chunk, args)
        out.extend(translated[item] for item in chunk)
    return out

def mock_translate(loc, items):
    return [f"[{loc}] {s}" for s in items]   # deterministic, offline

def load_existing(loc):
    """Translations already committed for `loc`, as {english key: translation}.

    Delegates to read_overlay(): the overlay is positional, so its key text
    lives only in enUS.lua and the two files must be zipped by index. Reading
    it with a key/value regex (what this did while overlays were keyed) now
    returns nothing, which would make every caller believe the locale is
    untranslated and overwrite the file with a blank one.
    """
    return read_overlay(loc)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--locales", default=",".join(LOCALES))
    ap.add_argument("--mock", action="store_true")
    args = ap.parse_args()
    translate = mock_translate if args.mock else real_translate
    enus = read_enus()
    manifest = {k: sha1(v) for k, v in enus.items()}
    state = json.load(open(STATE)) if os.path.exists(STATE) else {}
    for loc in [l for l in args.locales.split(",") if l]:
        prev = state.get(loc, {})
        existing = load_existing(loc)
        # new or changed (hash differs) OR missing from the locale file (self-heal
        # if state.json and the locale file ever drift out of sync)
        delta = [k for k in enus if prev.get(k) != manifest[k] or k not in existing]
        if delta:
            translations = translate(loc, [enus[k] for k in delta])
            for k, tv in zip(delta, translations):
                existing[k] = tv
        # drop keys no longer in enUS
        existing = {k: v for k, v in existing.items() if k in enus}
        write_locale(loc, existing)

        # Format/escape parity gate (reuses the Lua validator as source of truth).
        pairs = "return {" + "".join(
            f'[{json.dumps(k, ensure_ascii=False)}]={json.dumps(existing[k], ensure_ascii=False)},' for k in existing) + "}"
        with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as tf:
            tf.write(pairs); tf_path = tf.name
        chk = subprocess.run([lua_bin(),"-e",
            f'local V=assert(loadfile("tools/i18n/validate_format.lua"))();'
            f'local d=V.validate(assert(loadfile("{tf_path}"))());'
            f'if #d>0 then for _,x in ipairs(d) do io.stderr:write(x.key.."\\n") end os.exit(1) end'],
            capture_output=True, text=True)
        os.unlink(tf_path)
        if chk.returncode != 0:
            raise SystemExit(f"{loc}: format parity drift:\n{chk.stderr}")

        state[loc] = {k: manifest[k] for k in existing}
        print(f"{loc}: {len(delta)} translated, {len(existing)} total", file=sys.stderr)
    json.dump(state, open(STATE,"w"), indent=2, sort_keys=True)

if __name__ == "__main__":
    main()
