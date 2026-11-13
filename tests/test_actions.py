"""Run action hooks with a local fake CLI; never fetch or install real skills."""

import json
from pathlib import Path
import shutil
import subprocess
import sys

from test_status import MISE, MiseFixture, PIN


class PackageActionTests(MiseFixture):
    def setUp(self):
        super().setUp()
        cli = Path(self.env["MISE_DATA_DIR"]) / "installs/npm-skills/1.7.6/node_modules/.bin/skills"
        cli.parent.mkdir(parents=True)
        cli.write_text(f"#!{sys.executable}\n" + '''
import json
import os
from pathlib import Path
import shutil
import sys

args = sys.argv[1:]
home = Path(os.environ["HOME"])
with (home / "calls.jsonl").open("a") as calls:
    calls.write(json.dumps(args) + "\\n")
assert os.environ["DISABLE_TELEMETRY"] == "1"
lock = Path(os.environ["XDG_STATE_HOME"]) / "skills/.skill-lock.json"
data = json.loads(lock.read_text()) if lock.exists() else {"version": 3, "skills": {}}
if args[0] == "add":
    assert os.environ["GIT_TERMINAL_PROMPT"] == "0"
    assert args[2] == "--skill"
    assert args[4:] == ["--global", "--agent", "codex", "--copy", "--yes", "--json"]
    skill = args[3]
    url, ref = args[1].rsplit("#", 1)
    target = home / ".agents/skills" / skill
    target.mkdir(parents=True, exist_ok=True)
    (target / "SKILL.md").write_text("fixture\\n")
    data["skills"][skill] = {"sourceUrl": url, "ref": ref}
elif args[0] == "remove":
    skill = args[1]
    assert args[2:] == ["--global", "--agent", "codex", "--yes"]
    shutil.rmtree(home / ".agents/skills" / skill)
    del data["skills"][skill]
else:
    raise AssertionError(args)
lock.parent.mkdir(parents=True, exist_ok=True)
lock.write_text(json.dumps(data))
''')
        cli.chmod(0o755)
        self.env["PATH"] = str(cli.parent) + ":" + self.env["PATH"]

    def action(self, *args):
        result = subprocess.run(
            [MISE, "bootstrap", "packages", *args], cwd=self.project,
            env=self.env, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def calls(self):
        path = self.home / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_apply_missing_then_skip_matching(self):
        self.action("apply")
        self.assertEqual(self.status()["skills"]["packages"][0]["installed_version"], PIN)
        self.assertEqual(len(self.calls()), 1)
        self.action("apply")
        self.assertEqual(len(self.calls()), 1)

    def test_apply_changed_pin(self):
        self.record(ref="b" * 40)
        self.install_files()
        self.action("apply")
        self.assertEqual(self.status()["skills"]["packages"][0]["installed_version"], PIN)

    def test_apply_without_mise_data_dir_uses_xdg(self):
        del self.env["MISE_DATA_DIR"]
        self.action("apply")
        self.assertEqual(self.status()["skills"]["packages"][0]["installed_version"], PIN)

    def test_apply_without_data_overrides_uses_home(self):
        original = Path(self.env.pop("MISE_DATA_DIR"))
        del self.env["XDG_DATA_HOME"]
        default = self.home / ".local/share/mise"
        default.parent.mkdir(parents=True)
        shutil.move(str(original), str(default))
        self.action("apply")
        self.assertEqual(self.status()["skills"]["packages"][0]["installed_version"], PIN)

    def test_explicit_mise_data_dir_takes_precedence(self):
        original = Path(self.env["MISE_DATA_DIR"])
        override = self.root / "custom-mise-data"
        shutil.move(str(original), str(override))
        self.env["MISE_DATA_DIR"] = str(override)
        self.action("apply")
        self.assertEqual(self.status()["skills"]["packages"][0]["installed_version"], PIN)

    def test_apply_restores_deleted_directory_with_existing_lock(self):
        self.action("apply")
        (self.target / "SKILL.md").unlink()
        self.target.rmdir()
        self.assertIn("demo", json.loads(self.lock.read_text())["skills"])
        self.action("apply")
        self.assertTrue((self.target / "SKILL.md").is_file())
        self.assertEqual(len(self.calls()), 2)

    def test_upgrade_changed_pin(self):
        self.record(ref="b" * 40)
        self.install_files()
        self.action("upgrade")
        self.assertEqual(self.status()["skills"]["packages"][0]["installed_version"], PIN)

    def test_prune_mise_installed_fixture(self):
        self.action("apply")
        self.declare()
        self.action("prune", "--manager", "skills")
        self.assertFalse(self.target.exists())
        self.assertNotIn("demo", json.loads(self.lock.read_text())["skills"])
        self.assertEqual(self.calls()[-1][0], "remove")
