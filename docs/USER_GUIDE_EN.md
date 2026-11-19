# PatentLabel English user guide

English preview release 0.3.0. For Windows full AutoCAD 2014, 2019 or 2026.
Use the ZIP built for your exact AutoCAD year. AutoCAD LT, macOS and other CAD products are not supported by these packages.

## Install once

1. Download the English ZIP for your AutoCAD year and extract the entire ZIP into a folder.
2. Open that AutoCAD version and open a drawing. Finish any active command and close command dialogs.
3. Double-click Install.cmd in the extracted folder. The script uses Windows PowerShell. Administrator access and developer tools are not required.
4. Wait for the Installed message. If the window reports an error, keep the error text.
5. Save your work, close AutoCAD and start it again. Look for the PatentLabel English loading message, then enter BH.

After installation, the plug-in loads at startup and when you open another drawing. You do not need APPLOAD for every drawing. Installation applies to the current Windows user and AutoCAD profile.

## Make a callout

1. Type BH and press Enter.
2. Click the point on the part that the leader should identify.
3. Move the mouse. The whole two-segment leader and suggested label follow the cursor.
4. Click the desired center of the label. The preview stays visible while you enter the label.
5. Accept the first suggested label, 1, with Space or Enter, or type another label first. This finishes the command.
6. Press Space again to start another callout with the next suggested label.

The two Space presses have separate jobs: the first confirms the current label; the second uses AutoCAD's normal repeat-command behavior. If you run another command in between, type BH again.

Labels contain 1-32 ASCII letters or digits. Examples: 123, A, a, A01 and 12A. The limit is 32 characters, not the numeric value 32. Suggestions include 001 -> 002, A99 -> A100 and Z -> AA. Duplicate labels are allowed.

## Edit labels and settings

- BHXG: select a callout, type its replacement label at the command line and confirm. The leader gap is recalculated. A copied callout can be edited independently.
- BHSZ: set label height, horizontal landing length, text gap, confirmation key and weight. Press Enter at a setting to keep its value. New English labels use Arial Regular by default.
- BHJC: select existing callouts and choose Bold or Regular. Selected labels are changed to Arial; leader lineweight stays unchanged.
- BHVER: show the edition, AutoCAD version, preview-module status and Arial font lookup.
- BHHELP: display command help.
- Esc cancels the current operation. At the first or second point prompt, Enter finishes or cancels the callout. Use U or Ctrl+Z to undo a completed operation.

Double-clicking a label uses AutoCAD's built-in attribute editor. Finish with that editor's normal OK/Close action. For a label change that also adjusts the leader, use BHXG.

## Troubleshooting and removal

- Unknown BH or no preview: restart AutoCAD after installation and run BHVER. If BHVER is also unknown, the backend has not loaded. Keep the loading/installer error text for the maintainer.
- Installer cannot find AutoCAD: open a drawing in the matching release and finish active commands. The installer deliberately rejects other AutoCAD versions.
- Font or layer error: make sure Arial is available and the PATENT_LABEL layer is on, thawed and unlocked.
- Switching between Chinese and English: run the desired package's installer and restart AutoCAD. Both language editions use the same owned bundle for that AutoCAD year. Do not manually NETLOAD both editions in one process.
- Manual temporary loading: NETLOAD the DLL in the package's .bundle/Contents/Windows directory. Its sibling PatentLabel.lsp must remain beside it. If necessary, APPLOAD that LSP once. Restart first if an older edition was loaded.
- To disable automatic loading, open the matching AutoCAD release, run Uninstall.cmd and restart. Files and backups are retained. The installer preserves unrelated trusted paths and SECURELOAD.

## Trial checklist

Try a blank drawing first. Check startup/new-drawing loading, both click positions, preview retention, accepting 1 without typing, Space-to-repeat, letters, copied-callout editing, undo, and saving/reopening a DWG.

The 2014 and 2019 packages are compiled against their supported APIs but need testing in those actual releases. Core Console checks on 2026 do not establish compatibility with another AutoCAD release or prove desktop mouse behavior. An English Windows/AutoCAD desktop still needs user verification.

For a bug report, include your AutoCAD year and update, Windows version, package language, BHVER output, reproduction steps and error text. Use a minimal sample drawing you are willing to share.
