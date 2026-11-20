"""Verify the UI assembly's actual CAD geometry/interop without operating the desktop."""
from datetime import datetime
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import xml.etree.ElementTree as ET

from test_plugin import DEFAULT_EXE, DEFAULT_TEMPLATE, ROOT, isolated_settings, restore_isolated_settings, run_core, lisp_string


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--english", action="store_true")
    args = parser.parse_args()
    output = ROOT / "artifacts" / ("ui-core-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    output.mkdir(parents=True)
    dll = ROOT / "src/PatentLabel.UI/bin/Release/net8.0-windows/PatentLabel.UI.dll"
    source = ROOT / "src/PatentLabel.lsp"
    version = ET.parse(ROOT / "deployment/PackageContents.xml").getroot().attrib["AppVersion"]
    if args.english:
        dll = ROOT / "src/PatentLabel.English2026/bin/Release/net8.0-windows/PatentLabel.English2026.dll"
        source = ROOT / "build/english/2026/PatentLabel.lsp"
        version = "0.4.0-en-2026"
    tested_dll = output / f"PatentLabel.UI.{version}.dll"
    shutil.copy2(dll, tested_dll)
    shutil.copy2(source, output / source.name)
    shutil.copy2(DEFAULT_TEMPLATE, output / "input.dwg")
    destination = lisp_string(output / "geometry.jsonl")
    steps = [
        '(setq bht:trusted (getvar "TRUSTEDPATHS"))',
        f'(setvar "TRUSTEDPATHS" (strcat bht:trusted ";" {lisp_string(output)}))',
        f'(command-s "_.NETLOAD" {lisp_string(tested_dll)})',
        f'(load {lisp_string(output / source.name)})',
        '(setvar "TRUSTEDPATHS" bht:trusted)',
        '(setvar "CMDECHO" 0)',
        '(setvar "OSMODE" 0)',
        '(command-s "_.UNDO" "_Control" "_All")',
        '(command-s "_.UNDO" "_End")',
        '(command-s "_.UNDO" "_Auto" "_Off")',
        '(setenv "PatentLabel.SimHeiWeight" "")',
        '(setenv "PatentLabel.Bold" "Bold")',
        '(bh:sync-ui)',
        '(bh:ensure-resources)',
        f'(setq bht:stream (open {destination} "w"))',
        '(write-line (bh:ui-geometry \'(0.0 0.0 0.0) "001" 2.5 3.75 0.8) bht:stream)',
        '(write-line (bh:ui-geometry \'(5 10 0) "12345678" 2.5 3.75 0.8) bht:stream)',
        '(command-s "_.UCS" "_3point" \'(100.0 50.0 7.0) \'(100.0 51.0 7.0) \'(99.0 50.0 7.0))',
        '(write-line (bh:ui-geometry \'(0.0 0.0 0.0) "103" 2.5 3.75 0.8) bht:stream)',
        '(command-s "_.UCS" "_World")',
        '(command-s "_.UCS" "_3point" \'(0.0 0.0 40.0) \'(1.0 0.0 40.0) \'(0.0 0.0 41.0))',
        '(write-line (bh:ui-geometry \'(0.0 0.0 0.0) "104" 2.5 3.75 0.8) bht:stream)',
        '(command-s "_.UCS" "_World")',
        '(setq bht:invalid (vl-catch-all-apply \'bh:ui-geometry (list \'(0.0 0.0 0.0) "A B" 2.5 3.75 0.8)))',
        '(write-line (if (vl-catch-all-error-p bht:invalid) "INVALID_PASS" "INVALID_FAIL") bht:stream)',
        '(setq bht:entity (bh:make-label \'(0.0 0.0 0.0) \'(30.0 20.0 0.0) "001" \'(2.5 3.75 0.8)))',
        '(bh:ui-apply (cdr (assoc 5 (entget bht:entity))) "12345678")',
        '(write-line (if (= (cdr (assoc 1 (entget (bh:attribute bht:entity)))) "12345678") "EDIT_PASS" "EDIT_FAIL") bht:stream)',
        '(command-s "_.U")',
        '(write-line (if (= (cdr (assoc 1 (entget (bh:attribute bht:entity)))) "001") "UNDO_PASS" "UNDO_FAIL") bht:stream)',
        '(setq bht:count-before (if (setq bht:ss (ssget "_X" \'((0 . "INSERT")))) (sslength bht:ss) 0))',
        '(setq bht:picked (bh:ui-preview-hold \'(1415.59 1015.68 0.0) "123" 2.5 3.75 0.8))',
        '(write-line (if (and (= (length bht:picked) 3) (numberp (car bht:picked)) (equal bht:picked \'(1430.59 1025.68 0.0) 0.000001)) "POINT_PASS" "POINT_FAIL") bht:stream)',
        '(write-line (bh:ui-state) bht:stream)',
        '(write-line (if (= bht:count-before (if (setq bht:ss (ssget "_X" \'((0 . "INSERT")))) (sslength bht:ss) 0)) "TRANSIENT_DB_PASS" "TRANSIENT_DB_FAIL") bht:stream)',
        '(bh:ui-preview-clear)',
        '(write-line (bh:ui-state) bht:stream)',
        '(setq bht:entity (bh:make-label \'(1415.59 1015.68 0.0) (bh:point-result bht:picked) "123" \'(2.5 3.75 0.8)))',
        '(write-line (if (= (cdr (assoc 1 (entget (bh:attribute bht:entity)))) "123") "SCREENSHOT_POINT_PASS" "SCREENSHOT_POINT_FAIL") bht:stream)',
        '(bh:ui-apply (cdr (assoc 5 (entget bht:entity))) "A01")',
        '(write-line (if (= (cdr (assoc 1 (entget (bh:attribute bht:entity)))) "A01") "LETTER_EDIT_PASS" "LETTER_EDIT_FAIL") bht:stream)',
        '(write-line (if (and (bh:ui-identifier-p "A") (bh:ui-identifier-p "123") (bh:ui-identifier-p "a01") (not (bh:ui-identifier-p "A 1"))) "UI_LABEL_PASS" "UI_LABEL_FAIL") bht:stream)',
        '(write-line (bh:ui-font-state) bht:stream)',
        '(bh:ui-configure "Space" "Bold")',
        '(write-line (bh:ui-geometry \'(0.0 0.0 0.0) "123" 2.5 3.75 0.8) bht:stream)',
        '(bh:ui-configure "Space" "Regular")',
        '(write-line (if (not (bh:ui-ensure-fonts)) "FONTS_UNCHANGED_PASS" "FONTS_UNCHANGED_FAIL") bht:stream)',
        '(close bht:stream)',
        '_.QUIT',
        '_No',
    ]
    script = output / "verify.scr"
    script_text = "\n".join(steps) + "\n"
    if args.english:
        script_text = script_text.replace("PatentLabel.SimHeiWeight", "PatentLabel.EnglishWeight")
    script.write_text(script_text, encoding="mbcs")
    snapshot = isolated_settings()
    try:
        run_core(DEFAULT_EXE, output / "input.dwg", script, output / "run.log", 90)
        lines = (output / "geometry.jsonl").read_text(encoding="utf-8").splitlines()
        if len(lines) != 17:
            raise RuntimeError(f"UI core checks did not finish: {lines}; inspect {output / 'run.txt'}")
        shapes = [json.loads(line) for line in lines[:4]]
        checks = {}
        def same(left, right):
            return len(left) == len(right) and all(abs(a-b) < 1e-7 for a,b in zip(left,right))
        expected = [([0, 0, 0], [15, 10, 0]), ([5, 10, 0], [20, 20, 0]),
                    ([100, 50, 7], [90, 65, 7]), ([0, 0, 40], [15, 0, 50])]
        for index, (shape, (target, center)) in enumerate(zip(shapes, expected)):
            checks[f"preview-{index}-target-exact"] = same(shape["points"][0], target)
            checks[f"preview-{index}-number-center-exact"] = same(shape["center"], center)
            checks[f"preview-{index}-valid"] = shape["valid"] is True
        checks["preview-long-number-has-larger-width"] = shapes[1]["width"] > shapes[0]["width"]
        for index in (0,1):
            p = shapes[index]["points"]
            checks[f"preview-{index}-horizontal-landing"] = abs(p[1][1] - p[2][1]) < 1e-7
            checks[f"preview-{index}-text-gap-exact"] = abs(abs(p[2][0] - shapes[index]["center"][0]) - shapes[index]["width"]/2 - .8) < 1e-7
        checks.update({"invalid-number-rejected": lines[4] == "INVALID_PASS",
                       "command-edit-backend-updates-number": lines[5] == "EDIT_PASS",
                       "command-edit-backend-undo-restores-number": lines[6] == "UNDO_PASS"})
        held, cleared = json.loads(lines[8]), json.loads(lines[10])
        checks.update({
            "native-picked-point-is-flat": lines[7] == "POINT_PASS",
            "after-second-click-retains-line-and-text": held["retainedDrawables"] == 2,
            "native-transients-registered": held["registeredTransients"] == 2,
            "preview-does-not-create-dwg-entities": lines[9] == "TRANSIENT_DB_PASS",
            "clear-disposes-held-preview": cleared["retainedDrawables"] == 0 and cleared["registeredTransients"] == 0,
            "screenshot-coordinate-creates-three-digit-label": lines[11] == "SCREENSHOT_POINT_PASS",
            "command-edit-accepts-mixed-label": lines[12] == "LETTER_EDIT_PASS",
            "dotnet-validator-accepts-letters-and-digits": lines[13] == "UI_LABEL_PASS",
        })
        fonts = json.loads(lines[14])
        bold_preview = json.loads(lines[15])
        if args.english:
            # The common geometry/interop checks use edition-specific style identifiers.
            fonts = {key.replace("PATENT_LABEL_ARIAL_", "PATENT_LABEL_SIMHEI_"): value for key, value in fonts.items()}
            for shape in shapes + [bold_preview]:
                shape["textStyle"] = shape["textStyle"].replace("PATENT_LABEL_ARIAL_", "PATENT_LABEL_SIMHEI_")
        checks.update({
            "native-font-bold-flag-is-true": fonts["PATENT_LABEL_SIMHEI_BOLD"]["bold"] is True,
            "native-font-regular-flag-is-false": fonts["PATENT_LABEL_SIMHEI_REGULAR"]["bold"] is False,
            "default-font-face-matches-edition": fonts["PATENT_LABEL_SIMHEI_REGULAR"]["face"].lower() in ({"arial"} if args.english else {"simhei", "黑体"}),
            "default-font-file-matches-edition": fonts["PATENT_LABEL_SIMHEI_REGULAR"]["file"].lower().endswith("arial.ttf" if args.english else "simhei.ttf"),
            "default-preview-uses-regular-font": shapes[0]["textStyle"] == "PATENT_LABEL_SIMHEI_REGULAR",
            "bold-preview-uses-bold-font": bold_preview["textStyle"] == "PATENT_LABEL_SIMHEI_BOLD",
            "old-bold-default-does-not-carry-over": held["defaultBold"] is False,
            "custom-inline-editor-disabled": held["inlineEditingEnabled"] is False,
            "existing-correct-fonts-not-rewritten": lines[16] == "FONTS_UNCHANGED_PASS",
        })
        report = {"passed": sum(checks.values()), "failed": len(checks) - sum(checks.values()),
                  "checks": checks, "desktop_automated": False, "english": args.english,
                  "mouse_preview_and_native_attribute_editor": "user verification required",
                  "dll_sha256": hashlib.sha256(dll.read_bytes()).hexdigest(),
                  "lisp_sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
        (output / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(json.dumps(report, indent=2))
        print(f"Report: {output / 'report.json'}")
        return 1 if report["failed"] else 0
    finally:
        restore_isolated_settings(snapshot)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
