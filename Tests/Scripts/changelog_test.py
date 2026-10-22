"""Tests for bin/changelog.py: python3 -m unittest discover -s Tests/Scripts -p '*_test.py'"""

import importlib.util
import pathlib
import unittest

BIN = pathlib.Path(__file__).resolve().parents[2] / "bin" / "changelog.py"
spec = importlib.util.spec_from_file_location("changelog", BIN)
changelog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(changelog)

URL = changelog.REPO_URL

FIRST = f"""# Changelog

## [Unreleased]

### Added

- First feature.

[Unreleased]: {URL}/commits/main
"""

LATER = f"""# Changelog

## [Unreleased]

### Fixed

- A bug.

## [0.1.0] - 2026-10-22

### Added

- First feature.

[Unreleased]: {URL}/compare/v0.1.0...HEAD
[0.1.0]: {URL}/releases/tag/v0.1.0
"""


class SectionBodyTest(unittest.TestCase):
    def test_body_stops_at_next_section(self):
        self.assertEqual(changelog.section_body(LATER, "Unreleased"), "### Fixed\n\n- A bug.")

    def test_body_stops_at_links(self):
        self.assertEqual(changelog.section_body(LATER, "0.1.0"), "### Added\n\n- First feature.")

    def test_missing_section(self):
        self.assertIsNone(changelog.section_body(LATER, "9.9.9"))


class ReleaseTest(unittest.TestCase):
    def test_first_release_links_to_its_tag(self):
        text = changelog.release(FIRST, "0.1.0", "2026-10-22")
        self.assertIn("## [Unreleased]\n\n## [0.1.0] - 2026-10-22\n\n### Added\n\n- First feature.", text)
        self.assertIn(f"[Unreleased]: {URL}/compare/v0.1.0...HEAD\n[0.1.0]: {URL}/releases/tag/v0.1.0", text)

    def test_later_release_compares_with_previous_tag(self):
        text = changelog.release(LATER, "0.1.1", "2026-11-01")
        self.assertEqual(changelog.section_body(text, "0.1.1"), "### Fixed\n\n- A bug.")
        self.assertEqual(changelog.section_body(text, "Unreleased"), "")
        self.assertIn(f"[Unreleased]: {URL}/compare/v0.1.1...HEAD\n[0.1.1]: {URL}/compare/v0.1.0...v0.1.1", text)

    def test_existing_version_is_an_error(self):
        with self.assertRaises(SystemExit):
            changelog.release(LATER, "0.1.0", "2026-11-01")

    def test_empty_unreleased_is_an_error(self):
        empty = changelog.release(LATER, "0.1.1", "2026-11-01")
        with self.assertRaises(SystemExit):
            changelog.release(empty, "0.1.2", "2026-11-02")


if __name__ == "__main__":
    unittest.main()
