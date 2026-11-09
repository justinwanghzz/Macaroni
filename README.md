# Macaroni

<img src="Config/MacaroniIcon.png" width="128" alt="Macaroni app icon">

A local, open-source macOS utility that comes to the file you are working with. Start dragging a file in Finder, then hold **Shift** to reveal format choices above the file and editing tools below it. Drop onto an action to continue.

Development history: [BUILD_LOG.md](BUILD_LOG.md) tracks the first working draft, review-driven changes, version milestones and validation records.

Full feature list: [formats, image/video editing, PDFs, editor, shelf, clipboard and workflows](docs/FEATURES.md).

## Run

Requires macOS 14+ and, to build from source, Xcode with command-line tools selected. The packaged binary targets the build machine's architecture.

```sh
Scripts/build.sh
open build/Macaroni.app
```

Macaroni lives in the menu bar. Its menu opens the file shelf, clipboard, Markdown/math editor, workflows, Settings, and Recent results. Pause/Resume suspends the utility without quitting. Settings offers Shift, Control-Shift and Option-Shift activation. Fn/Globe is not advertised as an alternative without hardware validation.

Open `Package.swift` in Xcode to edit the project. The build script produces the real `.app` bundle, including offline renderer resources, metadata and an ad-hoc signature.

## What's included in 0.5.5

0.5.5 adds the golden macaroni app icon and matching monochrome menu-bar mark.

0.5.4 names the app **Macaroni**. The existing bundle identifier, data directory and Swift module names are retained so saved settings, shelf items, history and workflows continue to load.

0.5.3 links the editor panes: source caret/editing reveals the matching preview block; clicking preview content jumps to its source. See `docs/REVIEW_CHANGES_0.5.3.md`.

0.5.2 puts compact destination controls beside action buttons in image, video, PDF and workflow windows. The editor export dialog is unchanged.

0.5.1 refines editor search/toolbar and PDF export, compact folder controls, individual video speeds and workflow action dropdowns. See `docs/REVIEW_CHANGES_0.5.1.md`.

Fifth-pass changes add configurable output names, direct exports, a List/Icons shelf, video mute/speed, editor Find and an autosaving image workflow editor. See `docs/REVIEW_CHANGES_0.5.md`.

| Module | Behavior |
| --- | --- |
| Contextual menu | Image menu: a row of JPEG/PNG/HEIC/PDF formats, Preset below JPEG/PNG on the left and Shelf below HEIC/PDF on the right, then two rows of three image tools; other file types retain their compact/grouped menus; stable screen-edge placement and a brief fade |
| Shelf | Explicit Shelf drop target; resizable shelf with a 60% screen-height default; List/Icons toggle; native multi-selection and Command-A; Space/double-click preview; drag-out Copy/Move; empty shelf hides |
| Image tools | JPEG/PNG/HEIC conversion; interactive crop and ratios; width/height resize with lock and scaling; visual compression with trial-encode size; visual rotation presets and continuous custom-angle preview; separate immediate flips |
| Video | Source sizes, synchronized percentage/MB targets, relative or fixed batch budgets; H.264/AAC compression with verified output size/duration and cancellation; mute; 0.25×–3× speed export with pitch-preserved audio, selectable previews and individual speeds per clip |
| Documents | Images and scanned PDF pages to Markdown with local Vision OCR; text PDF, DOCX, PPTX and UTF-8 extraction |
| PDF organizer | Single-image PDF, multiple images/PDFs, whole-document and page ordering, group selection/dragging, rotation/removal, image-size/A4/Letter pages and margins |
| Clipboard | Active-by-default local text/image history; configurable Option-Shift-V popup, arrows, Enter/Command-V, persistent Pause, search, pins and native single/multiple-file entries |
| Editor | Drop Markdown directly into editable source/live preview; multiple-file switching, unsaved-edit protection, KaTeX math and paginated PDF export |
| Workflows | Image-only pipelines; autosave, sidebar rename/pin, dropped-image batches, visual crop, compression estimates and a final one-PDF-per-image step |

## Files and results

Conversions and image edits create **new files beside each original**. Repeated names receive a unique suffix. A normal one-folder operation selects its results in Finder. A batch spanning folders saves each result beside its source and displays one summary with Reveal controls. Conversions do not open or populate the shelf.

When required, Macaroni asks you to select the source folder to grant write access and remembers the scoped bookmark. If access is denied, it reports the problem instead of silently using another destination. The older shared Exports folder is not the default output location anymore.

Add files to the shelf by dropping onto Shelf or into the shelf itself. Select files with normal macOS selection gestures, use Command-A when the shelf is focused, and choose Copy or Move before dragging out to Finder. Copy retains sources; the optional Clear after copy setting removes successfully delivered shelf references and closes the shelf when empty. Command-C alone retains references until delivery is confirmed. Move copies and verifies delivery before deleting each source and removing successful shelf entries. Cancelled drops that never request delivery do not remove files. Failed items remain available. The shelf's menu also offers explicit Copy/Move to folder commands and processing actions.

