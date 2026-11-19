"""Exercise actual DB notifications and native command/undo boundaries in disposable CAD drawings."""
from pathlib import Path
from datetime import datetime
import argparse
import json
import re
import shutil
import sys
from test_plugin import ROOT, DEFAULT_EXE, DEFAULT_TEMPLATE, run_core, isolated_settings, restore_isolated_settings, lisp_string


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--english", action="store_true")
    args = parser.parse_args()
    output = ROOT / "artifacts" / ("attachment-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    output.mkdir(parents=True)
    source = ROOT / "src/PatentLabel.lsp"
    dll = ROOT / "src/PatentLabel.UI/bin/Release/net8.0-windows/PatentLabel.UI.dll"
    helpers = ROOT / "tests/AttachmentCommands/bin/Release/net8.0-windows/AttachmentCommands.dll"
    if args.english:
        source = ROOT / "build/english/2026/PatentLabel.lsp"
        dll = ROOT / "src/PatentLabel.English2026/bin/Release/net8.0-windows/PatentLabel.English2026.dll"
    definitions = ROOT / "tests/integration.lsp"
    if args.english:
        definitions = output / "integration-en.lsp"
        definitions.write_text((ROOT / "tests/integration.lsp").read_text(encoding="utf-8")
                               .replace("PATENT_LABEL_SIMHEI_", "PATENT_LABEL_ARIAL_")
                               .replace("PatentLabel.SimHeiWeight", "PatentLabel.EnglishWeight")
                               .replace("simhei", "arial"), encoding="ascii")
    for path in (source, dll, helpers):
        shutil.copy2(path, output / path.name)
    shutil.copy2(DEFAULT_TEMPLATE, output / "input.dwg")
    steps = [
        '(setq plt:trusted (getvar "TRUSTEDPATHS"))',
        f'(setvar "TRUSTEDPATHS" (strcat plt:trusted ";" {lisp_string(output)} ";" {lisp_string(ROOT / "tests")}))',
        f'(command-s "_.NETLOAD" {lisp_string(output / dll.name)})',
        f'(command-s "_.NETLOAD" {lisp_string(output / helpers.name)})',
        f'(load {lisp_string(output / source.name)})',
        f'(load {lisp_string(definitions)})',
        '(setvar "TRUSTEDPATHS" plt:trusted)',
        f'(setq bht:output {lisp_string(output)})',
        '(bht:init)',
        '(bh:ensure-resources)',
        '(setq plt:a (bh:make-label \'(0 0 0) \'(30 20 0) "1" \'(2.5 3.75 0.8)))',
        '(setq plt:oldline (bht:vertices plt:a))',
        '(pltest:configure (cdr (assoc 5 (entget plt:a))) 10.0 5.0 "123456")',
        'PLTEST_ATTR_MOVE',
        '(bht:assert (bht:point= (trans (cdr (assoc 11 (entget (bh:attribute plt:a)))) (bh:attribute plt:a) 0) \'(40 25 0)) "native-attribute-moved")',
        '(bht:assert (bht:point= (bht:world plt:a (car (bht:vertices plt:a))) \'(0 0 0)) "follow-preserves-world-target")',
        '(bht:assert (equal (cadr (bht:world plt:a (caddr (bht:vertices plt:a)))) 25.0 0.000001) "native-command-event-connects-leader-to-moved-label")',
        'U',
        '(bht:assert (bht:point= (trans (cdr (assoc 11 (entget (bh:attribute plt:a)))) (bh:attribute plt:a) 0) \'(30 20 0)) "one-undo-restores-attribute-position")',
        '(bht:assert (equal (bht:vertices plt:a) plt:oldline 0.000001) "one-undo-restores-leader-together")',
        '_.REDO',
        '(bht:assert (equal (cadr (bht:world plt:a (caddr (bht:vertices plt:a)))) 25.0 0.000001) "redo-restores-attached-leader")',
        '(setq plt:beforetext (bht:vertices plt:a))',
        'PLTEST_ATTR_TEXT',
        '(bht:assert (not (equal (bht:vertices plt:a) plt:beforetext 0.000001)) "native-text-edit-recalculates-gap")',
        '(bht:assert (bht:point= (trans (cdr (assoc 11 (entget (bh:attribute plt:a)))) (bh:attribute plt:a) 0) \'(40 25 0)) "text-edit-keeps-moved-label-position")',
        '(setq plt:beforeabort (bht:vertices plt:a))',
        'PLTEST_ABORT_MOVE',
        '(bht:assert (equal (bht:vertices plt:a) plt:beforeabort 0.000001) "aborted-native-transaction-keeps-geometry")',
        '(command-s "_.COPY" plt:a "" "_non" \'(0 0 0) "_non" \'(0 40 0))',
        '(setq plt:copy (entlast) plt:original-definition (cdr (assoc 2 (entget plt:a))))',
        '(bht:assert (equal (cdr (assoc 2 (entget plt:copy))) plt:original-definition) "copy-initially-shares-definition")',
        '(pltest:configure (cdr (assoc 5 (entget plt:copy))) -20.0 10.0 "XYZ")',
        'PLTEST_ATTR_MOVE',
        '(bht:assert (not (equal (cdr (assoc 2 (entget plt:copy))) plt:original-definition)) "follow-detaches-copied-definition")',
        '(bht:assert (equal (cdr (assoc 2 (entget plt:a))) plt:original-definition) "follow-does-not-change-original-definition")',
        '(bht:assert (bht:point= (bh:attribute-center (bh:attribute plt:a)) \'(40 25 0)) "original-label-position-survives-copy-move")',
        '(bht:assert (bht:point= (bh:attribute-center (bh:attribute plt:copy)) \'(20 75 0)) "copied-label-moves-independently")',
        '(bht:assert (bht:point= (bht:world plt:copy (car (bht:vertices plt:copy))) \'(0 40 0)) "copy-follow-keeps-copied-target")',
        '(bh:replace-number plt:copy "XYZ")',
        '(bht:assert (equal (cadr (bht:world plt:copy (caddr (bht:vertices plt:copy)))) 75.0 0.000001) "LISP-renumber-keeps-moved-leader-end")',
        '(bh:set-weight plt:copy "Bold")',
        '(bht:assert (equal (cadr (bht:world plt:copy (caddr (bht:vertices plt:copy)))) 75.0 0.000001) "restyle-keeps-moved-leader-end")',
        '(bh:begin-undo)',
        '(bh:move-label plt:copy \'(60 90 0))',
        '(bh:end-undo)',
        '(bht:assert (and (bht:point= (bh:attribute-center (bh:attribute plt:copy)) \'(60 90 0)) (equal (cadr (bht:world plt:copy (caddr (bht:vertices plt:copy)))) 90.0 0.000001)) "explicit-move-keeps-text-and-leader-attached")',
        'U',
        '(bht:assert (and (bht:point= (bh:attribute-center (bh:attribute plt:copy)) \'(20 75 0)) (equal (cadr (bht:world plt:copy (caddr (bht:vertices plt:copy)))) 75.0 0.000001)) "explicit-move-undo-restores-both")',
        '(command-s "_.SCALE" plt:a "" "_non" \'(0 0 0) 2.0)',
        '(pltest:configure (cdr (assoc 5 (entget plt:a))) 10.0 5.0 "234")',
        'PLTEST_ATTR_MOVE',
        '(bht:assert (and (bht:point= (bh:attribute-center (bh:attribute plt:a)) \'(90 55 0)) (equal (cadr (bht:world plt:a (caddr (bht:vertices plt:a)))) 55.0 0.000001)) "scaled-callout-follows-native-label-move")',
        '(bht:assert (bht:point= (bht:world plt:a (car (bht:vertices plt:a))) \'(0 0 0)) "scaled-callout-anchor-stays-fixed")',
        '(command-s "_.UCS" "_3point" \'(100 50 7) \'(100 51 7) \'(99 50 7))',
        '(setq plt:rotated (bh:make-label \'(0 0 0) \'(25 15 0) "R1" \'(2.5 3.75 0.8)))',
        '(command-s "_.UCS" "_World")',
        '(pltest:configure (cdr (assoc 5 (entget plt:rotated))) 8.0 -4.0 "R234")',
        'PLTEST_ATTR_MOVE',
        '(bht:assert (bht:point= (bh:attribute-center (bh:attribute plt:rotated)) \'(93 71 7)) "rotated-UCS-attribute-move-position")',
        '(bht:assert (bht:point= (bht:world plt:rotated (car (bht:vertices plt:rotated))) \'(100 50 7)) "rotated-UCS-target-is-fixed")',
        '(bht:assert (equal (cadr (caddr (bht:vertices plt:rotated))) (cadr (bh:block-local plt:rotated (bh:attribute-center (bh:attribute plt:rotated)))) 0.000001) "rotated-UCS-leader-end-follows-label")',
        '(setq plt:p (bh:point-result (bh:ui-move-label (cdr (assoc 5 (entget plt:copy))))))',
        '70,80,0',
        '(bht:assert (bht:point= plt:p \'(70 80 0)) "move-preview-returns-native-picked-center")',
        '(bht:assert (not (null (vl-string-search "\\\"retainedDrawables\\\":2" (bh:ui-state)))) "move-preview-retained-until-commit")',
        '(bh:begin-undo)', '(bh:move-label plt:copy plt:p)', '(bh:end-undo)',
        '(bht:assert (and (bht:point= (bh:attribute-center (bh:attribute plt:copy)) \'(70 80 0)) (equal (cadr (bht:world plt:copy (caddr (bht:vertices plt:copy)))) 80.0 0.000001)) "preview-move-commits-matching-geometry")',
        '(setq plt:unlinked (bh:make-label \'(160 0 0) \'(190 20 0) "N1" \'(2.5 3.75 0.8)))',
        '(entmod (append (entget plt:unlinked) (list (list -3 (list "PATENT_LABEL")))))',
        '(setq plt:unlinked-definition (cdr (assoc 2 (entget plt:unlinked))))',
        '(pltest:configure (cdr (assoc 5 (entget plt:unlinked))) 5.0 10.0 "N2")',
        'PLTEST_ATTR_MOVE',
        '(bht:assert (equal (cdr (assoc 2 (entget plt:unlinked))) plt:unlinked-definition) "unmarked-block-not-modified-by-monitor")',
        '(setq plt:stream (open (strcat bht:output "/state.json") "w"))',
        '(write-line (bh:ui-state) plt:stream)',
        '(close plt:stream)',
        '(bht:write (strcat "SUMMARY " (itoa bht:passed) " " (itoa bht:failed)))',
        '(setq plt:stream (open (strcat bht:output "/saved-handle.txt") "w"))',
        '(write-line (cdr (assoc 5 (entget plt:copy))) plt:stream)', '(close plt:stream)',
        '(setvar "FILEDIA" 0)', '_.QSAVE',
        '_.QUIT', '_No',
    ]
    script = output / "verify.scr"
    script.write_text("\n".join(steps) + "\n", encoding="mbcs")
    snapshot = isolated_settings()
    try:
        run_core(DEFAULT_EXE, output / "input.dwg", script, output / "run.log", 90)
        saved_handle = (output / "saved-handle.txt").read_text().strip()
        reopen = steps[:8] + [
            f'(setq bht:output {lisp_string(output)})', '(setq bht:passed 0 bht:failed 0)',
            f'(setq plt:copy (handent "{saved_handle}"))',
            '(bht:assert (and (bht:point= (bh:attribute-center (bh:attribute plt:copy)) \'(70 80 0)) (equal (cadr (bht:world plt:copy (caddr (bht:vertices plt:copy)))) 80.0 0.000001)) "save-reopen-preserves-attached-geometry")',
            '(pltest:configure (cdr (assoc 5 (entget plt:copy))) 5.0 -10.0 "XYZ")',
            'PLTEST_ATTR_MOVE',
            '(bht:assert (and (bht:point= (bh:attribute-center (bh:attribute plt:copy)) \'(75 70 0)) (equal (cadr (bht:world plt:copy (caddr (bht:vertices plt:copy)))) 70.0 0.000001)) "save-reopen-reattaches-command-monitor")',
            '(bht:assert (bht:point= (bht:world plt:copy (car (bht:vertices plt:copy))) \'(0 40 0)) "reopened-callout-keeps-original-target")',
            '(bht:write (strcat "REOPEN_SUMMARY " (itoa bht:passed) " " (itoa bht:failed)))',
            '_.QUIT', '_No',
        ]
        reopen_script = output / "reopen.scr"
        reopen_script.write_text("\n".join(reopen) + "\n", encoding="mbcs")
        run_core(DEFAULT_EXE, output / "input.dwg", reopen_script, output / "reopen.log", 90)
        results = (output / "results.txt").read_text(encoding="utf-8")
        print(results)
        print((output / "state.json").read_text(encoding="utf-8"))
        summaries = re.findall(r"^(?:REOPEN_)?SUMMARY (\d+) (\d+)$", results, re.M)
        report = {"passed": sum(int(a) for a, _ in summaries), "failed": sum(int(b) for _, b in summaries),
                  "english": args.english, "desktop_automated": False, "host": str(DEFAULT_EXE)}
        (output / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"Report directory: {output}")
        return 1 if "FAIL " in results or "REOPEN_SUMMARY " not in results else 0
    finally:
        restore_isolated_settings(snapshot)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
