"""Exercise package status with the actual mise Lua runtime, in isolated homes."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MISE = shutil.which("mise")
PIN = "a" * 40
SOURCE = "https://github.com/example/skills.git"


@unittest.skipUnless(MISE, "mise is required")
class MiseFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mise-skills-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir()
        self.project = self.root / "project"
        self.project.mkdir()
        self.env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_STATE_HOME": str(self.root / "state"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "MISE_CONFIG_DIR": str(self.root / "config/mise"),
            "MISE_DATA_DIR": str(self.root / "data/mise"),
            "MISE_STATE_DIR": str(self.root / "state/mise"),
            "MISE_CACHE_DIR": str(self.root / "cache/mise"),
            "MISE_TRUSTED_CONFIG_PATHS": str(self.project),
            "MISE_YES": "1",
            "MISE_OFFLINE": "1",
        }
        plugin = Path(self.env["MISE_DATA_DIR"]) / "plugins/skills"
        plugin.parent.mkdir(parents=True)
        shutil.copytree(ROOT, plugin, ignore=shutil.ignore_patterns(".git", ".opencode", "tests"))
        self.target = self.home / ".agents/skills/demo"
        self.lock = self.root / "state/skills/.skill-lock.json"
        self.declare("demo")

    def declare(self, *skills):
        declarations = "".join(
            f'"skills:example/skills/{skill}" = "{PIN}"\n' for skill in skills
        )
        (self.project / "mise.toml").write_text("[bootstrap.packages]\n" + declarations)

    def record(self, **changes):
        entry = {"sourceUrl": SOURCE, "ref": PIN, **changes}
        self.lock.parent.mkdir(parents=True, exist_ok=True)
        self.lock.write_text(json.dumps({"version": 3, "skills": {"demo": entry}}))

    def install_files(self):
        self.target.mkdir(parents=True)
        (self.target / "SKILL.md").write_text("fixture\n")

    def status(self, error=None):
        result = subprocess.run(
            [MISE, "bootstrap", "packages", "status", "--json"],
            cwd=self.project, env=self.env, capture_output=True, text=True, timeout=30,
        )
        if error:
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(error, result.stderr)
            return
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)


class PackageStatusTests(MiseFixture):
    def test_missing_without_lock(self):
        self.assertEqual(self.status()["skills"]["packages"][0]["state"], "missing")

    def test_installed(self):
        self.record()
        self.install_files()
        before = self.lock.read_bytes()
        package = self.status()["skills"]["packages"][0]
        self.assertEqual(package["state"], "installed")
        self.assertEqual(package["installed_version"], PIN)
        self.assertEqual(self.lock.read_bytes(), before)

    def test_missing_lock_entry(self):
        self.record()
        self.declare("other")
        self.assertEqual(self.status()["skills"]["packages"][0]["state"], "missing")

    def test_missing_files(self):
        self.record()
        self.assertEqual(self.status()["skills"]["packages"][0]["state"], "missing")

    def test_missing_entrypoint(self):
        self.record()
        self.target.mkdir(parents=True)
        self.assertEqual(self.status()["skills"]["packages"][0]["state"], "missing")

    def test_mismatched_pin(self):
        self.record(ref="b" * 40)
        self.install_files()
        self.assertEqual(self.status()["skills"]["packages"][0]["installed_version"], "b" * 40)

    def test_mixed_batch(self):
        self.record()
        self.install_files()
        self.declare("absent", "demo", "other")
        packages = self.status()["skills"]["packages"]
        self.assertEqual(
            {pkg["package"].split("/")[-1]: pkg["state"] for pkg in packages},
            {"absent": "missing", "demo": "installed", "other": "missing"},
        )

    def test_foreign_source_rejected(self):
        self.record(sourceUrl="https://github.com/foreign/skills.git")
        self.install_files()
        self.status(error="Different source in global lock")

    def test_untracked_files_rejected_without_lock(self):
        self.install_files()
        self.status(error="Untracked global content")

    def test_untracked_files_rejected_without_entry(self):
        self.record()
        self.install_files()
        self.target.rename(self.target.with_name("other"))
        self.declare("other")
        self.status(error="Untracked global content")

    def test_symlinked_target_rejected(self):
        self.record()
        self.target.parent.mkdir(parents=True)
        self.target.symlink_to(self.project, target_is_directory=True)
        self.status(error="Target is a symlink")

    def test_symlinked_content_rejected(self):
        self.record()
        self.install_files()
        (self.target / "linked").symlink_to(self.project)
        self.status(error="Target contains a symlink")

    def test_invalid_lock_rejected(self):
        self.record()
        self.lock.write_text("not json")
        self.status(error="Global lock is not valid JSON")


if __name__ == "__main__":
    unittest.main()
