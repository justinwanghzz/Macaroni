# Fifth-pass changes — Utility 0.5.0 (build 10)

Implemented against the 13 items in `Testing/REVIEW_LOG.md`. That log remains the reviewer's original record; this file records the implementation.

| Item | Change |
| --- | --- |
| 1. Output names | Shared `OutputNaming` rules; Settings → Output naming edits suffixes, dimension/speed/workflow patterns and combined-PDF names. Underscore collision numbering; repeated operation suffixes collapse, including previously numbered inputs. Resize names use actual resulting dimensions. Processing preserves originals. Shelf delivery keeps Finder-style names. |
| 2. Image PDF export | Editable suggested name, visible destination, source-folder direct export, collision-safe commit and close on success |
| 3. Shelf | Independent List/Icons toggle; List default with 56-point rows; default height 60% of the usable screen, vertically centered; explicit resize persists |
| 4. Rotation Reset | Same tile content dimensions, button style and spacing as the rotation presets |
| 5. Secondary exports | Image adjustments, video compression/speed, workflows, PDF organizer and editor expose the destination; source folder by default; Choose folder before exporting |
| 6. Secondary UI | Soft PDF view selector, rounded page actions, direct Export PDF labels; internal unique window keys no longer appear in native PDF titles |
| 7. Office dependency | Removed Office-to-PDF backend, preview/controller, drop targets, executable settings and dependency prompts. DOCX/PPTX Markdown parser retained |
| 8. PDF OCR | Direct Core Graphics raster, 2600-pixel longest edge, bounded per-page memory, per-page progress; accurate multilingual Vision recognition retained; timing/text comparison recorded separately |
| 9. Editor Find | Native incremental find bar, highlighted matches and next/previous navigation; toolbar and Command-F / Command-G / Shift-Command-G |
| 10. Video default | Percentage starts at 100%, MB equals source bytes / 1,000,000; existing synchronized relative/fixed batch controls retained |
| 11. Video mute/speed | Immediate Mute action; Video speed window from 0.25× to 3×, initially 1×, native play/pause/scrubber, spectral pitch preservation. Export time range and duration validation prevent stretched-audio tails |
| 12. Clipboard | Compact Clear unpinned / Clear all footer buttons replace the three-dot menu; existing cleanup behavior retained |
| 13. Image presets | Always-visible Preset target below JPEG/PNG, opposite Shelf. Autosaved image-only workflow editor; create/select/delete/rename/pin, native sidebar arrows and Enter, visual crop callback, compression estimate, compact image controls, final per-image PDF step |

## Decisions for previously open details

- A secondary window collecting inputs from multiple folders defaults to **the first input's folder**, shown before export; the user can choose another folder for the entire batch. Immediate drag conversions continue saving beside each individual source.
- A workflow crop previews its preceding steps and stores normalized coordinates; the same relative region applies to each image. It does not export a separate cropped file when accepted. Locked resize fits each image inside the chosen bounds and retains that image's aspect ratio.
- The workflow estimate is the combined actual encoded size through the first compression step, calculated in a cancellable background job. Later steps can change final size.
- The image workflow PDF step is final and creates **one PDF per image**. Combining inputs into one PDF remains a separate organizer action.
- Enter in a native sidebar runs the selected workflow; text fields handle Enter as editing completion. Run has no global Return shortcut that could intercept text editing.
- Editor Save updates an existing document; Save As suggests the current name. New documents suggest Untitled.md, with Untitled.pdf for export. The editor remains open after PDF export so editing can continue.

## Automated versus hands-on verification

`Scripts/test.sh` covers processing, file safety, naming, geometry, PDF content, OCR quality/timing, video duration/audio/pitch and cancellation. The isolated native smoke runner covers model persistence, actual direct exports/window closure, workflow crop callbacks, default settings, clipboard data restoration, editor rendering and paginated PDF output. It uses its own data directory and named clipboard.

No computer-use automation was used for this pass. Finder drag feel, text-field focus/renaming, player interaction, multiple displays and appearance remain the reviewer's hands-on checks in `Testing/FIFTH_PASS_RETEST.md`.
