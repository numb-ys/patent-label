"""Source-only checks suitable for CI; no CAD, SDK or external Python packages."""
import importlib.util
import json
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from generate_english import english_backend, prepare


class PublicSourceChecks(unittest.TestCase):
    def test_english_is_ascii_and_complete(self):
        source = english_backend()
        self.assertTrue(source.isascii())
        self.assertIn("PATENT_LABEL_ARIAL_REGULAR", source)
        self.assertIn("PatentLabel.EnglishWeight", source)
        self.assertNotIn("simhei.ttf", source)

    def test_translations_are_nonempty_ascii(self):
        translations = json.loads((ROOT / "i18n/en.json").read_text(encoding="utf-8"))
        self.assertGreater(len(translations), 40)
        self.assertTrue(all(value and value.isascii() for value in translations.values()))

    def test_generators_preserve_chinese_sources(self):
        paths = [ROOT / "src/PatentLabel.lsp", ROOT / "src/PatentLabel.UI/Interaction.cs",
                 ROOT / "legacy/AutoCAD2014/PatentLabel2014.lsp", ROOT / "legacy/AutoCAD2019/PatentLabel2019.lsp"]
        before = {p: p.read_bytes() for p in paths}
        for year in (2014, 2019, 2026):
            prepare(year)
            generated = ROOT / f"build/english/{year}"
            for name in ("Interaction.cs", "LabelFonts.cs", "LabelAttachment.cs", "LabelGripEditing.cs", "PatentLabel.lsp"):
                content = (generated / name).read_text(encoding="ascii")
                self.assertTrue(content.isascii())
            backend = (generated / "PatentLabel.lsp").read_text(encoding="ascii")
            self.assertIn(f"0.3.2-en-{year}", backend)
            self.assertIn("c:BHVER", backend)
        self.assertEqual(before, {p: p.read_bytes() for p in paths})

    def test_english_has_no_inline_edit_hooks(self):
        for year in (2014, 2019, 2026):
            prepare(year)
            ui = (ROOT / f"build/english/{year}/Interaction.cs").read_text(encoding="ascii")
            for removed in ("BeginDoubleClick", "DocumentLockModeChanged", "ShowModelessDialog", "InlineNumberForm"):
                self.assertNotIn(removed, ui)

    def test_installer_template_preserves_boundaries(self):
        source = (ROOT / "deployment/english/Install.ps1.in").read_text(encoding="ascii")
        self.assertIn("$cadVersion.StartsWith('@@API@@')", source)
        self.assertIn("$record.ProductCode -ne $productCode", source)
        self.assertNotIn("SetVariable('SECURELOAD'", source)
        self.assertNotRegex(source, r"(?i)Remove-Item.*-Recurse")

    def test_license_and_docs(self):
        self.assertIn("MIT License", (ROOT / "LICENSE").read_text(encoding="ascii"))
        guide = (ROOT / "docs/USER_GUIDE_EN.md").read_text(encoding="ascii")
        for word in ("Install.cmd", "Uninstall.cmd", "BHVER", "Space again", "2014", "2019", "2026"):
            self.assertIn(word, guide)
        self.assertNotIn("C:\\Users\\", guide)


if __name__ == "__main__":
    unittest.main()
