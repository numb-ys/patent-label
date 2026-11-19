# Contributing

Please keep the two-click workflow and native Space-to-repeat behavior predictable. Explain the concrete problem, proposed behavior and validation in a pull request.

## Bug reports

Include the AutoCAD year/update, Windows language/version, package edition, `BHVER` output where available, reproduction steps, expected/actual behavior and error text. Use a minimal sample you are authorized to share. Do not attach confidential patent or client drawings.

## Changes

- Keep behavior in the shared backend/preview sources and add or update English translations when prompts change. Run `python scripts/generate_english.py` and inspect the generated diff.
- English LSP, installer and preview prompts must remain ASCII-safe. Font files are selected from the user's installation, never bundled.
- Do not reintroduce double-click command vetoes, HWND interception or modeless inline-edit callbacks without a separate design and actual native stability evidence.
- Keep ownership checks, exact CAD-version detection, trusted-path preservation and `SECURELOAD` preservation in installers.
- Do not commit SDKs, tokens, private drawings, generated logs, build directories or machine-specific install state.
- Run the relevant source, build, installer and native tests. State clearly which actual CAD releases and desktop interactions were tested.

By submitting a contribution, you agree to license it under this project's MIT license. Existing third-party rights remain unchanged.
