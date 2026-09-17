import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile

game_versions = runpy.run_path(str(Path(__file__).with_name("toc_game_versions.py")))["game_versions"]


assert game_versions("## Interface: 120105\n") == ["12.1.5"]
assert game_versions("## Interface: 16001\n") == ["1.60.1"]
assert game_versions("## Interface: 120105, 16001\r\n") == ["12.1.5", "1.60.1"]
assert game_versions("## Interface: 120105,16001,120105\n") == ["12.1.5", "1.60.1"]
for invalid in ("", "## Interface: ", "## Interface: 120105,", "## Interface: 12.1.5",
                "## Interface: 120105 junk", "## Interface: 120105\n## Interface: 16001"):
    try:
        game_versions(invalid)
    except ValueError:
        pass
    else:
        raise AssertionError(f"accepted invalid TOC: {invalid!r}")

root = Path(__file__).resolve().parents[1]
script = root / "tools/toc_game_versions.py"
with tempfile.TemporaryDirectory() as directory:
    first, second = Path(directory) / "QUI.toc", Path(directory) / "QUI_Bags.toc"
    first.write_text("## Interface: 120105, 16001\n")
    second.write_text("## Interface: 16001, 120105\n")
    command = [sys.executable, str(script), str(first), str(second)]
    result = subprocess.run(command, capture_output=True, text=True, check=True)
    assert json.loads(result.stdout) == ["12.1.5", "1.60.1"]
    second.write_text("## Interface: 120105\n")
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode != 0 and "Interface targets differ" in result.stderr
    assert not result.stdout
    second.write_text("## Interface: 120105,broken\n")
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode != 0 and not result.stdout

tocs = [root / "QUI.toc", *sorted(root.glob("QUI_*/*.toc"))]
result = subprocess.run([sys.executable, str(script), *map(str, tocs)],
                        capture_output=True, text=True, check=True)
assert json.loads(result.stdout) == ["12.1.5", "1.60.1"]
print(f"TOC version parser: malformed input, suite mismatch, and {len(tocs)} manifests passed")
