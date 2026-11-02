import unittest

import depends_on


class DependsOnTest(unittest.TestCase):
    def test_none(self):
        self.assertEqual(depends_on.parse("Fix the thing.\n", "t0biasm"), [])
        self.assertEqual(depends_on.parse(None, "t0biasm"), [])

    def test_single_and_multiple(self):
        body = ("Some text\n"
                "Depends-on: https://github.com/t0biasm/emb-toolchain/pull/12\n"
                "depends-on: https://github.com/t0biasm/emb-platform/pull/3/\n")
        self.assertEqual(depends_on.parse(body, "t0biasm"), [
            {"repo": "emb-toolchain", "number": 12},
            {"repo": "emb-platform", "number": 3},
        ])

    def test_duplicates_removed(self):
        body = ("Depends-on: https://github.com/t0biasm/emb-toolchain/pull/12\n"
                "Depends-on: https://github.com/t0biasm/emb-toolchain/pull/12\n")
        self.assertEqual(len(depends_on.parse(body, "t0biasm")), 1)

    def test_other_owner_rejected(self):
        with self.assertRaises(depends_on.DependsError):
            depends_on.parse("Depends-on: https://github.com/evil/emb-toolchain/pull/1\n", "t0biasm")

    def test_malformed_rejected(self):
        for bad in ("Depends-on: https://github.com/t0biasm/emb-toolchain/issues/1",
                    "Depends-on: t0biasm/emb-toolchain#1",
                    "Depends-on: https://example.com/t0biasm/emb-toolchain/pull/1"):
            with self.assertRaises(depends_on.DependsError, msg=bad):
                depends_on.parse(bad + "\n", "t0biasm")

    def test_not_at_line_start_ignored(self):
        self.assertEqual(depends_on.parse("see Depends-on: https://github.com/t0biasm/x/pull/1\n", "t0biasm"), [])


if __name__ == "__main__":
    unittest.main()
