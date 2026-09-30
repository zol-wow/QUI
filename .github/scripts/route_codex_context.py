"""Resolve trusted branch metadata; issue text is report data, never commands."""
import json
import re
import sys
from pathlib import Path


def resolve(item, pull=None, repository="zol-wow/QUI"):
    if pull is not None:
        head = pull.get("head", {})
        branch = head.get("ref", "")
        if head.get("repo", {}).get("full_name") != repository:
            return {"allowed": "false", "reason": "fork"}
        if not re.fullmatch(r"[A-Za-z0-9_./-]+", branch) or ".." in branch:
            return {"allowed": "false", "reason": "invalid-pr-context"}
        # A follow-up change targets the existing PR HEAD, preserving its work.
        return {"allowed": "true", "checkout_ref": branch, "base_ref": branch, "reason": "pr-head"}
    labels = {label if isinstance(label, str) else label.get("name", "") for label in item.get("labels", [])}
    branches = labels & {"branch:alpha", "branch:beta"}
    if len(branches) > 1:
        return {"allowed": "false", "reason": "conflicting-branch-labels"}
    if branches:
        branch = next(iter(branches)).split(":")[1]
        return {"allowed": "true", "checkout_ref": branch, "base_ref": branch, "reason": "confirmed-branch-label"}
    body = str(item.get("body") or "")
    # Explicit issue-form fields and reported prerelease versions provide branch
    # context. Arbitrary instructions such as "run on beta" do not select a ref.
    reported = set(re.findall(r"(?im)^\s*(?:\*\*)?(?:affected\s+)?branch(?:\*\*)?\s*:\s*(alpha|beta)\b", body))
    reported.update(re.findall(r"(?i)\bv?\d+\.\d+(?:\.\d+)?[-.](alpha|beta)\d*\b", body + " " + str(item.get("title") or "")))
    reported = {branch.lower() for branch in reported}
    if len(reported) != 1:
        return {"allowed": "false", "reason": "ambiguous-release-context"}
    branch = next(iter(reported))
    return {"allowed": "true", "checkout_ref": branch, "base_ref": branch, "reason": "reported-release-context"}


if __name__ == "__main__":
    item_path, pull_path, repository = sys.argv[1:]
    item = json.loads(Path(item_path).read_text())
    pull = json.loads(Path(pull_path).read_text()) if Path(pull_path).is_file() else None
    if item.get("pull_request") and pull is None:
        raise SystemExit("PR metadata unavailable; refusing issue fallback")
    result = resolve(item, pull, repository)
    for key, value in result.items():
        print(f"{key}={value}")
