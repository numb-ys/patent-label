# Changelog

## 0.4.0 - Continuous click or type workflow

- BH stays active until Esc. Click the next target immediately after placing a label to accept the suggested number and start another leader.
- Optionally type digits/letters and press Space/Enter, then click the next target directly. A blank Space accepts the default and continues.
- The second click places a complete default label. Esc keeps it; Esc after only the target click cancels that unfinished preview.
- Creation and an optional number replacement share one undo group per callout. Existing grip movement and native text editing remain available after leaving BH.
- Continuous BH always accepts Space/Enter; BHSZ confirmation-key preference applies to BHXG editing.
- Updated all six language/year packages and guides.

Validation uses native AutoCAD 2026 console input outside SCRIPT macro grouping, including 20 successive click-only callouts, numeric/letter input, cancel, per-callout undo with Auto on/off and save/reopen. Actual 2014/2019 desktop testing is still required.

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
