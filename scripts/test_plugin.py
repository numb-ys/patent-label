"""Run actual AutoCAD Core Console tests against isolated drawing copies.

No packages required. Usage: py -3 scripts/test_plugin.py
"""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import winreg

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EXE = Path(r"D:\Program Files\AutoCAD 2026\accoreconsole.exe")
DEFAULT_TEMPLATE = Path.home() / "AppData/Local/Autodesk/AutoCAD 2026/R25.1/chs/Template/acadiso.dwt"
ISOLATION_USER = "PatentLabelTest"
ISOLATION_PARENT = r"Software\appdatalow\software\Autodesk\AutoCAD"


def setting_name(name: str) -> bool:
    lowered = name.lower()
    return lowered in {"filedialog", "filedia", "cmdecho", "commandecho", "osmode", "pickfirst", "trustedpaths", "lispsys"} or lowered.startswith("patentlabel.")


def isolated_settings() -> dict[str, dict[str, tuple[object, int]]]:
    """Read ONLY the dedicated Core Console isolation branch, never GUI profiles."""
    captured: dict[str, dict[str, tuple[object, int]]] = {}

    def visit(path: str) -> None:
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path) as key:
                values: dict[str, tuple[object, int]] = {}
                for index in range(winreg.QueryInfoKey(key)[1]):
                    name, value, kind = winreg.EnumValue(key, index)
                    if setting_name(name):
                        values[name] = (value, kind)
                captured[path] = values
                children = [winreg.EnumKey(key, index) for index in range(winreg.QueryInfoKey(key)[0])]
            for child in children:
                visit(path + "\\" + child)
        except FileNotFoundError:
            return

    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, ISOLATION_PARENT) as base:
            versions = [winreg.EnumKey(base, index) for index in range(winreg.QueryInfoKey(base)[0])]
    except FileNotFoundError:
        return captured
    for version in versions:
        visit(ISOLATION_PARENT + "\\" + version + "\\CoreUser\\" + ISOLATION_USER)
    return captured


def restore_isolated_settings(snapshot: dict[str, dict[str, tuple[object, int]]]) -> None:
    current = isolated_settings()
    for path, values in current.items():
        prior = snapshot.get(path, {})
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path, 0, winreg.KEY_SET_VALUE) as key:
            for name in values:
                if name not in prior:
                    winreg.DeleteValue(key, name)
            for name, (value, kind) in prior.items():
                winreg.SetValueEx(key, name, 0, kind, value)


def lisp_string(value: str | Path) -> str:
    return '"' + str(value).replace("\\", "/").replace('"', '\\"') + '"'


def decode_log(data: bytes) -> str:
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16", errors="replace")
    if data.count(b"\x00") > len(data) // 8:
        return data.decode("utf-16-le", errors="replace")
    return data.decode("utf-8", errors="replace")


