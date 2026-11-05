import tempfile
import unittest
from pathlib import Path

import emb_deps

GITMODULES = """\
[submodule "toolchain/emb-toolchain"]
\tpath = toolchain/emb-toolchain
\turl = https://github.com/t0biasm/emb-toolchain.git
[submodule "platform/emb-platform"]
\tpath = platform/emb-platform
\turl = git@github.com:t0biasm/emb-platform
"""

CONFIG = """\
project = "prj-x"
[ci]
target = "//a:b"
[follow."toolchain/emb-toolchain"]
track = "main"
group = "core"
[follow."platform/emb-platform"]
track = "tag:v1.*"
mode = "pr"
"""


def project(config=CONFIG, gitmodules=GITMODULES):
    d = Path(tempfile.mkdtemp())
    (d / emb_deps.CONFIG_NAME).write_text(config)
    (d / ".gitmodules").write_text(gitmodules)
    return d


class EmbDepsTest(unittest.TestCase):
    def test_repo_name(self):
        self.assertEqual(emb_deps.repo_name("https://github.com/t0biasm/emb-toolchain.git"), "emb-toolchain")
        self.assertEqual(emb_deps.repo_name("git@github.com:t0biasm/emb-platform"), "emb-platform")

    def test_match_branch(self):
        d = project()
        m = emb_deps.match(d, "emb-toolchain", "refs/heads/main")
        self.assertEqual([r["path"] for r in m], ["toolchain/emb-toolchain"])
        self.assertEqual(m[0]["mode"], "auto")
        self.assertEqual(emb_deps.match(d, "emb-toolchain", "release/1.x"), [])

    def test_match_tag(self):
        d = project()
        self.assertEqual(len(emb_deps.match(d, "emb-platform", "refs/tags/v1.2.3")), 1)
        self.assertEqual(emb_deps.match(d, "emb-platform", "refs/tags/v2.0.0"), [])
        self.assertEqual(emb_deps.match(d, "emb-platform", "refs/heads/main"), [])

    def test_mode_off_not_matched(self):
        d = project(CONFIG.replace('track = "main"', 'track = "main"\nmode = "off"'))
        self.assertEqual(emb_deps.match(d, "emb-toolchain", "main"), [])

    def test_unlisted_submodule_frozen(self):
        d = project('project = "p"\n[follow."toolchain/emb-toolchain"]\ntrack = "main"\n')
        self.assertEqual(emb_deps.match(d, "emb-platform", "main"), [])

    def test_check_ok(self):
        self.assertEqual(emb_deps.check(project(), "main"), [])

    def test_check_release_must_not_track_main(self):
        problems = emb_deps.check(project(), "release/1.0")
        self.assertTrue(any("must not track main" in p for p in problems))

    def test_check_release_on_maintained_line_ok(self):
        cfg = CONFIG.replace('track = "main"', 'track = "release/1.x"')
        self.assertEqual(emb_deps.check(project(cfg), "release/1.0"), [])

    def test_check_errors(self):
        self.assertTrue(emb_deps.check(project('[follow."nope"]\ntrack = "main"\n')))
        self.assertTrue(emb_deps.check(project('[follow."platform/emb-platform"]\nmode = "auto"\n')))
        self.assertTrue(emb_deps.check(project('[follow."platform/emb-platform"]\ntrack = "main"\nmode = "x"\n')))
        self.assertTrue(emb_deps.check(project('[follow."platform/emb-platform"]\ntrack = "main"\nfoo = 1\n')))

    def test_group_needs_same_mode(self):
        grouped = CONFIG.replace('mode = "pr"', 'mode = "pr"\ngroup = "core"')
        self.assertTrue(any("group" in p for p in emb_deps.check(project(grouped), "main")))
        same = grouped.replace('mode = "pr"', 'mode = "auto"')
        self.assertEqual(emb_deps.check(project(same), "main"), [])

    def test_missing_file(self):
        self.assertTrue(emb_deps.check(tempfile.mkdtemp()))

    def test_ci_defaults(self):
        s = emb_deps.ci_settings({"project": "prj-x", "ci": {"target": "//a:b"}})
        self.assertEqual(s["config"], "")
        self.assertEqual(s["artifact-patterns"], "*.hex *.elf *.bin *.out")
        self.assertEqual(s["submodules"], "recursive")
        self.assertIs(s["upload"], True)
        self.assertEqual(s["project"], "prj-x")

    def test_ci_values_override_defaults(self):
        s = emb_deps.ci_settings({"project": "prj-x", "ci": {
            "target": "//applications/sumobot:app", "config": "atmega32u4",
            "artifact-patterns": "*.hex app", "submodules": "true", "upload": False}})
        self.assertEqual((s["config"], s["submodules"], s["upload"]), ("atmega32u4", "true", False))

    def test_ci_errors(self):
        bad = [
            {"project": "p"},                                              # no [ci]
            {"project": "p", "ci": {}},                                    # no target
            {"project": "p", "ci": {"target": "app"}},                     # not a label
            {"project": "p", "ci": {"target": "//a:b", "extra": "x"}},     # unknown key
            {"project": "p", "ci": {"target": "//a:b", "submodules": "yes"}},
            {"project": "p", "ci": {"target": "//a:b", "upload": "true"}},
            {"project": "p", "ci": {"target": "//a:b", "config": 3}},
            {"ci": {"target": "//a:b"}},                                   # no project
        ]
        for config in bad:
            with self.assertRaises(emb_deps.ConfigError, msg=str(config)):
                emb_deps.ci_settings(config)

    def test_check_validates_ci_when_present(self):
        self.assertEqual(emb_deps.check(project('project = "p"\n[ci]\ntarget = "//a:b"\nnope = 1\n')), ["[ci]: unknown keys ['nope']"])
        self.assertEqual(emb_deps.check(project('project = "p"\n')), [])   # [ci] optional until the project migrates


if __name__ == "__main__":
    unittest.main()
