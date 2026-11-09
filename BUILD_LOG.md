# Macaroni — build and iteration history

From the first working draft to **0.5.8**. This history is reconstructed from the saved implementation plans, version notes, validation reports and review log. It is a development summary, not a complete record of every coding session. Dates are included only where the records establish them.

## Starting point: what we intended to build

The project began as a background macOS utility for everyday file work. Instead of opening a large application, the user would drag a file, hold a shortcut and see relevant actions beside it. The proposed modules were file tools, a temporary shelf, clipboard history, a lightweight Markdown/math editor and reusable workflows.

The application itself did not need an AI agent. The project used a coding agent to build and iterate on a useful native product.

Planning records: [implementation plan](docs/INITIAL_PLAN.md), [implementation backlog](docs/INITIAL_BACKLOG.md).

## Version-by-version history

| Stage / version | What prompted the iteration | What we built or changed |
| --- | --- | --- |
| **First working draft — October 31, 2026** | Turn the proposal into an actual application | Native Swift/AppKit/SwiftUI menu-bar app; Shift-drag contextual actions; image format conversion, compression, resize, rotation and flips; target-size video compression; text PDF/DOCX/PPTX to Markdown; persistent file shelf with copy/move; text/image clipboard history with search and pins; offline Markdown/math editing and PDF export; saved action pipelines; progress, cancellation, per-file results and safe output naming. Initial records describe a shared Exports destination and a more intrusive shelf/popup experience. |
| **0.2 — First review pass, November 7** | R001–R015: make the app behave more naturally in Finder and provide real visual adjustment tools | Shelf became an explicit target rather than appearing during every conversion; compact, resizable shelf with native multi-selection and drag-out Copy/Move; outputs saved beside sources and selected in Finder; configurable drag activation; separate conversion/tool targets around an open center; visual crop with handles and ratios; width/height resize with lock and scale slider; compression preview with a real encoded-size estimate; live rotation with presets/custom angles; source-folder grants; more consistent secondary windows and result feedback. |
| **0.2.1 — Popup redesign** | The circular targets felt scattered and too similar to the reference interaction | Replaced bubbles with aligned rounded cards; formats above, tools below and a dedicated shelf position. Targets stayed fixed during a short fade. Whole-menu translation handled screen edges. Introduced the muted indigo/teal palette and removed the unchanged “Images for sharing” sample preset. |
| **0.3.0 — Second review pass** | R016–R029: refine layout, previews, clipboard behavior and ordinary editing | More deliberate layouts for images, videos, documents and mixed selections; category colors and eligible-file counts; cleaner completion cards; immediate cached rotation preview and visual angle tiles; optional Clear after copy; synchronized video percentage/MB controls; direct Markdown opening with multi-file switching and unsaved-change protection; clipboard recording on by default with persistent Pause; searchable hotkey popup with arrows, Enter and destination paste; fixes for restoring older image content after copying newer text. Video compression initially opened at 50%. |
| **0.4.0 — Third review pass** | R030–R036: expand PDF/document capabilities and improve clipboard file handling | Single-image PDF creation and multi-image PDF assembly; PDF combining with whole-document and individual-page ordering; rotation/removal while retaining selectable PDF text; on-device English/Chinese image and scanned-PDF OCR; native clipboard file references, including multiple files and missing-file handling. Added an optional LibreOffice-backed Excel/PowerPoint-to-PDF feature. Tried Fn–Shift–V for clipboard history. |
| **0.4.1 — Shortcut correction** | Fn-based activation did not work reliably for the user's workflow | Changed clipboard history to **Option–Shift–V**, migrated saved Fn defaults and retained explicitly selected alternatives. This remains the current default. |
| **0.4.2 — Fourth-pass image menu** | R037–R038: reduce clutter and clarify the action hierarchy | Four image conversions in one row: JPEG, PNG, HEIC and PDF. Six tools in two rows: Crop, Compress, Resize, Rotate, Flip H and Flip V. Removed image-to-Markdown from the image popup while retaining OCR processing elsewhere. Shelf was initially placed above the format row. |
| **0.4.3 — Shelf placement correction** | R039: refine where Shelf belongs relative to the dragged file | Moved Shelf into the central gap on the right, beneath the midpoint between HEIC and PDF. Formats and tools retained their existing rows. |
| **0.4.4 — Shelf polish** | R040: improve the floating shelf's appearance | Cleaner title bar, compact Copy/Move control, rounded thumbnail cards, clearer selection, filenames/sizes, softer light/dark surfaces and a viewport-width fix for narrow shelves. |
| **0.5.0 — Fifth review pass** | Thirteen new items covering naming, exports, shelf modes, OCR, video and presets | Configurable output naming, operation suffixes and collision numbering; direct source-folder exports with editable destinations; PDF auto-close after successful export; List/Icons shelf modes and a 60%-screen-height default; matching rotation Reset tile; softer PDF controls and clean window titles; removal of LibreOffice-dependent conversions; bounded direct PDF rasterization for OCR and per-page progress; editor Find; video compression initially at 100%; video mute and 0.25×–3× speed adjustment with pitch-preserved audio and player preview; explicit clipboard cleanup buttons; always-visible Preset target and an autosaving image-only workflow editor with rename/pin, visual crop, compression estimates and a final per-image PDF step. |
| **0.5.1 — Editor and export refinement** | Follow-up: search/toolbar looked cluttered, folder paths were too long, video batches needed individual settings, and workflow steps needed editable action types | Compact editor toolbar and an on-demand search strip with counts/highlights/navigation; moved editor PDF options into an attached export dialog; shortened destination displays to folder names with the full path on hover; selectable video previews and independent speeds for each clip, plus Apply to all; removed the video explanatory paragraph; restored action dropdowns on workflow steps with appropriate default settings and PDF-last validation. |
| **0.5.2 — Compact action footers** | Follow-up: destination cards occupied an unnecessary extra row | Destination/Change now shares the bottom action row with Crop/Apply, Compress, Export or Run in image, video, PDF and workflow windows. PDF filenames remain editable in a simple separate field. Reduced video-window heights. The approved Markdown editor/export dialog was left unchanged. |
| **0.5.3 — Linked editor navigation** | Follow-up: source and preview needed Overleaf-style navigation | Source caret/editing reveals and marks the corresponding preview block; clicking preview headings, paragraphs, tables, equations or code jumps back to source. Added Unicode-safe line mapping, stale-render protection and PDF-safe highlighting. |
| **0.5.4 — Macaroni name** | User chose the final product name | Renamed the app bundle, executable, visible app/menu labels and distribution artifacts to Macaroni; retained internal module names and storage identity for compatibility. |
| **0.5.5 — Macaroni icon** | User requested matching icon artwork and GitHub publication | Added golden macaroni app artwork, native monochrome menu-bar mark and public-repository documentation. |
| **0.5.6 — Hosted compiler compatibility** | User supplied the failed GitHub build log | Made rotation-preview Double/CGFloat conversions explicit to remove an overloaded cos inference failure in the hosted macOS compiler. |
| **0.5.7 — Mixed PDF assembly** | Mixed image and PDF drag selection | Replaced separate combine targets with one action. Image pages start before the selected PDF pages, with whole-document and page-level editing before a single export. |
| **0.5.8 — Resize input** | Clearing a locked dimension restored the previous value | Kept the raw field text during editing and paused preview and export while a dimension is blank. |

