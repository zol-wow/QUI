import json
from pathlib import Path
import re
import sys


def game_versions(toc):
    headers = re.findall(r"^## Interface:[ \t]*(.*)$", toc, re.MULTILINE)
    if len(headers) != 1:
        raise ValueError("expected one Interface header")
    values = [value.strip() for value in headers[0].split(",")]
    if not all(re.fullmatch(r"[1-9][0-9]{4,5}", value) for value in values):
        raise ValueError("expected comma-separated five or six digit interface numbers")
    interfaces = list(dict.fromkeys(map(int, values)))
    return [f"{value // 10000}.{value // 100 % 100}.{value % 100}" for value in interfaces]


if __name__ == "__main__":
    try:
        if len(sys.argv) < 2:
            raise ValueError("usage: toc_game_versions.py TOC [TOC ...]")
        versions = game_versions(Path(sys.argv[1]).read_text())
        for filename in sys.argv[2:]:
            if set(game_versions(Path(filename).read_text())) != set(versions):
                raise ValueError(f"{filename}: Interface targets differ from {sys.argv[1]}")
        print(json.dumps(versions))
    except (OSError, ValueError) as error:
        sys.exit(str(error))
