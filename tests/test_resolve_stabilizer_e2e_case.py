#!/usr/bin/env python3

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RESOLVER = ROOT / "scripts" / "resolve_stabilizer_e2e_case.py"


class ResolveStabilizerE2ECaseTests(unittest.TestCase):
    def run_resolver(self, case, environment=None):
        with tempfile.TemporaryDirectory() as directory:
            temp_root = Path(directory)
            input_path = temp_root / "input.json"
            output_path = temp_root / "output.json"
            input_path.write_text(json.dumps(case), encoding="utf-8")
            result = subprocess.run(
                [
                    "python3",
                    str(RESOLVER),
                    "--input",
                    str(input_path),
                    "--output",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                env={**os.environ, **(environment or {})},
                check=False,
            )
            resolved = (
                json.loads(output_path.read_text(encoding="utf-8"))
                if output_path.exists()
                else None
            )
            return result, resolved

    def test_resolves_library_and_relative_media(self):
        result, resolved = self.run_resolver(
            {
                "library": "${STABILIZER_E2E_LIBRARY}",
                "originalMediaRelative": "Event/Original Media/clip.mov",
                "proxyMediaRelative": "Event/Transcoded Media/Proxy Media/clip.mov",
            },
            {"STABILIZER_E2E_LIBRARY": "/Volumes/Edit/Test.fcpbundle"},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(resolved["library"], "/Volumes/Edit/Test.fcpbundle")
        self.assertEqual(
            resolved["originalMedia"],
            "/Volumes/Edit/Test.fcpbundle/Event/Original Media/clip.mov",
        )
        self.assertEqual(
            resolved["proxyMedia"],
            "/Volumes/Edit/Test.fcpbundle/Event/Transcoded Media/Proxy Media/clip.mov",
        )

    def test_rejects_missing_environment_variable(self):
        environment = dict(os.environ)
        environment.pop("STABILIZER_E2E_LIBRARY", None)
        with tempfile.TemporaryDirectory() as directory:
            input_path = Path(directory) / "input.json"
            output_path = Path(directory) / "output.json"
            input_path.write_text(
                json.dumps({"library": "${STABILIZER_E2E_LIBRARY}"}),
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    "python3",
                    str(RESOLVER),
                    "--input",
                    str(input_path),
                    "--output",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

        self.assertEqual(result.returncode, 2)
        self.assertIn("requires non-empty environment variable", result.stderr)

    def test_rejects_media_path_escape(self):
        result, _ = self.run_resolver(
            {
                "library": "/Volumes/Edit/Test.fcpbundle",
                "originalMediaRelative": "../outside.mov",
            }
        )

        self.assertEqual(result.returncode, 2)
        self.assertIn("must stay inside", result.stderr)

    def test_all_checked_in_cases_resolve_without_machine_specific_paths(self):
        cases_root = ROOT / "tests" / "stabilizer_e2e_cases"
        for case_path in sorted(cases_root.glob("*.json")):
            with self.subTest(case=case_path.name):
                case = json.loads(case_path.read_text(encoding="utf-8"))
                self.assertEqual(case["library"], "${STABILIZER_E2E_LIBRARY}")
                self.assertNotIn("/Users/", case_path.read_text(encoding="utf-8"))
                result, resolved = self.run_resolver(
                    case,
                    {
                        "STABILIZER_E2E_LIBRARY": (
                            "/Volumes/Edit/stabilizer_super_smoother.fcpbundle"
                        )
                    },
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(resolved["originalMedia"].startswith(resolved["library"]))
                self.assertTrue(resolved["proxyMedia"].startswith(resolved["library"]))


if __name__ == "__main__":
    unittest.main()
