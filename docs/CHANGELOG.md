# Changelog

## 0.3.2 - Native live label grip

- Select a callout normally and drag the blue grip at its label center. The full leader previews continuously with a fixed target; no typed command is needed.
- Native grip/draw/extents overrules are restricted to PatentLabel blocks. Preview callbacks only change detached graphics; a final native grip transaction saves the label and leader together.
- Esc cancels, one Undo/Redo restores both parts, and copied callouts stay independent. Existing blocks need no conversion. BHYD remains optional.
- English and Chinese editions and guides updated for 2014, 2019 and 2026. Restart AutoCAD after installing.

Validation: 27 native grip checks per language in isolated 2026 Core Console runs, including real native grip callbacks, successive drag samples, drawing extents, actual WorldDraw/plot output, cancellation and undo/redo. Desktop mouse interaction and actual 2014/2019 installations still require user testing.

## 0.3.1 - Leader attachment

- The leader follows a moved `NUMBER` attribute after the native command finishes. The target on the part stays fixed.
- Native attribute text edits recalculate the leader gap. Existing un-exploded PatentLabel blocks work without conversion.
- New `BHYD` command moves the label with a full leader preview; Esc cancels.
- Copied blocks receive independent definitions on edit. Undo/redo restores the text and leader together.
- Renumbering or restyling a repositioned label preserves its new position.
- English and Chinese editions share this behavior for AutoCAD 2014, 2019 and 2026. Restart AutoCAD after updating.
- Updated English PDF and Chinese quick-start guides. No custom double-click editing hooks were added.

Validation: 31 attachment checks per language, 37 native preview/font checks per language, and 81 backend checks per language in isolated AutoCAD 2026 Core Console runs; installer mock tests and legacy API/framework builds passed. The attachment suite includes save/reopen, copy isolation, undo/redo, scale, rotated UCS and the native preview input bridge. Actual 2014/2019 desktop and mouse behavior still require user testing.

## 0.3.0 - First public English preview

ASCII English prompts and installers, Arial Regular default, three AutoCAD targets, English user guides and MIT licensing. Chinese 0.2.4 packages were retained with license notices.
