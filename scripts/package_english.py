"""Build and package an English PatentLabel edition without installing it locally."""
import argparse
import json
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from generate_english import ROOT, VERSION, YEARS, prepare

TARGETS = {
    2014: {"api": "19.1", "bundle": "PatentLabel2014", "prefix": "PatentLabel.UI2014", "tfm": "net40", "product": "{DC15BCC6-A227-43B0-9E47-B1B772FE48ED}"},
    2019: {"api": "23.0", "bundle": "PatentLabel2019", "prefix": "PatentLabel.UI2019", "tfm": "net47", "product": "{ADB4DE6C-B867-4BBC-A3F6-862C78387076}"},
    2026: {"api": "25.1", "bundle": "PatentLabel", "prefix": "PatentLabel.UI", "tfm": "net8.0-windows", "product": "{8B0F3B60-D8F1-4C1B-84CE-C24A6025C691}"},
}


def package(year, no_build=False, sdk2014=None):
    config = TARGETS[year]
    prepare(year)
    if not no_build:
        cmd = ["dotnet", "build", str(ROOT / f"src/PatentLabel.English{year}/PatentLabel.English{year}.csproj"),
               "-c", "Release", "--nologo", "-p:DebugType=none", "-p:DebugSymbols=false"]
        if sdk2014:
            cmd.append(f"-p:AutoCAD2014RefDir={Path(sdk2014).resolve()}")
        subprocess.run(cmd, check=True)
    dll = ROOT / f"src/PatentLabel.English{year}/bin/Release/{config['tfm']}/PatentLabel.English{year}.dll"
    if not dll.is_file():
        raise FileNotFoundError(dll)
    destination = ROOT / f"build/packages/PatentLabel-AutoCAD{year}-{VERSION}-en"
    contents = destination / f"{config['bundle']}.bundle/Contents/Windows"
    contents.mkdir(parents=True, exist_ok=True)
    filename = f"{config['prefix']}.{VERSION}.{year}.dll"
    shutil.copy2(dll, contents / filename)
    shutil.copy2(ROOT / f"build/english/{year}/PatentLabel.lsp", contents / "PatentLabel.lsp")
    app = ET.Element("ApplicationPackage", SchemaVersion="1.0", AppVersion=f"{VERSION}.{year}",
                     AutodeskProduct="AutoCAD", ProductType="Application", Name=config["bundle"],
                     Author="numb-ys", Description=f"English patent drawing callouts for AutoCAD {year}", ProductCode=config["product"])
    components = ET.SubElement(app, "Components")
    ET.SubElement(components, "RuntimeRequirements", OS="Win64" if year == 2026 else "Win32|Win64", Platform="AutoCAD",
                  SeriesMin=f"R{config['api']}", SeriesMax=f"R{config['api']}")
    ET.SubElement(components, "ComponentEntry", AppName=f"PatentLabel.English{year}", AppType=".Net",
                  ModuleName=f"./Contents/Windows/{filename}", AppDescription="English callout preview", LoadOnAutoCADStartup="True")
    ET.indent(app, space="  ")
    ET.ElementTree(app).write(destination / f"{config['bundle']}.bundle/PackageContents.xml", encoding="utf-8", xml_declaration=True)
    installer = (ROOT / "deployment/english/Install.ps1.in").read_text(encoding="ascii")
    substitutions = {"YEAR": str(year), "BUNDLE": config["bundle"], "PRODUCT": config["product"],
                     "API": config["api"], "MAJOR": config["api"].split(".")[0], "DLLPREFIX": config["prefix"],
                     "DLLREGEX": re.escape(config["prefix"])}
    for key, value in substitutions.items():
        installer = installer.replace(f"@@{key}@@", value)
    if "@@" in installer:
        raise ValueError("Unexpanded installer placeholder")
    (destination / "Install.ps1").write_bytes(installer.replace("\n", "\r\n").encode("ascii"))
    for action in ("Install", "Uninstall"):
        command = (f'@echo off\r\nsetlocal\r\necho Open a drawing in AutoCAD {year} first.\r\n'
                   f'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" -Action {action}\r\n'
                   f'if errorlevel 1 (echo {action} did not finish. Keep the error message above.) else (echo Done. Restart AutoCAD {year}.)\r\npause\r\n')
        (destination / f"{action}.cmd").write_bytes(command.encode("ascii"))
    manual = (ROOT / "docs/USER_GUIDE_EN.md").read_text(encoding="utf-8").replace("{{YEAR}}", str(year))
    (destination / "START-HERE.txt").write_bytes(manual.replace("\n", "\r\n").encode("ascii"))
    shutil.copy2(ROOT / "LICENSE", destination / "LICENSE")
    shutil.copy2(ROOT / "THIRD_PARTY_NOTICES.md", destination / "THIRD_PARTY_NOTICES.md")
    pdf = ROOT / "docs/USER_GUIDE_EN.pdf"
    if pdf.is_file():
        shutil.copy2(pdf, destination / "USER_GUIDE_EN.pdf")
    # Explicit inputs prevent SDKs, old builds and working drawings from entering the archive.
    files = [contents / filename, contents / "PatentLabel.lsp", destination / f"{config['bundle']}.bundle/PackageContents.xml",
             destination / "Install.ps1", destination / "Install.cmd", destination / "Uninstall.cmd", destination / "START-HERE.txt",
             destination / "LICENSE", destination / "THIRD_PARTY_NOTICES.md"]
    if pdf.is_file():
        files.append(destination / "USER_GUIDE_EN.pdf")
    archive = ROOT / f"dist/PatentLabel-AutoCAD{year}-{VERSION}-en.zip"
    archive.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for path in files:
            output.write(path, str(Path(destination.name) / path.relative_to(destination)))
    print(json.dumps({"year": year, "package_directory": str(destination), "archive": str(archive)}))
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--year", type=int, choices=YEARS, required=True)
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--sdk2014")
    args = parser.parse_args()
    package(args.year, args.no_build, args.sdk2014)
