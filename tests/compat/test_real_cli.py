"""Opt-in network contract test against the pinned, unmodified skills executable."""

import os
from pathlib import Path
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_status import MISE, MiseFixture  # noqa: E402


CLI = os.environ.get("SKILLS_CLI_TEST_BIN")
# A skill shipped by the CLI's own immutable v1.7.6 source tree.
REVISION = "7a5e920bead4b1039a6d6df5d7e1163b7b09423a"


@unittest.skipUnless(CLI and MISE, "set SKILLS_CLI_TEST_BIN to skills 1.7.6 to enable network tests")
class RealCliContractTests(MiseFixture):
    def setUp(self):
        super().setUp()
        binary = Path(CLI).resolve(strict=True)
        (self.bin / "skills").unlink()
        (self.bin / "skills").symlink_to(binary)
        self.env.pop("MISE_OFFLINE")
        self.target = self.home / ".agents/skills/find-skills"
        (self.project / "mise.toml").write_text(
            '[bootstrap.packages]\n'
            f'"skills:vercel-labs/skills/find-skills" = "{REVISION}"\n'
        )

    def run_action(self, *args):
        result = subprocess.run(
            [MISE, "bootstrap", "packages", *args], cwd=self.project,
            env=self.env, capture_output=True, text=True, timeout=240,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_pinned_install_status_upgrade_and_prune(self):
        self.run_action("apply", "--dry-run")
        self.assertFalse(self.target.exists())
        self.run_action("apply")
        package = self.status()["skills"]["packages"][0]
        self.assertEqual(package["installed_version"], REVISION)
        self.assertTrue((self.target / "SKILL.md").is_file())
        before = self.lock.read_bytes()
        self.run_action("apply")
        self.run_action("upgrade")
        self.assertEqual(self.lock.read_bytes(), before)
        self.declare()
        self.run_action("prune", "--manager", "skills", "--dry-run")
        self.assertTrue(self.target.exists())
        self.run_action("prune", "--manager", "skills")
        self.assertFalse(self.target.exists())