def run_core(exe: Path, drawing: Path, script: Path, log: Path, timeout: int) -> None:
    with log.open("wb") as output:
        result = subprocess.run(
            [str(exe), "/i", str(drawing), "/s", str(script), "/l", "en-US",
             "/isolate", ISOLATION_USER, str(log.parent / "isolated-profile")],
            stdin=subprocess.DEVNULL,
            stdout=output,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
    log.with_suffix(".txt").write_text(decode_log(log.read_bytes()), encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"Core Console exited {result.returncode}; see {log.with_suffix('.txt')}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--autocad", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--source", type=Path, default=ROOT / "src/PatentLabel.lsp")
    parser.add_argument("--legacy-engine", action="store_true", help="Use the isolated host's MBCS AutoLISP engine for the legacy source")
    parser.add_argument("--english", action="store_true", help="Check Arial styles and English weight settings")
    args = parser.parse_args()
    for required in (args.autocad, args.template, args.source):
        if not required.is_file():
            parser.error(f"Missing required file: {required}")
    output = ROOT / "artifacts" / ("integration-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    output.mkdir(parents=True)
    drawing = output / "input.dwg"
    shutil.copy2(args.template, drawing)
    tested_source = output / "tested-PatentLabel.lsp"
    shutil.copy2(args.source, tested_source)
    source_sha256 = hashlib.sha256(tested_source.read_bytes()).hexdigest()
    definitions = ROOT / "tests/integration.lsp"
    if args.english:
        definitions = output / "integration-en.lsp"
        definitions.write_text((ROOT / "tests/integration.lsp").read_text(encoding="utf-8")
                               .replace("PATENT_LABEL_SIMHEI_", "PATENT_LABEL_ARIAL_")
                               .replace("PatentLabel.SimHeiWeight", "PatentLabel.EnglishWeight")
                               .replace("simhei", "arial"), encoding="ascii")
    common = (
        f"(setq bht:output {lisp_string(output)})\n"
        '(setq bht:saved-vars (mapcar \'(lambda (key) (cons key (getvar key))) \'("FILEDIA" "CMDECHO" "OSMODE" "TRUSTEDPATHS")))\n'
        '(setq bht:saved-env (mapcar \'(lambda (key) (cons key (getenv key))) \'("PatentLabel.Height" "PatentLabel.Landing" "PatentLabel.Gap" "PatentLabel.Confirm" "PatentLabel.Bold" "PatentLabel.SimHeiWeight" "PatentLabel.EnglishWeight")))\n'
        '(setq bht:trusted (getvar "TRUSTEDPATHS"))\n'
        f'(setvar "TRUSTEDPATHS" (strcat bht:trusted ";" {lisp_string(output)} ";" {lisp_string(ROOT / "tests")}))\n'
        f"(load {lisp_string(tested_source)})\n"
        f"(load {lisp_string(definitions)})\n"
        '(setvar "TRUSTEDPATHS" bht:trusted)\n'
        '(setq *error* bht:on-error)\n'
    )
    first = output / "create.scr"
    # SCR input uses the Windows system code page, independently of LISPSYS.
    steps = (
        '(bht:init)\n'
        '(bht:case "basic-case-completed" \'bht:basic)\n'
        '(bht:case "ucs-case-completed" \'bht:ucs)\n'
        '(bht:case "copy-edit-case-completed" \'bht:copy-edit)\n'
        '(bht:case "weight-case-completed" \'bht:weight)\n'
        '(bht:undo)\n'
        '(bht:case "locked-layer-case-completed" \'bht:locked-layer)\n'
        '(bht:case "paper-case-completed" \'bht:paper)\n'
        '(bht:finish)\n(bht:restore-settings)\n_.QUIT\n'
    )
    first.write_text(common + steps, encoding="mbcs")
    print(f"Running AutoCAD integration tests in {output}", flush=True)
    original_isolated_settings = isolated_settings()
    (output / "settings-snapshot.json").write_text(
        json.dumps(original_isolated_settings, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    try:
        if args.legacy_engine:
            engine_script = output / "legacy-engine.scr"
            engine_script.write_text('(setvar "LISPSYS" 0)\n_.QUIT\n', encoding="mbcs")
            run_core(args.autocad, drawing, engine_script, output / "legacy-engine.log", args.timeout)
        run_core(args.autocad, drawing, first, output / "create.log", args.timeout)
        result_file = output / "results.txt"
        results = result_file.read_text(encoding="utf-8")
        summary = re.search(r"^SUMMARY (\d+) (\d+)$", results, re.M)
        expected = re.search(r"^PERSIST_EXPECT (\d+)$", results, re.M)
        if not summary or not expected:
            raise RuntimeError("Integration suite did not complete; inspect create.txt")
        second = output / "reopen.scr"
        second.write_text(
            common + f"(setq bht:expected {expected[1]})\n(bht:reopen)\n(bht:restore-settings)\n_.QUIT\n",
            encoding="mbcs",
        )
        run_core(args.autocad, output / "verification.dwg", second, output / "reopen.log", args.timeout)
        results = result_file.read_text(encoding="utf-8")
        reopened = re.search(r"^REOPEN_SUMMARY (\d+) (\d+)$", results, re.M)
        if not reopened:
            raise RuntimeError("Reopen suite did not complete; inspect reopen.txt")
        failed = int(summary[2]) + int(reopened[2])
        passed = int(summary[1]) + int(reopened[1])
        report = {"passed": passed, "failed": failed, "output": str(output), "real_host": str(args.autocad),
                  "source": str(args.source.resolve()), "legacy_engine": args.legacy_engine, "english": args.english,
                  "source_sha256": source_sha256, "tested_source": str(tested_source),
                  "isolation_registry_parent": "HKEY_CURRENT_USER\\" + ISOLATION_PARENT,
                  "isolation_user": ISOLATION_USER}
        (output / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
        print(results, flush=True)
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 1 if failed else 0
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f"ERROR: {exc}\nArtifacts: {output}", file=sys.stderr)
        return 2
    finally:
        # Covers normal success, script errors, process timeout, and load failures.
        # Only selected values inside CoreUser/PatentLabelTest can be changed.
        restore_isolated_settings(original_isolated_settings)
        nonempty = lambda captured: {path: values for path, values in captured.items() if values}
        restored = nonempty(isolated_settings()) == nonempty(original_isolated_settings)
        cleanup = {"isolated_settings_restored": restored, "gui_profile_modified": False}
        (output / "cleanup.json").write_text(json.dumps(cleanup, indent=2), encoding="utf-8")
        if (output / "report.json").is_file():
            report = json.loads((output / "report.json").read_text(encoding="utf-8"))
            report.update(cleanup)
            (output / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
        if not restored:
            raise RuntimeError(f"Isolated settings cleanup differs from snapshot; inspect {output}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    raise SystemExit(main())