## How the main modules evolved

| Module | First working draft | Current behavior |
| --- | --- | --- |
| **Contextual actions** | Contextual popup; early layouts could cover the file or open too much UI | Aligned targets, stable entrance, type-specific actions, source clearance, Shelf on the right and image Preset on the left |
| **Image tools** | Conversion, compression, resize, rotation and flips | Visual crop, dimensions/ratio lock/scaling, live previews, real compression estimates, custom angles, safe naming and compact export footers |
| **Video** | Compress to a measured maximum size | Synchronized percentage/MB targets, 100% starting value, mute, selectable previews, individual 0.25×–3× speeds and pitch-preserved export |
| **PDF/documents** | Extract readable PDF/DOCX/PPTX text | Image-to-PDF, PDF assembly and page editing, scanned-document OCR, faster bounded PDF rendering; Word/PowerPoint Markdown extraction retained |
| **Shelf** | Persistent collection and copy/move operations | Explicit activation, narrow resizable panel, native selection/drag delivery, optional copy cleanup, List/Icons and adaptive height |
| **Clipboard** | Text/images, history search and pins | Compact Option–Shift–V popup, keyboard navigation, reliable older-content restoration, native single/multiple file references, Pause and direct cleanup buttons |
| **Editor** | Source/live preview, Markdown/math and PDF export | Direct file opening, multi-file switching, protected unsaved edits, cleaner toolbar, conditional search strip and a separate PDF export dialog |
| **Workflows** | Save and run ordered action pipelines | Image-only autosaved editor, sidebar rename/pin/navigation, dropped-file inputs, changeable action types, visual crop and per-image PDF output |
| **Exports** | Shared output folder and basic unique names | Source-folder defaults, configurable operation names, `_2`/`_3` collisions, editable PDF names, concise destination controls and preserved originals |

