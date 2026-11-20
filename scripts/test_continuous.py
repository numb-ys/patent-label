"""Exercise native continuous BH input, Esc, numbering and undo without desktop automation."""
from datetime import datetime
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess
import sys
from test_plugin import ROOT, DEFAULT_EXE, DEFAULT_TEMPLATE, ISOLATION_USER, decode_log, run_core, isolated_settings, restore_isolated_settings, lisp_string


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--english', action='store_true')
    parser.add_argument('--basic', action='store_true', help='Use the LISP fallback without a managed preview assembly')
    parser.add_argument('--source', type=Path)
    parser.add_argument('--legacy-engine', action='store_true')
    args = parser.parse_args()
    output = ROOT / 'artifacts' / ('continuous-' + datetime.now().strftime('%Y%m%d-%H%M%S'))
    output.mkdir(parents=True)
    source = args.source or ROOT / ('build/english/2026/PatentLabel.lsp' if args.english else 'src/PatentLabel.lsp')
    dll = ROOT / ('src/PatentLabel.English2026/bin/Release/net8.0-windows/PatentLabel.English2026.dll' if args.english
                  else 'src/PatentLabel.UI/bin/Release/net8.0-windows/PatentLabel.UI.dll')
    shutil.copy2(source, output/'PatentLabel.lsp')
    shutil.copy2(DEFAULT_TEMPLATE, output/'input.dwg')
    if not args.basic: shutil.copy2(dll, output/dll.name)
    definitions = ROOT/'tests/integration.lsp'
    if args.english:
        definitions = output/'integration-en.lsp'
        definitions.write_text((ROOT/'tests/integration.lsp').read_text(encoding='utf-8')
            .replace('PATENT_LABEL_SIMHEI_', 'PATENT_LABEL_ARIAL_')
            .replace('PatentLabel.SimHeiWeight', 'PatentLabel.EnglishWeight').replace('simhei', 'arial'), encoding='ascii')
    steps = [
        '(setq plt:trusted (getvar "TRUSTEDPATHS"))',
        f'(setvar "TRUSTEDPATHS" (strcat plt:trusted ";" {lisp_string(output)} ";" {lisp_string(ROOT/"tests")}))',
    ]
    if not args.basic: steps += [f'(command-s "_.NETLOAD" {lisp_string(output/dll.name)})']
    steps += [f'(load {lisp_string(output/"PatentLabel.lsp")})', f'(load {lisp_string(definitions)})',
        '(setvar "TRUSTEDPATHS" plt:trusted)', f'(setq bht:output {lisp_string(output)})', '(bht:init)',
        '(setq bh:next nil)', 'BH', '0,0,0', '25,15,0',
        '\x1b(bht:assert (and (= (bht:number-count "1") 1) (equal bh:next "2")) "Esc-after-second-click-keeps-default-one")',
        '(bht:assert (= 0 (logand 8 (getvar "UNDOCTL"))) "Esc-closes-current-undo-group")',
        'BH', '40,0,0', '65,15,0', '80,0,0', '105,15,0', '120,0,0', '145,15,0',
        '\x1b(bht:assert (and (= (bht:number-count "2") 1) (= (bht:number-count "3") 1) (= (bht:number-count "4") 1) (equal bh:next "5")) "click-only-continuous-two-through-four")',
        '(bht:assert (bht:point= (bht:world (entlast) (car (bht:vertices (entlast)))) \'(120 0 0)) "next-target-click-is-reused-exactly-once")',
        'U', '(bht:assert (and (= (bht:number-count "4") 0) (= (bht:number-count "3") 1) (= (bht:number-count "2") 1)) "one-undo-removes-only-last-continuous-label")',
        # A new AutoLISP evaluation can invalidate REDO even if it only queries entities.
        'U', '_.REDO', '(bht:assert (= (bht:number-count "3") 1) "redo-immediately-after-undo-restores-continuous-label")',
        'BH', '0,40,0', '25,55,0', '001 40,40,0', '65,55,0',
        '\x1b(bht:assert (and (= (bht:number-count "001") 1) (= (bht:number-count "002") 1) (equal bh:next "003")) "typed-numeric-label-is-not-direct-distance-and-preserves-zeros")',
        'BH', '80,40,0', '105,55,0', 'A01 120,40,0', '145,55,0',
        '\x1b(bht:assert (and (= (bht:number-count "A01") 1) (= (bht:number-count "A02") 1) (equal bh:next "A03")) "typed-mixed-label-space-goes-straight-to-next-target")',
        'BH', '0,80,0', '25,95,0', 'Z 40,80,0', '65,95,0',
        '\x1b(bht:assert (and (= (bht:number-count "Z") 1) (= (bht:number-count "AA") 1)) "letters-increment-across-Z-to-AA")',
        '(setq bh:next "501")', 'BH', '80,80,0', '105,95,0', '  120,80,0', '145,95,0',
        '\x1b(bht:assert (and (= (bht:number-count "501") 1) (= (bht:number-count "502") 1)) "blank-space-confirms-and-extra-space-does-not-exit")',
        '(setq plt:count (bht:count) plt:next bh:next)', 'BH',
        '\x1b(bht:assert (and (= (bht:count) plt:count) (equal bh:next plt:next)) "Esc-before-first-click-does-not-create-a-label")',
        'BH', '160,80,0',
        '\x1b(bht:assert (and (= (bht:count) plt:count) (equal bh:next plt:next)) "Esc-after-first-click-cancels-only-unfinished-preview")',
        'BH', '0,120,0', '25,135,0', 'A-1 ABC1 ',
        '\x1b(bht:assert (= (bht:number-count "ABC1") 1) "invalid-identifier-reprompts-without-losing-current-label")',
        'BH', '160,120,0', '185,135,0', '123456789012345678901234567890123 VALID1 ',
        '\x1b(bht:assert (= (bht:number-count "VALID1") 1) "overlong-identifier-reprompts-without-partial-text")',
        '(setq bh:next "1" plt:ones (bht:number-count "1"))',
        'BH', '200,120,0', '203,120,0', 'AAAAAAAAAA 240,120,0', '265,135,0',
        '\x1b(bht:assert (and (= (bht:number-count "1") (+ plt:ones 1)) (= (bht:number-count "AAAAAAAAAA") 0)) "overlapping-renumber-keeps-default-and-allows-next-target-click")',
        '(setq bh:next "F1" plt:count (bht:count))', 'BH',
    ]
    for index in range(20):
        steps += [f'{index*40},180,0', f'{index*40+25},195,0']
    steps += [
        '\x1b(bht:assert (and (= (bht:count) (+ plt:count 20)) (= (bht:number-count "F20") 1) (equal bh:next "F21")) "twenty-callouts-without-confirmation-spaces")',
        '(setenv "PatentLabel.Confirm" "Enter")', '(setq bh:next "E1")',
        'BH', '0,240,0', '25,255,0', 'E100 40,240,0', '65,255,0',
        '\x1b(bht:assert (and (= (bht:number-count "E100") 1) (= (bht:number-count "E101") 1)) "continuous-space-confirm-is-independent-of-BHXG-enter-only-setting")',
        '(setq plt:edited (bh:read-number "1"))', '701 702', '703',
        '(bht:assert (equal plt:edited "703") "BHXG-enter-only-validation-still-rejects-embedded-spaces")',
        '(setenv "PatentLabel.Confirm" "Space")',
        'BH', '0,280,0', '25,295,0', 'a01 40,280,0', '65,295,0',
        '\x1b(bht:assert (and (= (bht:number-count "a01") 1) (= (bht:number-count "a02") 1)) "native-arbitrary-input-preserves-lowercase-identifiers")',
        '(command-s "_.UNDO" "_Auto" "_On")', '(setq bh:next "701")',
        'BH', '40,120,0', '65,135,0', '80,120,0', '105,135,0',
        '\x1bU', '(bht:assert (and (= (bht:number-count "701") 1) (= (bht:number-count "702") 0)) "automatic-undo-on-still-removes-only-one-label")',
        '(bht:assert (= 0 (logand 8 (getvar "UNDOCTL"))) "command-exit-leaves-no-undo-group-open")',
        '(bht:assert (not (wcmatch (strcase (getvar "CMDNAMES")) "*BH*")) "Esc-returns-to-normal-CAD-command-prompt")',
        '(bht:finish)', '_.QUIT', '_No',
    ]
    script = output/'console-input.txt'
    script.write_text('\n'.join(steps)+'\n',encoding='mbcs')
    snapshot = isolated_settings()
    try:
        if args.legacy_engine:
            engine = output/'engine.scr'; engine.write_text('(setvar "LISPSYS" 0)\n_.QUIT\n',encoding='ascii')
            run_core(DEFAULT_EXE,output/'input.dwg',engine,output/'engine.log',90)
        # Feed the native console, rather than SCRIPT: SCRIPT introduces a macro undo
        # wrapper when UNDO Auto is on and cannot represent an interactive BH session.
        with (output/'run.log').open('wb') as log:
            process = subprocess.run([str(DEFAULT_EXE),'/i',str(output/'input.dwg'),'/l','en-US',
                '/isolate',ISOLATION_USER,str(output/'isolated-profile')], input=script.read_bytes(),
                stdout=log,stderr=subprocess.STDOUT,timeout=90,creationflags=subprocess.CREATE_NO_WINDOW)
        (output/'run.txt').write_text(decode_log((output/'run.log').read_bytes()),encoding='utf-8')
        if process.returncode: raise RuntimeError(f'Core Console failed: {process.returncode}; {output}')
        results = (output/'results.txt').read_text(encoding='utf-8')
        print(results)
        summary = re.search(r'^SUMMARY (\d+) (\d+)$',results,re.M)
        if not summary: raise RuntimeError(f'Continuous suite did not finish: {output}')
        expected = re.search(r'^PERSIST_EXPECT (\d+)$',results,re.M)
        prefix = steps[:steps.index('(bht:init)')]
        reopen = output/'reopen.scr'
        reopen.write_text('\n'.join(prefix + [f'(setq bht:expected {expected[1]})', '(bht:reopen)', '_.QUIT', '_No'])+'\n',encoding='mbcs')
        run_core(DEFAULT_EXE,output/'verification.dwg',reopen,output/'reopen.log',90)
        reopened = re.search(r'^REOPEN_SUMMARY (\d+) (\d+)$',(output/'results.txt').read_text(encoding='utf-8'),re.M)
        if not reopened: raise RuntimeError(f'Reopen checks did not finish: {output}')
        report = {'passed':int(summary[1])+int(reopened[1]),'failed':int(summary[2])+int(reopened[2]),'english':args.english,'basic':args.basic,
                  'legacy_engine':args.legacy_engine,'desktop_automated':False,'output':str(output)}
        (output/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print(json.dumps(report,indent=2));return 1 if report['failed'] else 0
    finally: restore_isolated_settings(snapshot)


if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    raise SystemExit(main())
