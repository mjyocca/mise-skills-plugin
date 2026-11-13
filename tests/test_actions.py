"""Run action hooks with a local fake CLI; never fetch or install real skills."""

import json
from pathlib import Path
import shutil
import subprocess

from test_status import MISE, MiseFixture, PIN


class PackageActionTests(MiseFixture):
    def action(self, *args, error=None):
        result = subprocess.run(
            [MISE, "bootstrap", "packages", *args], cwd=self.project,
            env=self.env, capture_output=True, text=True, timeout=30,
        )
        if error:
            self.assertNotEqual(result.returncode, 0, result.stderr)
            self.assertIn(error, result.stderr)
        else:
            self.assertEqual(result.returncode, 0, result.stderr)

    def calls(self):
        path = self.home / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_apply_missing_then_skip_matching(self):
        self.action("apply")
        self.assertEqual(self.status()["skills"]["packages"][0]["installed_version"], PIN)
        self.assertEqual(len(self.calls()), 1)
        self.assertFalse((self.project / "injected").exists())
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

    def test_apply_dry_run_does_not_invoke_cli(self):
        self.action("apply", "--dry-run")
        self.assertEqual(self.calls(), [])
        self.assertFalse(self.target.exists())
        self.assertFalse(self.lock.exists())

    def test_upgrade_dry_run_does_not_invoke_cli(self):
        self.record(ref="b" * 40)
        self.install_files()
        before = self.lock.read_bytes()
        self.action("upgrade", "--dry-run")
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.lock.read_bytes(), before)

    def test_upgrade_current_pin_is_noop(self):
        self.record()
        self.install_files()
        self.action("upgrade")
        self.assertEqual(self.calls(), [])

    def test_action_failure_is_reported(self):
        self.env["SKILLS_TEST_FAIL"] = "1"
        self.action("apply", error="fixture action failed")

    def test_incompatible_cli_is_rejected_before_mutation(self):
        self.env["SKILLS_TEST_VERSION"] = "9.0.0"
        self.action("apply", error="Unsupported skills CLI version")
        self.assertEqual(self.calls(), [])

    def test_json_result_is_validated(self):
        modes = {
            "invalid": "Invalid skills add JSON",
            "missing": "Missing skills add results",
            "extra": "Unexpected or duplicate",
            "duplicate": "Unexpected or duplicate",
        }
        for field, value in {
            "status": "skipped", "source": "foreign/repo", "ref": "main",
            "scope": "project", "mode": "symlink", "agents": ["codex"], "path": "/outside",
        }.items():
            modes[json.dumps({field: value})] = "Skills add result did not confirm"
        for i, (mode, error) in enumerate(modes.items()):
            with self.subTest(mode=mode):
                self.declare(f"result-{i}")
                self.env["SKILLS_TEST_RESULT"] = mode
                self.action("apply", error=error)

    def test_shell_substitution_in_pin_is_rejected(self):
        (self.project / "mise.toml").write_text(
            '[bootstrap.packages]\n"skills:example/skills/demo" = "$(touch injected)"\n'
        )
        self.action("apply", error="Expected a full 40-character")
        self.assertFalse((self.project / "injected").exists())
        self.assertEqual(self.calls(), [])

    def test_same_source_is_batched(self):
        self.declare("demo", "other")
        self.action("apply")
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual(set(self.calls()[0][3:5]), {"demo", "other"})

    def test_unpinned_cli_selector_is_rejected_without_mutation(self):
        self.declare("demo", "other")
        self.action("apply", "skills:example/skills/demo", error="Expected a full 40-character")
        self.assertEqual(self.calls(), [])
        self.assertFalse(self.target.with_name("other").exists())

    def test_prune_dry_run_does_not_invoke_remove(self):
        self.action("apply")
        self.declare()
        before = self.lock.read_bytes()
        self.action("prune", "--manager", "skills", "--dry-run")
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual(self.lock.read_bytes(), before)

    def test_shared_content_is_not_force_deleted(self):
        self.action("apply")
        self.declare()
        self.env["SKILLS_TEST_RETAIN"] = "1"
        self.action("prune", "--manager", "skills", error="CLI did not fully remove")
        self.assertTrue(self.target.exists())
