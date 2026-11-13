"""Deliberately small fake for transport tests, not proof of CLI compatibility."""

import json
import os
from pathlib import Path
import shutil
import sys

args = sys.argv[1:]
home = Path(os.environ["HOME"])
if args == ["--version"]:
    print(os.environ.get("SKILLS_TEST_VERSION", "1.7.6"))
    sys.exit(0)

with (home / "calls.jsonl").open("a") as calls:
    calls.write(json.dumps(args) + "\n")
assert os.environ["DISABLE_TELEMETRY"] == "1"
if os.environ.get("SKILLS_TEST_FAIL"):
    sys.exit("fixture action failed")

lock = Path(os.environ["XDG_STATE_HOME"]) / "skills/.skill-lock.json"
data = json.loads(lock.read_text()) if lock.exists() else {"version": 3, "skills": {}}
results = []
if args[0] == "add":
    assert os.environ["GIT_TERMINAL_PROMPT"] == "0"
    assert args[2] == "--skill"
    end = args.index("--global")
    assert args[end:] == ["--global", "--agent", "codex", "--copy", "--yes", "--json"]
    url, ref = args[1].rsplit("#", 1)
    for skill in args[3:end]:
        target = home / ".agents/skills" / skill
        target.mkdir(parents=True, exist_ok=True)
        (target / "SKILL.md").write_text("fixture\n")
        data["skills"][skill] = {"sourceUrl": url, "ref": ref, "sourceType": "github"}
        results.append({
            "name": skill, "status": "installed",
            "source": url.removeprefix("https://github.com/").removesuffix(".git"), "ref": ref,
            "path": str(target), "scope": "global", "agents": ["Codex"], "mode": "copy",
        })
elif args[0] == "remove":
    skill = args[1]
    assert args[2:] == ["--global", "--agent", "codex", "--yes"]
    if not os.environ.get("SKILLS_TEST_RETAIN"):
        shutil.rmtree(home / ".agents/skills" / skill, ignore_errors=True)
        data["skills"].pop(skill, None)
else:
    raise AssertionError(args)

lock.parent.mkdir(parents=True, exist_ok=True)
lock.write_text(json.dumps(data))
if args[0] == "add":
    mode = os.environ.get("SKILLS_TEST_RESULT")
    if mode == "invalid":
        print("not json")
        sys.exit(0)
    if mode == "missing":
        results = []
    elif mode == "extra":
        results.append({**results[0], "name": "unexpected"})
    elif mode == "duplicate":
        results.append(results[0])
    elif mode:
        results[0].update(json.loads(mode))
    print(json.dumps(results))
