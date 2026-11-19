# Building and testing

## Layout

- `src/PatentLabel.lsp`, `src/PatentLabel.UI/`: original Chinese 2026 backend and native preview module.
- `src/PatentLabel.en.lsp`: generated, ASCII English backend. `i18n/en.json` contains the prompt translations.
- `src/english/LabelFonts.cs`: English Arial font implementation.
- `scripts/generate_english.py`: reuses shared behavior to generate per-year English sources into ignored `build/` output.
- `src/PatentLabel.English2014`, `2019`, `2026`: target-specific project files.
- `legacy/AutoCAD2014`, `legacy/AutoCAD2019`: original Chinese installer and backend sources.
- `deployment/english/Install.ps1.in`: English installer template, with owned-bundle checks and exact release detection.
- `tests/`: portable/source checks, installer mock checks, binary metadata inspection and optional native Core Console checks.

## Requirements and references

Use Python 3.10+ and a .NET 8+ SDK. Build the Windows targets on Windows. The 2019 and 2026 English targets use exact official NuGet versions `23.0.0` and `25.1.0` of `AutoCAD.NET.Core` and `AutoCAD.NET.Model`. Framework reference packs are build-time packages only.

AutoCAD 2014 requires separately obtained ObjectARX 2013/2014 managed references. They are not in Git and must not be committed or redistributed with releases. Autodesk lists the 2013 SDK as supported for AutoCAD 2014 in its [compatibility table](https://help.autodesk.com/cloudhelp/2020/ENU/AutoCAD-Customization/files/GUID-A6C680F2-DE2E-418A-A182-E4884073338A.htm).

```powershell
python scripts/package_english.py --year 2019
python scripts/package_english.py --year 2026
python scripts/package_english.py --year 2014 --sdk2014 C:\SDK\ObjectARX2013\inc
```

No installer runs during packaging. `--no-build` packages an already built DLL. A compiled DLL is copied with a versioned filename so an update does not overwrite a loaded module. Release builds omit debug symbols to avoid publishing developer-machine paths.

## Automated checks without AutoCAD

```powershell
python -m unittest discover -s tests -p "test_public*.py" -v
python scripts/package_english.py --year 2019
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_english_installer.ps1 -Year 2019 -PackageDirectory build/packages/PatentLabel-AutoCAD2019-0.3.2-en
dotnet run --project tests/Metadata2014/Metadata2014.csproj -- src/PatentLabel.English2019/bin/Release/net47/PatentLabel.English2019.dll ".NETFramework,Version=v4.7" "23.0."
```

Installer tests use a fake document and a temporary APPDATA folder. They do not connect to AutoCAD or change the real user profile. CI builds and packages 2019/2026 and runs source/installer checks. It does not have licensed CAD installations; do not describe CI as native CAD validation. The 2014 build remains a developer-supplied-SDK step.

## Native Core Console checks

Run only with a separately installed AutoCAD and a disposable template. `scripts/test_plugin.py` accepts `--autocad`, `--template`, `--source`, `--legacy-engine` and `--english`. Pass local paths as needed; its default template path is the developer's Chinese 2026 profile.

```powershell
python scripts/test_plugin.py --source build/english/2019/PatentLabel.lsp --legacy-engine --english
python scripts/test_ui.py --english
dotnet build tests/AttachmentCommands/AttachmentCommands.csproj -c Release
python scripts/test_attachment.py --english
python scripts/test_grips.py --english
```

These checks isolate the test registry branch, restore its selected settings and use temporary drawing copies. `--legacy-engine` restarts that isolated Core Console profile with `LISPSYS=0`. A passing 2019 LSP check in a 2026 host verifies common backend behavior and ASCII loading only, not native 2019 compatibility.

The attachment suite loads a test-only command assembly in the isolated 2026 host. It changes attributes through native command transactions, then checks deferred synchronization, copied-block isolation, one-step undo/redo, cancelled transactions, UCS/scale, the move-preview input bridge and save/reopen. The helper assembly is never packaged. Object-modified notifications only collect IDs; geometry updates run after completed commands, without native double-click interception or interactive calls in event handlers.

The grip suite calls AutoCAD's actual GetGripPoints/MoveGripPointsAt protocol on disposable native clones and real block references. It verifies continuous samples, fixed targets, preview extents, cancel, commit, copy isolation and undo/redo. A separate plot-only fixture calls the native WorldDraw path and exports its preview to PDF for visual inspection. Production preview callbacks draw detached entities and do not write to the DWG; only the final database-resident grip callback commits geometry. Custom grip/draw/extents rules use the PATENT_LABEL XData filter. Do not dispose grips returned by an overrule manually after notifying GripsToBeDeleted; the managed host releases those grips.

Desktop users should additionally verify cursor preview, selection, second-click preview retention, cancel, focus, native attribute editing, startup/new-document loading and save/reopen behavior on each claimed CAD/Windows language combination. Do not modify working drawings for automated testing.

## Documentation

The Markdown guide is authoritative. To regenerate the English PDF, install authoring dependencies in your own development environment and run:

```powershell
python -m pip install reportlab pypdf
python scripts/create_english_manual.py
```

Render the resulting PDF and inspect every page before publishing. The existing Chinese guide generator is `scripts/legacy/create_quickstart2014.py --year 2014` or `--year 2019`. It additionally uses Windows Chinese fonts.
