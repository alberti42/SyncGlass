"""Tests for bin/merge_appcast_item.py, bin/inject_appcast_notes.py and bin/md_to_html.py:
python3 -m unittest discover -s Tests/Scripts -p '*_test.py'"""

import pathlib
import subprocess
import sys
import tempfile
import unittest

BIN = pathlib.Path(__file__).resolve().parents[2] / "bin"
EMPTY = """<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>SyncGlass</title>
        <language>en</language>
    </channel>
</rss>
"""

OLD_URL = "https://github.com/alberti42/SyncGlass/releases/download/v1.0.0/SyncGlass.zip"
NEW_URL = "https://github.com/alberti42/SyncGlass/releases/download/v1.1.0/SyncGlass.zip"


def item(build, url):
    return f"""<item>
            <title>{build}</title>
            <sparkle:version>{build}</sparkle:version>
            <enclosure url="{url}" length="1" type="application/octet-stream" sparkle:edSignature="x"/>
        </item>"""


def appcast(*items):
    return EMPTY.replace("    </channel>", "".join(f"        {i}\n" for i in items) + "    </channel>")


def run(script, *args):
    return subprocess.run([sys.executable, str(BIN / script), *map(str, args)],
                          capture_output=True, text=True)


class AppcastTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.tmp = pathlib.Path(self.dir.name)

    def tearDown(self):
        self.dir.cleanup()

    def write(self, name, text):
        path = self.tmp / name
        path.write_text(text)
        return path

    def test_merge_into_empty_appcast(self):
        new = self.write("new.xml", appcast(item(2, NEW_URL)))
        original = self.write("original.xml", EMPTY)
        self.assertEqual(run("merge_appcast_item.py", new, original).returncode, 0)
        self.assertEqual(original.read_text(), appcast(item(2, NEW_URL)))

    def test_merge_keeps_old_urls(self):
        # generate_appcast rewrites the URL of every item with the new prefix.
        new = self.write("new.xml", appcast(item(2, NEW_URL), item(1, NEW_URL)))
        original = self.write("original.xml", appcast(item(1, OLD_URL)))
        self.assertEqual(run("merge_appcast_item.py", new, original).returncode, 0)
        text = original.read_text()
        self.assertLess(text.index("<sparkle:version>2<"), text.index("<sparkle:version>1<"))
        self.assertIn(OLD_URL, text)
        self.assertEqual(text.count(NEW_URL), 1)

    def test_merge_fails_without_new_item(self):
        new = self.write("new.xml", appcast(item(1, NEW_URL)))
        original = self.write("original.xml", appcast(item(1, OLD_URL)))
        self.assertNotEqual(run("merge_appcast_item.py", new, original).returncode, 0)

    def test_notes_go_into_first_item(self):
        notes_md = self.write("notes.md", "## Changes\n\n- **Bold** and `code`, [link](https://example.com)\n")
        notes_html = self.tmp / "notes.html"
        self.assertEqual(run("md_to_html.py", notes_md, notes_html).returncode, 0)
        self.assertEqual(notes_html.read_text(),
                         "<h2>Changes</h2>\n<ul>\n<li><strong>Bold</strong> and <code>code</code>, "
                         '<a href="https://example.com">link</a></li>\n</ul>\n')

        cast = self.write("appcast.xml", appcast(item(2, NEW_URL), item(1, OLD_URL)))
        for _ in range(2):  # a second run replaces the description
            self.assertEqual(run("inject_appcast_notes.py", cast, notes_html).returncode, 0)
        text = cast.read_text()
        self.assertEqual(text.count("<description><![CDATA["), 1)
        self.assertLess(text.index("<![CDATA["), text.index("<sparkle:version>1<"))


if __name__ == "__main__":
    unittest.main()
