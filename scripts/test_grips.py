"""Call AutoCAD's real grip protocol on DB objects and disposable drag clones; no desktop automation."""
from datetime import datetime
import argparse
import json
import re
import shutil
import sys
from test_plugin import ROOT, DEFAULT_EXE, DEFAULT_TEMPLATE, run_core, isolated_settings, restore_isolated_settings, lisp_string


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--english', action='store_true')
    args = parser.parse_args()
    output = ROOT / 'artifacts' / ('grips-' + datetime.now().strftime('%Y%m%d-%H%M%S'))
    output.mkdir(parents=True)
    source = ROOT / ('build/english/2026/PatentLabel.lsp' if args.english else 'src/PatentLabel.lsp')
    dll = ROOT / ('src/PatentLabel.English2026/bin/Release/net8.0-windows/PatentLabel.English2026.dll' if args.english
                  else 'src/PatentLabel.UI/bin/Release/net8.0-windows/PatentLabel.UI.dll')
    helper = ROOT / 'tests/AttachmentCommands/bin/Release/net8.0-windows/AttachmentCommands.dll'
    for p in (source, dll, helper): shutil.copy2(p, output / p.name)
    shutil.copy2(DEFAULT_TEMPLATE, output / 'input.dwg')
    definitions = ROOT / 'tests/integration.lsp'
    if args.english:
        definitions = output / 'integration-en.lsp'
        definitions.write_text((ROOT / 'tests/integration.lsp').read_text(encoding='utf-8')
            .replace('PATENT_LABEL_SIMHEI_', 'PATENT_LABEL_ARIAL_')
            .replace('PatentLabel.SimHeiWeight', 'PatentLabel.EnglishWeight').replace('simhei', 'arial'), encoding='ascii')
    common = [
        '(setq plt:trusted (getvar "TRUSTEDPATHS"))',
        f'(setvar "TRUSTEDPATHS" (strcat plt:trusted ";" {lisp_string(output)} ";" {lisp_string(ROOT / "tests")}))',
        f'(command-s "_.NETLOAD" {lisp_string(output / dll.name)})',
        f'(command-s "_.NETLOAD" {lisp_string(output / helper.name)})',
        f'(load {lisp_string(output / source.name)})', f'(load {lisp_string(definitions)})',
        '(setvar "TRUSTEDPATHS" plt:trusted)', f'(setq bht:output {lisp_string(output)})',
    ]
    steps = common + [
        '(bht:init)', '(bh:ensure-resources)',
        '(setq plt:a (bh:make-label \'(0 0 0) \'(30 20 0) "A1" \'(2.5 3.75 0.8)))',
        '(setq plt:handle (cdr (assoc 5 (entget plt:a))))',
        '(command-s "_.COPY" plt:a "" "_non" \'(0 0 0) "_non" \'(0 40 0))',
        '(setq plt:copy (entlast) plt:def (cdr (assoc 2 (entget plt:a))) plt:copy-def (cdr (assoc 2 (entget (entlast)))))',
        '(setq plt:stream (open (strcat bht:output "/geometry.jsonl") "w"))',
        '(write-line (pltest:grip-info plt:handle) plt:stream)',
        '(write-line (pltest:grip-preview plt:handle 10.0 5.0) plt:stream)',
        '(write-line (bh:ui-grip-geometry) plt:stream)', '(write-line (bh:ui-state) plt:stream)',
        '(bht:assert (bht:point= (bh:attribute-center (bh:attribute plt:a)) \'(30 20 0)) "drag-preview-does-not-move-real-attribute")',
        '(bht:assert (equal (cdr (assoc 2 (entget plt:a))) plt:def) "drag-preview-does-not-write-block-definition")',
        '(bht:assert (bht:point= (bht:world plt:a (car (bht:vertices plt:a))) \'(0 0 0)) "drag-preview-keeps-real-target")',
        '(write-line (pltest:grip-sample -50.0 -10.0) plt:stream)',
        '(write-line (bh:ui-grip-geometry) plt:stream)', '(write-line (bh:ui-state) plt:stream)',
        '(pltest:grip-clear)', '(write-line (bh:ui-state) plt:stream)',
        '(bht:assert (equal (cdr (assoc 2 (entget plt:a))) plt:def) "cancel-preview-keeps-original-definition")',
        '(pltest:configure plt:handle 10.0 5.0 "unused")', 'PLTEST_GRIP_COMMIT',
        '(bht:assert (bht:point= (bh:attribute-center (bh:attribute plt:a)) \'(40 25 0)) "native-grip-commits-label-position")',
        '(bht:assert (bht:point= (bht:world plt:a (car (bht:vertices plt:a))) \'(0 0 0)) "native-grip-commit-keeps-target")',
        '(bht:assert (equal (cadr (bht:world plt:a (caddr (bht:vertices plt:a)))) 25.0 0.000001) "native-grip-commit-reconnects-line")',
        '(bht:assert (and (equal (cdr (assoc 2 (entget plt:copy))) plt:copy-def) (bht:point= (bh:attribute-center (bh:attribute plt:copy)) \'(30 60 0))) "native-grip-copy-remains-independent")',
        'U',
        '(bht:assert (and (bht:point= (bh:attribute-center (bh:attribute plt:a)) \'(30 20 0)) (equal (cdr (assoc 2 (entget plt:a))) plt:def)) "native-grip-single-undo-restores-text-and-line")',
        '_.REDO',
        '(bht:assert (and (bht:point= (bh:attribute-center (bh:attribute plt:a)) \'(40 25 0)) (equal (cadr (bht:world plt:a (caddr (bht:vertices plt:a)))) 25.0 0.000001)) "native-grip-redo-restores-text-and-line")',
        '(pltest:configure plt:handle -50.0 -10.0 "unused")', 'PLTEST_GRIP_COMMIT',
        '(bht:assert (and (bht:point= (bh:attribute-center (bh:attribute plt:a)) \'(-10 15 0)) (equal (cadr (bht:world plt:a (caddr (bht:vertices plt:a)))) 15.0 0.000001)) "repeated-grip-uses-current-label-position")',
        '(setq plt:beforeabort (bht:vertices plt:a))',
        '(pltest:configure plt:handle 100.0 0.0 "unused")', 'PLTEST_GRIP_ABORT',
        '(bht:assert (and (bht:point= (bh:attribute-center (bh:attribute plt:a)) \'(-10 15 0)) (equal (bht:vertices plt:a) plt:beforeabort 0.000001)) "native-aborted-grip-restores-geometry")',
        '(command-s "_.UCS" "_3point" \'(100 50 7) \'(100 51 7) \'(99 50 7))',
        '(setq plt:r (bh:make-label \'(0 0 0) \'(25 15 0) "R1" \'(2.5 3.75 0.8)))',
        '(command-s "_.UCS" "_World")',
        '(pltest:configure (cdr (assoc 5 (entget plt:r))) 8.0 -4.0 "unused")', 'PLTEST_GRIP_COMMIT',
        '(bht:assert (bht:point= (bh:attribute-center (bh:attribute plt:r)) \'(93 71 7)) "native-grip-rotated-UCS-position")',
        '(bht:assert (bht:point= (bht:world plt:r (car (bht:vertices plt:r))) \'(100 50 7)) "native-grip-rotated-UCS-target")',
        # Keep the plot-only resident clone in a separate fixture after all protocol/undo checks.
        '(setq plt:render (bh:make-label \'(0 0 0) \'(30 20 0) "A1" \'(2.5 3.75 0.8)))',
        f'(pltest:grip-render (cdr (assoc 5 (entget plt:render))) {lisp_string(output / "native-grip-preview.pdf")})',
        '(write-line (bh:ui-state) plt:stream)', '(close plt:stream)',
        '(bht:write (strcat "SUMMARY " (itoa bht:passed) " " (itoa bht:failed)))',
        '_.QUIT', '_No',
    ]
    script = output / 'verify.scr'
    script.write_text('\n'.join(steps) + '\n', encoding='mbcs')
    snapshot = isolated_settings()
    try:
        run_core(DEFAULT_EXE, output/'input.dwg', script, output/'run.log', 90)
        results = (output/'results.txt').read_text(encoding='utf-8')
        print(results)
        data = [json.loads(line) for line in (output/'geometry.jsonl').read_text().splitlines()]
        checks = {
            'one-native-label-grip': data[0]['count'] == 1 and data[0]['grips'][0]['type'] == 'LabelGrip',
            'grip-at-number-center': data[0]['grips'][0]['point'] == [30,20,0],
            'detached-clone-preview': data[1]['clone'] is True,
            'preview-first-label-position': data[2].get('center') == [40,25,0],
            'preview-first-fixed-target': data[2].get('points',[[None]])[0] == [0,0,0],
            'preview-extents-follow-text': data[1]['max'][0] >= 40 and data[1]['max'][1] >= 25,
            'preview-second-label-position': data[5].get('center') == [-20,10,0],
            'preview-second-fixed-target': data[5].get('points',[[None]])[0] == [0,0,0],
            'one-preview-per-active-drag': data[6]['activeGripPreviews'] == 1,
            'cancel-clears-preview': data[7]['activeGripPreviews'] == 0,
            'no-native-grip-errors': data[-1]['gripError'] == '',
            'preview-and-final-callbacks-hit': data[-1]['gripSamples'] >= 2 and data[-1]['gripCommits'] >= 3,
            'native-drawing-callback-hit': data[-1]['gripDraws'] > 0 and (output/'native-grip-preview.pdf').is_file(),
        }
        summary = re.search(r'^SUMMARY (\d+) (\d+)$', results, re.M)
        if not summary: raise RuntimeError('Grip suite did not finish')
        report = {'passed':int(summary[1])+sum(checks.values()), 'failed':int(summary[2])+sum(not v for v in checks.values()),
                  'english':args.english, 'checks':checks, 'desktop_automated':False, 'state':data[-1]}
        (output/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print(json.dumps(report,indent=2)); print(f'Report: {output}')
        return 1 if report['failed'] else 0
    finally: restore_isolated_settings(snapshot)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    raise SystemExit(main())
