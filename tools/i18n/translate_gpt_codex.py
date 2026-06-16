#!/usr/bin/env python3
"""Generate MT shard JSON files through `codex exec` GPT models.

The output files are consumed by tools/i18n/assemble_mt.py:
  tools/i18n/_mt/out_<locale>_<shard>.json
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.i18n.lua_literal import unescape_lua_string
ENUS = ROOT / "core/locale/enUS.lua"
MT_DIR = ROOT / "tools/i18n/_mt"

LOCALES = ["esES", "esMX", "frFR", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW"]

LANG_NAMES = {
    "esES": "Spanish for Spain",
    "esMX": "Spanish for Latin America",
    "frFR": "French",
    "itIT": "Italian",
    "ptBR": "Brazilian Portuguese",
    "ruRU": "Russian",
    "koKR": "Korean",
    "zhCN": "Simplified Chinese",
    "zhTW": "Traditional Chinese",
}


def read_enus():
    txt = ENUS.read_text(encoding="utf-8")
    keys = re.findall(r'\["((?:\\.|[^"])*)"\]\s*=', txt)
    return [unescape_lua_string(k) for k in keys]


def shard_path(loc, shard_index):
    return MT_DIR / f"out_{loc}_{shard_index:03d}.json"


def valid_existing(path, keys):
    if not path.exists():
        return False
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return False
    return sorted(data.keys()) == sorted(keys) and all(isinstance(v, str) for v in data.values())


def prompt_for(loc, keys):
    lang = LANG_NAMES.get(loc, loc)
    payload = {str(i): key for i, key in enumerate(keys)}
    return (
        f"You are localizing QUI, a World of Warcraft addon UI, into {lang} "
        f"for locale {loc}.\n\n"
        "Translate every English string in the JSON object below. Return JSON with "
        "a single `translations` object whose keys exactly match the numeric input "
        "IDs. Do not reorder by meaning; each output ID must translate only the "
        "English string at the same input ID. Do not use tools. Do not add notes.\n\n"
        "Rules:\n"
        "- Preserve printf/Lua format specifiers exactly: %1$s, %2$d, %s, %d, %%, etc. "
        "Do not add, remove, or change specifiers.\n"
        "- Preserve WoW UI escapes exactly: |cff... color codes, |r, |T...|t, |H...|h.\n"
        "- Preserve slash commands and code/config tokens exactly, such as /qui, /reload, dbKey, CVar, API names, IDs, and enum-like values.\n"
        "- Keep addon/proper names such as QUI and Blizzard unchanged unless the localized WoW client normally translates that term.\n"
        "- Keep the tone terse and natural for in-game settings labels and descriptions.\n"
        "- Translate human-readable English only.\n\n"
        "Input JSON object:\n"
        + json.dumps(payload, ensure_ascii=False, sort_keys=True)
    )


def schema_for(count):
    props = {str(i): {"type": "string"} for i in range(count)}
    return {
        "type": "object",
        "properties": {
            "translations": {
                "type": "object",
                "properties": props,
                "required": list(props),
                "additionalProperties": False,
            }
        },
        "required": ["translations"],
        "additionalProperties": False,
    }


def run_codex(loc, keys, args):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as schema_file:
        json.dump(schema_for(len(keys)), schema_file)
        schema_path = schema_file.name
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as output_file:
        output_path = output_file.name
    cmd = [
        "codex", "exec",
        "--ephemeral",
        "--ignore-user-config",
        "--ignore-rules",
        "-C", str(ROOT),
        "-m", args.model,
        "-c", f'model_reasoning_effort="{args.reasoning_effort}"',
        "--output-schema", schema_path,
        "-o", output_path,
        "-",
    ]
    env = os.environ.copy()
    env.setdefault("NO_COLOR", "1")
    try:
        result = subprocess.run(
            cmd,
            input=prompt_for(loc, keys),
            text=True,
            capture_output=True,
            env=env,
            timeout=args.timeout_seconds,
        )
        if result.returncode != 0:
            sys.stderr.write(result.stdout)
            sys.stderr.write(result.stderr)
            raise RuntimeError(f"{loc}: codex exited {result.returncode}")
        raw = Path(output_path).read_text(encoding="utf-8")
        parsed = json.loads(raw)
        translations_by_id = parsed["translations"]
        if len(translations_by_id) != len(keys):
            raise RuntimeError(f"{loc}: expected {len(keys)} translations, got {len(translations_by_id)}")
        translations = [translations_by_id[str(i)] for i in range(len(keys))]
        if not all(isinstance(v, str) for v in translations):
            raise RuntimeError(f"{loc}: non-string translation returned")
        return dict(zip(keys, translations))
    finally:
        Path(schema_path).unlink(missing_ok=True)
        Path(output_path).unlink(missing_ok=True)


def translate_shard(task):
    loc, shard_index, shard_keys, path, args = task
    if not args.force and valid_existing(path, shard_keys):
        return f"{loc} shard {shard_index}: existing {path}, skipped"
    last_error = None
    for attempt in range(1, args.retries + 2):
        try:
            table = run_codex(loc, shard_keys, args)
            path.write_text(json.dumps(table, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            return f"{loc} shard {shard_index}: wrote {path} ({len(shard_keys)} strings)"
        except Exception as e:
            last_error = e
            if attempt <= args.retries:
                time.sleep(2 * attempt)
    raise RuntimeError(f"{loc} shard {shard_index}: {last_error}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--locales", default=",".join(LOCALES))
    ap.add_argument("--shard-size", type=int, default=250)
    ap.add_argument("--model", default="gpt-5.4-mini")
    ap.add_argument("--reasoning-effort", default="low")
    ap.add_argument("--timeout-seconds", type=int, default=900)
    ap.add_argument("--jobs", type=int, default=1)
    ap.add_argument("--max-shards", type=int, default=0,
                    help="Stop after this many shards per locale; 0 means no limit.")
    ap.add_argument("--retries", type=int, default=1)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    keys = read_enus()
    MT_DIR.mkdir(parents=True, exist_ok=True)

    tasks = []
    for loc in [x for x in args.locales.split(",") if x]:
        for shard_index, start in enumerate(range(0, len(keys), args.shard_size), 1):
            if args.max_shards and shard_index > args.max_shards:
                break
            shard_keys = keys[start:start + args.shard_size]
            tasks.append((loc, shard_index, shard_keys, shard_path(loc, shard_index), args))

    if args.jobs <= 1:
        for task in tasks:
            print(f"{task[0]} shard {task[1]}: translating {len(task[2])} strings", flush=True)
            print(translate_shard(task), flush=True)
        return

    with ThreadPoolExecutor(max_workers=args.jobs) as executor:
        futures = {}
        for task in tasks:
            print(f"{task[0]} shard {task[1]}: queued {len(task[2])} strings", flush=True)
            futures[executor.submit(translate_shard, task)] = task
        for future in as_completed(futures):
            print(future.result(), flush=True)


if __name__ == "__main__":
    main()