## Decisions we changed after testing

- **Circle → aligned cards:** the visual novelty mattered less than predictable placement and readable choices.
- **Automatic shelf → explicit shelf:** ordinary conversions should not open unrelated UI.
- **Shared output folder → source-folder defaults:** results should be easy to find where the work began.
- **Fn shortcut → Option–Shift–V:** the actual keyboard experience overruled the earlier design choice.
- **Add Office-to-PDF → remove it:** the external LibreOffice dependency created setup friction; independent Word/PowerPoint Markdown extraction remained useful.
- **Persistent export controls → contextual controls:** editor export options appear only on request; image/video destination controls fit beside the action buttons.
- **Manual workflow save → autosave:** editing a preset should not require remembering a separate Save action.
- **One batch speed → per-video speeds:** preview selection and export settings now match individual inputs.

## Testing alongside the iterations

The initial draft recorded **10 passing core tests**. Later validation records report 16 for 0.2, 21 for 0.3, 30 for 0.4 and 36 for the 0.5 implementation/refinement stage. Test counts are snapshots, not a cumulative feature score: tests were added and obsolete dependency-specific tests were removed.

Checks expanded from basic conversion and source preservation to image pixels/dimensions, native copy/move delivery, PDF text/page order, clipboard restoration, OCR text/timing, video size/duration/audio/pitch, workflow persistence and editor export. Isolated app smoke checks also ran against extracted release packages with temporary app data and a named test clipboard.

For the fifth-pass scan benchmark, the recorded warm measurements changed from about **0.212 → 0.176 seconds** for one page and **0.512 → 0.443 seconds** for three pages, retaining the English/Chinese text. These results apply to the supplied samples, not every possible scan.

The 0.5.2 package passed strict signature verification and its isolated smoke suite on a fresh-storage rerun. Its initial smoke run hit an editor-load assertion that did not reproduce; this remains recorded in that version's notes. Styling, real Finder gestures, hotkey conflicts and hardware-specific interaction still need hands-on review; automated checks do not establish that every manual interaction passed.

## Where the original evidence lives

- **Original feedback:** [Testing/REVIEW_LOG.md](docs/REVIEW_TRACE.md). Its “Recorded” statuses preserve the feedback as written; they are not a current implementation-status tracker.
- **First draft:** [validation](docs/VALIDATION.md), [architecture](docs/ARCHITECTURE.md).
- **First review:** [0.2 changes](docs/REVIEW_CHANGES_0.2.md), [validation](docs/VALIDATION_0.2.md), [0.2.1 UI redesign](docs/UI_CHANGES_0.2.1.md).
- **Second review:** [0.3 changes](docs/REVIEW_CHANGES_0.3.md), [validation](docs/VALIDATION_0.3.md).
- **Third review:** [0.4 changes](docs/REVIEW_CHANGES_0.4.md), [validation](docs/VALIDATION_0.4.md), [0.4.1 shortcut](docs/SHORTCUT_0.4.1.md).
- **Fourth review:** [0.4.2 menu](docs/REVIEW_CHANGES_0.4.2.md), [0.4.3 placement](docs/REVIEW_CHANGES_0.4.3.md), [0.4.4 shelf](docs/REVIEW_CHANGES_0.4.4.md).
- **Fifth review:** [0.5 changes](docs/REVIEW_CHANGES_0.5.md), [validation and OCR measurements](docs/VALIDATION_0.5.md).
- **Linked editor navigation:** [0.5.3 changes](docs/REVIEW_CHANGES_0.5.3.md), [validation](docs/VALIDATION_0.5.3.md).
- **Recent refinements:** [0.5.1 changes](docs/REVIEW_CHANGES_0.5.1.md), [validation](docs/VALIDATION_0.5.1.md), [0.5.2 compact footers](docs/REVIEW_CHANGES_0.5.2.md).
- **Compiler/test output:** version-labelled `.log` files and `Release-Smoke.json` under `build/`. These are local artifacts; some “latest” files are replaced by subsequent runs, so they are not a complete immutable archive of every build.
