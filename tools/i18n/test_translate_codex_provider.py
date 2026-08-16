#!/usr/bin/env python3
import os
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.i18n import translate_delta


calls = []


def fake_run_codex(loc, items, args):
    calls.append((loc, list(items), args.model, args.reasoning_effort, args.timeout_seconds))
    return {item: f"{loc}:{item}" for item in items}


original = translate_delta.run_codex
try:
    translate_delta.run_codex = fake_run_codex
    os.environ["QUI_I18N_MODEL"] = "test-model"
    os.environ["QUI_I18N_REASONING_EFFORT"] = "medium"
    os.environ["QUI_I18N_TIMEOUT_SECONDS"] = "12"
    items = [f"key-{i}" for i in range(61)]
    got = translate_delta.real_translate("deDE", items)
finally:
    translate_delta.run_codex = original
    os.environ.pop("QUI_I18N_MODEL", None)
    os.environ.pop("QUI_I18N_REASONING_EFFORT", None)
    os.environ.pop("QUI_I18N_TIMEOUT_SECONDS", None)

assert got == [f"deDE:{item}" for item in items]
assert [len(call[1]) for call in calls] == [60, 1]
assert all(call[2:] == ("test-model", "medium", 12) for call in calls)

translate_delta.run_codex = fake_run_codex
try:
    translate_delta.real_translate("deDE", ["default"])
finally:
    translate_delta.run_codex = original

assert calls[-1][2:] == ("gpt-5.6-luna", "low", 900)
print("test_translate_codex_provider OK")
