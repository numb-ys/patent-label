"""Generate ASCII English AutoLISP and per-version managed sources from shared behavior."""
import argparse
import importlib.util
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.3.1"
YEARS = (2014, 2019, 2026)


def english_backend():
    source = (ROOT / "src/PatentLabel.lsp").read_text(encoding="utf-8")
    translations = json.loads((ROOT / "i18n/en.json").read_text(encoding="utf-8"))
    def translate(match):
        literal = json.loads(match.group())
        if any(ord(c) > 127 for c in literal):
            if literal not in translations:
                raise ValueError(f"Missing English translation: {literal!r}")
            return json.dumps(translations[literal], ensure_ascii=True)
        return match.group()
    source = re.sub(r'"(?:\\.|[^"\\])*"', translate, source)
    source = source.replace("0.3.1", VERSION)
    source = source.replace(";;; UTF-8. AutoCAD 2021+ with LISPSYS=1/2; verified host recorded in README.",
                            ";;; ASCII English source, compatible with legacy and Unicode AutoLISP engines.")
    source = source.replace("PATENT_LABEL_SIMHEI_", "PATENT_LABEL_ARIAL_").replace("PatentLabel.SimHeiWeight", "PatentLabel.EnglishWeight")
    source = source.replace('(bh:ensure-font-style "PATENT_LABEL_ARIAL_BOLD" "simhei.ttf")',
                            '(bh:ensure-font-style "PATENT_LABEL_ARIAL_BOLD" "arialbd.ttf")')
    source = source.replace('"simhei.ttf"', '"arial.ttf"')
    # ASCII-only files do not depend on a Chinese Windows code page.
    source.encode("ascii")
    return source


def prepare(year):
    if year not in YEARS:
        raise ValueError(year)
    source = english_backend()
    (ROOT / "src/PatentLabel.en.lsp").write_bytes(source.replace("\n", "\r\n").encode("ascii"))
    identity = f"{VERSION}-en-{year}"
    namespace = f"PatentLabel.English{year}"
    if year == 2026:
        ui = (ROOT / "src/PatentLabel.UI/Interaction.cs").read_text(encoding="utf-8")
        original_namespace = "PatentLabel.UI"
        original_version = "0.3.1"
    else:
        spec = importlib.util.spec_from_file_location("legacy_generator", ROOT / "scripts/legacy/prepare-sources.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        # Redirect all generator writes to ignored build output, preserving the Chinese sources.
        shared = ROOT / "build/english-shared"
        (shared / "src/PatentLabel.UI").mkdir(parents=True, exist_ok=True)
        import shutil
        shutil.copy2(ROOT / "src/PatentLabel.lsp", shared / "src/PatentLabel.lsp")
        for name in ("Interaction.cs", "LabelFonts.cs", "LabelAttachment.cs"):
            shutil.copy2(ROOT / "src/PatentLabel.UI" / name, shared / "src/PatentLabel.UI" / name)
        module.ROOT = shared
        module.prepare(year)
        ui = (shared / f"src/PatentLabel.UI{year}/Interaction.cs").read_text(encoding="utf-8")
        original_namespace = f"PatentLabel.UI{year}"
        original_version = f"0.3.1-{year}"
    ui = ui.replace(original_namespace, namespace).replace(original_version, identity)
    ui = ui.replace("移动鼠标预览整条折线，点击数字中心位置 <取消本条>",
                    "Move to preview the leader; pick the label center <Cancel this callout>")
    ui = ui.replace(f'"PatentLabel{year}.lsp"' if year != 2026 else '"PatentLabel.lsp"', '"PatentLabel.lsp"')
    if year == 2026:
        ui = "using System;\nusing System.Collections.Generic;\nusing System.Linq;\n" + ui
    fonts = (ROOT / "src/english/LabelFonts.cs").read_text(encoding="utf-8").replace("namespace PatentLabel.English;", f"namespace {namespace};")
    attachment = (ROOT / "src/PatentLabel.UI/LabelAttachment.cs").read_text(encoding="utf-8").replace("namespace PatentLabel.UI;", f"namespace {namespace};")
    generated = ROOT / f"build/english/{year}"
    generated.mkdir(parents=True, exist_ok=True)
    for name, value in (("Interaction.cs", ui), ("LabelFonts.cs", fonts), ("LabelAttachment.cs", attachment)):
        value.encode("ascii")
        (generated / name).write_text(value, encoding="ascii")
    source = source.replace(VERSION, identity)
    diagnostic = f'''(defun c:BHVER ()
  (prompt (strcat "\\nPatentLabel {identity} | AutoCAD " (getvar "ACADVER")))
  (prompt (if (bh:ui-available-p) "\\nEnglish preview module: loaded." "\\nEnglish preview module: not loaded (basic mode)."))
  (prompt (strcat "\\nArial file: " (if (findfile "arial.ttf") (findfile "arial.ttf") "not found")))
  (princ))

'''
    source = source.replace('(bh:sync-ui)\n(prompt "\\nPatentLabel', diagnostic + '(bh:sync-ui)\n(prompt "\\nPatentLabel')
    (generated / "PatentLabel.lsp").write_bytes(source.replace("\n", "\r\n").encode("ascii"))
    print(f"Generated English sources for AutoCAD {year}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--year", type=int, choices=YEARS)
    arguments = parser.parse_args()
    for year in (YEARS if arguments.year is None else (arguments.year,)):
        prepare(year)