Clipboard collection starts enabled on a fresh installation; an explicit Pause choice persists across restarts. The default popup shortcut is Option-Shift-V; prior Fn settings migrate automatically, while other explicit shortcut choices are retained and can be changed in Settings. Enter commits the highlighted item and returns focus; Command-V commits, dismisses and pastes into the original app, with macOS Accessibility access required for the automatic paste. Escape cancels without changing clipboard contents. File history restores file URLs/bookmarks; copying image pixels remains a distinct image entry. Its local history is not an encrypted password vault. Recording permissions depend on macOS. The shelf uses the file pasteboard; the editor and image tools process locally without an account or network connection.

## Image adjustment details

Crop provides free selection, draggable corners, movement, a thirds grid, pixel dimensions, and ratio presets. A crop batch reviews images individually. Resize starts with the ratio locked; unlocking permits stretching. Its slider scales pixel dimensions, while Compress changes storage size.

Compression size feedback comes from a real background trial encode. JPEG and HEIC use their codecs' quality controls. PNG keeps its dimensions and alpha while simplifying color values; inspect the preview when choosing a stronger reduction. Some inputs may show No reduction. The saved output's actual size is reported after completion.

Custom rotation expands the canvas to retain the image. JPEG fills exposed corners with white; alpha-capable outputs retain transparency. Original source data is preserved by conversion/edit operations. Explicit Move is the operation that relocates originals.

## Testing and review

```sh
Scripts/test.sh
Scripts/smoke.sh
Scripts/package.sh
Scripts/verify-package.sh
```

The smoke and package-verification checks require a logged-in graphical desktop. They use isolated data and a named test pasteboard. `Scripts/review-ui.sh` opens an isolated developer review app with generated samples and leaves its review controls available; Quit review closes it.

The package is `build/Macaroni-macOS.zip`. The app is an ad-hoc signed development build. Public distribution needs Developer ID signing/notarization. No app-sandbox entitlement is enabled in this build. The minimum deployment target compiles as macOS 14; runtime behavior on other OS versions and Intel hardware needs separate checking.

Latest UI testing starts at `../Testing/UI_RETEST_0.5.1.md`. Fifth-pass hands-on testing starts at `../Testing/FIFTH_PASS_RETEST.md`. General regression testing starts at `../Testing/START_HERE.md`, with a quick pass in `QUICK_PASS.md` and broader cases in `FINAL_CHECKLIST.md`, and notes in `FEEDBACK.md` / `REVIEW_LOG.md`. Previous testing folders, results, and version-specific checklists are retained under `Testing/_Archive`. Implementation records remain in `docs/REVIEW_CHANGES_0.4.md`, `docs/VALIDATION_0.4.md`, and the earlier versioned documents.

## Output names and exports

Settings → Output naming customizes operation suffixes and combined-PDF names. Processing preserves base names and adds concise suffixes, such as `_compressed`, `_1600x900` or `_muted`. Same-operation suffixes are not duplicated; collisions get `_2`, `_3`. Conversion never overwrites originals. Shelf delivery retains Finder-style names.

Secondary windows show a destination and export there directly. They initially use the first input’s folder; Change lets you choose a different destination for the batch. PDF windows offer an editable name and close after successful export. The editor saves existing files directly, offers Save As, and opens PDF export options only when requested. Search/Command-F opens its compact search strip.

The image-only Preset drop target opens workflows with the dragged images. Changes save automatically; pinned workflows sort first. Sidebar arrows select and Enter runs; Enter inside a text field completes editing. Crop is relative to each image; locked resize fits bounds. Export to PDF is the final step and produces one PDF per image.

## Boundaries

- Math in Markdown is a supported LaTeX-style subset, not full TeX compilation
- OCR preserves recognized text/paragraphs, not arbitrary document layout or equation/table reconstruction; legacy DOC/PPT and embedded-image extraction are not included
- Office inputs: 100 MB, expanded archive: 300 MB, individual XML entry: 20 MB; PDF: 500 pages
- Still images: at most 120 million source pixels; explicit dimensions up to 16000 pixels per edge within that pixel budget
- Video: first video/audio tracks, at most 30 fps and a 1920-pixel longest edge; no HDR/multiple-track fidelity guarantee
- Regular-file transfers are supported; directory transfers are not included
- Very tall individual Markdown blocks must be split before PDF export

## Source

`Sources/UtilityCore` contains typed actions, processing, layout geometry, persistence and file safety. `Sources/UtilityApp` contains the native interaction, controls, shelf, clipboard and editor. Runtime renderer assets and ZIPFoundation are pinned locally. Original code is MIT licensed; dependency licenses and reference inspiration are listed in `THIRD_PARTY_NOTICES.md`.
