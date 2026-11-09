> Historical pre-build planning document. The implemented architecture and current scope are described in ARCHITECTURE.md and FEATURES.md.

# Draft repository implementation plan

Prepared October 31, 2026.

## 1. Goal and scope authority

Build a new open-source macOS utility that stays in the background and presents contextual actions beside a dragged file. Its shelf, clipboard, editor, and workflows should feel like parts of the same small utility.

The approved proposal (submitted separately) is the scope authority. Earlier research and brainstorming are supporting material. The plan covers all five module groups in that PDF; narrower draft support is explicit below.

Reference: [FileFlipper review](REFERENCE_REVIEW.md), pinned to commit 53df099d75b5. Use its observable interaction and native platform patterns as design references. Implement our own code, assets, application identity, and architecture. This deliverable is a plan; the application repository has not yet been created.

## 2. Requirements mapped to the proposal

| ID | Requirement | Draft implementation boundary | Completion evidence |
| --- | --- | --- | --- |
| R01 | Background macOS utility | Menu-bar entry; no dashboard opens at launch; focused panels on request | Launch packaged .app and use it from Finder |
| R02 | Shift-drag contextual actions | Detect a real file drag, latch on Shift, show relevant actions near pointer | Live Finder drag invokes one real operation |
| R03 | Persistent temporary shelf | Multiple source folders; previews; explicit Copy To/Move To; collect/process a selection | Gather three files, navigate away, deliver them together |
| R04 | Image conversions | JPEG, PNG, HEIC when supported by runtime encoders | Fixtures convert and reopen with expected dimensions/format |
| R05 | Image transformations | Compress, resize, rotate, horizontal/vertical flip; individual/batch | Orientation, transparency, and output-path checks |
| R06 | Target-size video | Supported MOV/MP4 inputs; explicit byte target; full-duration output; measured size | A fixture meets a target or returns a precise unmet-target result |
| R07 | Document-to-Markdown | Text-based PDF, basic DOCX, and basic PPTX | Each format exports usable ordered Markdown |
| R08 | Clipboard history | Text and images; view/search; recopy a historical item; pin items | Copy A/B/C, retrieve A, restart, verify pin survives |
| R09 | Lightweight editor | Markdown source/preview; supported LaTeX-style equations; quick edits; PDF export | Edit a sample offline; export a readable PDF |
| R10 | Presets/workflows | Save named settings and linear multi-step image workflows | Create, save, relaunch, execute convert → resize → compress |
| R11 | Local processing | No runtime upload or model service; renderer assets bundled | Core demonstrations work with network unavailable |
| R12 | Open-source modular repo | Shared action contract, documented module template, build instructions, tests | Fresh checkout builds and a contributor can locate the extension seam |
| R13 | Clear batch outcomes | Inputs, outputs, skipped/failed status, progress, cancellation, retry | One corrupt input does not hide successful outputs or its own failure |

Clipboard-to-file export, PDF paragraph cleanup, and additional video controls were removed from the final proposal's feature table. They are not required draft UI. Internal normalization/encoding choices remain implementation details.

## 3. Recommended stack and decisions

| Area | Initial decision | Reason |
| --- | --- | --- |
| App | Native Swift, AppKit lifecycle/window/drag handling, SwiftUI for ordinary panels | The signature interaction requires precise native panel and drag behavior |
| OS baseline | Propose macOS 14+; use availability checks | Useful pre-Tahoe support without committing to every old release |
| Build | Committed Xcode app project; local Swift package for core/engines; SwiftPM tests | Real .app resources/entitlements plus independently testable logic |
| Image engine | ImageIO and CoreGraphics | Existing system codecs and pixel operations |
| Video engine | AVFoundation, with a measured export path and a controlled bitrate fallback | A preset label alone cannot prove a maximum byte size |
| Documents | PDFKit; ZIPFoundation + Foundation XML parsing for DOCX/PPTX | Local extraction without Microsoft Office or a Python installation for the user |
| Editor | NSTextView source editor + WKWebView preview | Lightweight source editing with a bundled web renderer |
| Rendering | Pinned markdown-it and KaTeX assets in app resources | Markdown and supported math without a runtime Node process or CDN |
| Persistence | Codable JSON metadata plus separate image/artifact files, atomic updates | Sufficient for bounded draft history, shelf references, and recipes |
| Jobs | Structured asynchronous operations and a shared coordinator; UI state on main actor | Responsive UI, per-file outcomes, cancellation |
| Extensibility | Compile-time module registration and source contributions | Community additions without a runtime plugin marketplace |

Proposed engineering decisions can change after the first prototypes, without dropping any requirement. Pin actual dependency versions and checksums in repository setup. Do not treat current library versions as permanently fixed.

### Build and distribution baseline

- Develop on the available arm64 Mac; Xcode is installed and selected.
- Use a stable bundle identifier owned by this project; keep the display name configurable until chosen.
- Keep app sandbox, file grants, resource bundling, and packaging coherent from the first .app.
- Include user-selected read/write access and app-scoped bookmarks where needed. Add printing capability only as required by PDF export. Do not inherit reference Word automation entitlements.
- Prefer a committed generated Xcode project so normal reviewers do not need XcodeGen. project.yml is the editable definition; regeneration is a developer task.
- Ad-hoc local builds are suitable for local review. A downloaded build on another Mac needs an explicitly tested signing/distribution path; notarization is a later release task unless it becomes necessary for the reviewer.
- Target older releases through deployment settings and API checks, then document which versions were actually exercised. Build-target compatibility is not runtime validation.
- Apple Silicon support is the draft acceptance platform. A universal binary can be built when both architectures and dependencies are checked.

## 4. Interaction specification

### Shift-drag state machine

```text
Idle
 -> native file drag observed
 -> Shift pressed during that drag
 -> classify all inputs and calculate applicable actions
 -> show contextual menu and reveal shelf
 -> hover selects action or shelf target
 -> drop commits exactly one destination
 -> finish native drag
 -> collect references OR request settings and enqueue action
 -> display result; keep shelf contents available
 -> return to Idle
```

Canceled drag, invalid target, and unsupported input paths return cleanly without modifying the source.

Implementation rules:
- Start from AppKit mouse/modifier and drag-pasteboard observation; verify the technique in the packaged app on the actual OS.
- Latch activation for the current drag, so releasing Shift does not close the picker.
- Read actual file URLs at drop time and revalidate them.
- Conversion/staging uses copy-compatible drag semantics. It must not accidentally tell Finder to remove the source.
- Delay disposal of the panel long enough for the drop callback; associate delayed callbacks with a drag-session ID.
- Keep a clear cancel region and support native drag cancellation.
- Constrain the overlay to the active display and avoid covering the entire screen with a drop-catching surface.
- A shelf drop and an action drop must not both execute.
- Maintain ordinary unmodified Finder dragging.
- Show roughly six useful actions plus a shelf target; use a More action when required. Applicable saved presets join this set.
- “Contextual” means file type, action compatibility, and saved preferences. No runtime AI prediction is required.
- If configuration is needed, finish the drag and open a small focused form, then run. Simple saved presets run immediately.
- Sleep/wake and disable/enable must not create duplicate timers or stale sessions.

### Shelf

- Dock at the active display's right edge; content remains available after the drag ends.
- Store references/bookmarks to originals, not duplicate data just for staging.
- Show thumbnail/name/type/source location and missing/unavailable state.
- Allow selection, removal, Reveal in Finder, Copy To, Move To, and applicable processing actions.
- Hide preserves the collection. Clear removes references; it does not delete source files.
- Persist metadata if practical in the draft and restore valid entries after restart.
- Quick operations also expose successful outputs on the shelf/results surface, with their actual locations.
- Use explicit Move To for managed moves. Default drag-out is copy-friendly; do not promise universal drag-out move behavior across every target application.
- Do not start recursively processing folders. Folder-reference staging can be added separately.

### Clipboard and editor access

Use menu-bar items and configurable shortcuts for non-file tasks. History is a compact searchable panel; the editor opens a focused document window only on request. An editor window must be able to accept keyboard input even though the drag picker is nonactivating. No large application dashboard is necessary.

## 5. Shared architecture and contracts

Separate domain logic, processing, state, and presentation.

| Contract | Essential fields/responsibility |
| --- | --- |
| FileAsset | Stable ID, URL/bookmark, detected type, size, display metadata, availability |
| SelectionContext | All dragged/staged inputs and per-action applicability counts |
| ActionDescriptor | Stable ID/version, title/icon, input rule, parameter schema, output-type rule |
| ActionRequest | Selected input IDs, validated parameters, destination policy, job ID |
| ActionResult | Per-input outputs, success/failed/skipped/canceled/unchanged status, warnings, measurements |
| UtilityAction | Asynchronous execution using shared file/output/progress services |
| WorkflowDefinition | Schema version, ID/name, ordered action IDs and parameters, accepted input types |
| JobRecord | State, progress, per-input/per-step results, final artifacts, failure/cancel details |
| ClipboardEntry | ID/type, text or image path, created time, content hash, pin state |
| ShelfEntry | Original reference or generated artifact reference plus display state |

Do not serialize closures or SwiftUI views. Do not hide a file operation inside an action menu's drawing code. A background clipboard service has a lifecycle contract distinct from a one-shot action.

### Execution and output policy

- All entry points call the same action registry and job coordinator: drag menu, shelf, preset execution, and editor export.
- Validate input/parameters/destination before processing.
- Keep heavy decoding, extraction, and encoding off the UI thread; marshal only view state and UI-only APIs onto the main actor.
- Start with one heavy video job and bounded light-file concurrency.
- Produce item-level reports and Retry Failed. A batch with successes and failures is a partial-success job.
- For mixed types, show applicability counts. Apply only to explicitly eligible inputs and report the remainder as skipped; never silently use the first file's category.
- Write intermediates to a job-owned directory and commit finished outputs atomically.
- Reserve collision-free names through one coordinator. File-exists checks alone are not sufficient under concurrent jobs.
- Conversion outputs preserve originals. Any replacement/move is explicit.
- Use a chosen output directory or authorized source directory. If source-adjacent writing is not granted, offer an app-managed export location or a destination picker.
- Scope and release file grants across asynchronous jobs. Refresh stale bookmarks and distinguish cloud placeholders from missing files.
- Cancellation cleans only the job's uncommitted artifacts. Do not promise general filesystem undo.

## 6. Module implementation details

### A. Shelf and file transfers

Build the store and UI separately. The store owns references, order, selection, and restoration. A transfer service owns actual Copy To/Move To operations and collision behavior.

For local moves, avoid overwriting by default. For cross-volume moves, finish and verify the copy before removing the source; cancellation before that point preserves it. Record partial outcomes if removal fails. Test with temporary fixtures, not the user's real working files.

Draft acceptance: stage three files from separate folders, hide/reopen the panel, preview, copy the selection, then test Move To on disposable copies. Removing shelf entries leaves originals intact.

### B. Images

Implement supported-format probing, source properties, orientation-aware decoding, pixel operations, and encoding as reusable stages. Support JPEG/PNG/HEIC when the codec is available. Expose conversion, compression, resize, rotate, and flip through registry actions.

Make transparency behavior explicit for JPEG, preserve expected orientation after rotation, and respect aspect ratio during resizing. Report unsupported animation/multi-frame cases instead of silently discarding frames. Do not call a fixed quality setting “lossless.”

Draft acceptance: convert a portrait HEIC, preserve a transparent PNG when appropriate, flatten alpha predictably for JPEG, verify dimensions after resize/rotation, and process a batch with one deliberately invalid file.

### C. Target-size video

Treat this as an early technical prototype because it differs materially from the reference.

1. Inspect duration, video/audio tracks, orientation, dimensions, and supported export formats.
2. Convert the requested MB value into an explicit byte cap. Specify whether the UI uses decimal MB.
3. First test AVAssetExportSession with a suitable preset and fileLengthLimit. Verify that it produces the complete clip and actually meets the cap on representative fixtures.
4. If that path is unreliable, use AVAssetReader/AVAssetWriter with a controlled video bitrate. Initial estimate:
   video bits/sec = 8 × (target bytes − reserved container bytes) / duration seconds − audio bits/sec.
5. Treat overhead allowance as a heuristic. Reject impossible budgets; do not truncate video or remove audio silently.
6. Preserve orientation and synchronize audio/video timestamps; handle audio-free screen recordings.
7. Measure the finished file and verify duration and decodability.
8. If too large, lower the budget and retry a bounded number of times. Publish “target met” only after the actual file is within the cap.
9. On failure, keep the original, show why, and offer another target. Report unchanged output when existing settings cannot usefully reduce the file.

Do not rely solely on changing the extension or choosing “medium quality.” Avoid introducing an external ffmpeg installation as a hidden prerequisite. If a packaged codec fallback is later considered, make that a separate documented dependency decision.

Draft acceptance: an ordinary MOV/MP4 recording meets a practical target, plays to the end, retains expected audio/orientation, and cancellation leaves the original untouched. An impossibly small target produces a useful error. Complex HDR/DRM/corrupt media may be explicitly unsupported initially.

### D. PDF, DOCX, and PPTX to Markdown

Use a small intermediate document model: document → sections/pages/slides → paragraphs/headings/lists/tables → Markdown writer. Keep readers separate from output formatting.

- PDF: PDFKit extraction in page order with boundaries. Identify locked, empty, or scanned documents. A scan must return an explicit unsupported/OCR-needed result until OCR is included.
- DOCX: read relevant package entries using ZIPFoundation; parse document.xml, styles, numbering, and hyperlinks. Support paragraphs, ordinary headings, lists, and simple tables.
- PPTX: follow presentation.xml and relationships to determine slide order; extract title/body text and basic bullets/tables. Do not sort slide filenames lexically or implement full slide rendering.
- Preserve Unicode, escape Markdown syntax where necessary, and surface warnings for unsupported embedded content.
- Bound archive entry sizes and parsing work. A malformed or huge Office package should return an error rather than exhaust the app.
- Do not require Microsoft Word/PowerPoint or use an LLM for extraction.
- Do not promise an equation-heavy or multi-column PDF becomes semantically perfect Markdown, or claim fixed token savings.

Draft acceptance: a text PDF, a styled DOCX, and a multi-slide PPTX each produce readable output. Include a slide-order fixture with slide numbers beyond nine and a locked/scanned PDF negative case.

### E. Clipboard history

Observe general-pasteboard changes through an isolated service; do not reuse drag-pasteboard monitoring. Record supported text and images, deduplicate content, and maintain a bounded local history with persistent pins.

Provide view/search, recopy an old entry, pin/unpin, and remove/clear/pause controls. When recopying an entry, avoid recapturing it as a new duplicate. The user's next unrelated copy must still be recorded.

Availability-check pasteboard privacy APIs on newer OS versions. If programmatic reads are denied or prompt-controlled, show a clear state and stop repeated reads; respect the system's decision. Do not promise a permission-free history service. Native Spotlight's history is not a dependency.

Skip marked concealed/transient entries where recognizable, and bound stored image size. No clipboard sync/cloud upload is needed.

Draft acceptance: copy A/B/C in another app, search and recopy A, pin B, relaunch, and recover B. Exercise pause, denied access where applicable, and image storage. Confirm no recopy loop.

### F. Lightweight editor and preview

Use NSTextView in a focused panel/window for source editing and WKWebView for a local rendered preview. Support Markdown, fenced code, ordinary tables, and the defined KaTeX equation subset.

- Bundle renderer JS/CSS/fonts in the .app; no CDN or runtime Node requirement.
- Debounce updates so typing remains responsive and stale render responses cannot replace newer content.
- Keep raw untrusted HTML/script execution disabled. Render ordinary code blocks literally.
- Resolve permitted local images relative to the opened document; remote image support is not a draft requirement.
- Provide Open, Save/Save As, unsaved-change handling, and export to PDF.
- Wait for fonts/math rendering before export. Use the WebKit print path for paginated output if createPDF produces one continuous page; test with a multi-page sample.
- Connect imported Markdown and shelf files directly to this editor.

Supported LaTeX-style math is not full .tex compilation. Full document classes, bibliography engines, and arbitrary packages are an explicit later extension.

Draft acceptance: open a Markdown sample with code/table/equations, edit it with visible preview updates, save/reopen, export a PDF, and read it offline.

### G. Presets and workflows

Store named settings and linear workflows as versioned Codable definitions referencing registered action IDs.

- Supply a real preset editor: create/name, add/remove/reorder compatible steps, edit parameters, save.
- Validate each step's input/output compatibility before running.
- Make compatible presets available in the drag menu and shelf.
- Use the shared job coordinator and show the failed step if interrupted.
- Keep intermediate outputs job-owned; publish the intended final outputs, with original inputs preserved.
- Do not silently convert unsupported files or run arbitrary shell commands.
- For an image sequence, avoid unnecessary repeated lossy encoding where practical; a later optimization can combine pixel operations before the final encode.
- Reopen saved presets after relaunch.

Draft acceptance: create a convert-to-JPEG → resize → compress workflow in the UI, save it, relaunch, and run it on a batch from the shelf.

## 7. Proposed repository layout

Working name: UtilityApp. Product naming and icon design can happen after the first working build.

```text
UtilityApp/
  README.md
  LICENSE
  CONTRIBUTING.md
  THIRD_PARTY_NOTICES.md
  .gitignore
  project.yml
  UtilityApp.xcodeproj/                 committed app project
  App/
    EntryPoint.swift
    AppDelegate.swift
    AppCoordinator.swift
    Interaction/
      DragSessionMonitor.swift
      DragSessionState.swift
      ContextPanelController.swift
      ActionDropView.swift
      ScreenPlacement.swift
    Panels/
      ShelfPanel.swift
      ClipboardPanel.swift
      EditorWindowController.swift
      PresetEditor.swift
      ResultsPanel.swift
      SettingsView.swift
  Packages/UtilityKit/
    Package.swift
    Package.resolved
    Sources/
      UtilityCore/                     models, contracts, type rules, workflow validation
      UtilityServices/                 jobs, file grants/output, stores, transfers
      UtilityModules/
        Images/
        Video/
        Documents/
        Clipboard/
        Editor/
        Workflows/
    Tests/
      UtilityCoreTests/
      UtilityServicesTests/
      UtilityModuleTests/
  Resources/
    Info.plist
    UtilityApp.entitlements
    PrivacyInfo.xcprivacy
    Assets.xcassets/
    Renderer/                          locally bundled JS, CSS, fonts, notices
  RendererBuild/                       development-only asset preparation + lockfile
  Fixtures/
    README.md
    Images/
    Video/
    Documents/
    Markdown/
  Scripts/
    build.sh
    test.sh
    package.sh
    prepare-renderer.sh
  docs/
    architecture.md
    reference-notes.md
    compatibility.md
    supported-formats.md
    manual-test-checklist.md
    demo-script.md
    development-log.md
  .github/workflows/
    ci.yml                             build + test + artifact; no automatic public release initially
```

Suggested dependency direction: App → UtilityModules/UtilityServices → UtilityCore. Core does not import SwiftUI. Avoid cycles between the shelf, clipboard, and editor; route cross-module opening through AppCoordinator.

The build should use committed renderer assets and lockfiles. Regenerating them is a development task, not a prerequisite for opening the app.

## 8. Execution order

See [task backlog](INITIAL_BACKLOG.md) for concrete task IDs and acceptance checks.

1. Establish a reproducible .app build, core types, fixture set, and output policy.
2. Prove the signature Finder interaction in a packaged app and one image action.
3. Complete shelf collection/delivery and structured job results.
4. Complete the required image actions and run the video size-target prototype early.
5. Implement clipboard and editor; they can proceed independently once shared stores and panels exist.
6. Complete PDF/DOCX/PPTX extraction and connect output to the editor/shelf.
7. Implement saved presets over the proven actions.
8. Run the end-to-end matrix, fresh-checkout build, offline review, and packaging.

Do not defer the native gesture or video sizing until the end. Both can force architectural changes.

If the original class dates still apply, the November 1 draft should contain a narrow functioning path through every submitted module, with limitations documented. November 2–8 is for format robustness, compatibility checks, interaction polish, and optional extensions. A placeholder button for an unfinished module is not a completed draft feature.

## 9. Meaningful verification

| Layer | Checks |
| --- | --- |
| Core | Type applicability; mixed selections; output naming reservations; workflow input/output validation; persistence schema |
| File services | Collision cases, stale/missing references, copy/move on disposable fixtures, denied destinations, cancellation cleanup |
| Images | Decode output; dimensions; EXIF orientation; alpha-to-JPEG; batch with a corrupt input |
| Video | Byte cap; complete duration; audio/orientation; progress/cancel; impossible target; larger-than-source result |
| Documents | Golden expected content; DOCX styles/lists; PPTX relationship order; Unicode; locked/scanned/corrupt files |
| Clipboard | Search/recopy/pins; self-copy suppression; restart; permissions; bounded images |
| Editor | Markdown/math/code; stale render prevention; save/reopen; paginated PDF; no network requirement |
| Workflow | UI-created preset persists; real execution matches intended order; failed step and per-file status |
| Native interaction | Shift before/after drag; release Shift; cancel; second drag race; disable; wake; display edges; Spaces |
| Distribution | Packaged app has renderer/assets and matching entitlement behavior; clean checkout builds; reviewer can find outputs |

Do not pad coverage with tests that merely assert UI text. Validate outcomes, failure paths, and integration seams.

### Five-minute independent review path

1. Launch app and locate menu-bar controls.
2. Shift-drag a photo into a contextual conversion and inspect its output.
3. Collect several fixtures on the shelf and copy them to a new folder.
4. Recopy an earlier clipboard entry and pin one.
5. Convert a supplied document to Markdown and make a quick edit.
6. Export its preview to PDF.
7. Run a saved workflow and a target-size video example.

A one-page Quick Start and reproducible sample files should make this possible without assistance.

## 10. Explicit extension ledger

Keep these ideas documented without silently adding them to the draft's critical path:

- Image crop, background removal, watermarking, advanced metadata controls, extra formats, RAW/animated-image handling.
- Video trimming, muting, audio extraction, GIFs, aggregate attachment budgets, advanced codec/HDR support.
- Scanned-document OCR, PDF merge/split/reorder/compression, spreadsheet extraction, sophisticated table recovery, source-linked document bundles.
- Clipboard-to-file export, reusable snippets, sequential paste, richer file references, cross-device synchronization.
- Batch renaming, clean ZIP packaging, file templates, favorite destinations beyond a basic recent destination list.
- Watched folders, Downloads intake, automatic processing rules.
- Full LaTeX compiler and multi-file projects; diagram rendering and equation-image export.
- Named/pinned shelves, extra activation gestures, display-specific arrangements.
- Runtime plugins, marketplace, shell-script actions, Windows port, App Store release, and cloud integrations.

Some were only brainstormed; they are not all agreed requirements. The final PDF's five groups remain the draft checklist.

## 11. What constitutes the draft repository

A draft repository is complete when:
- All R01–R13 have a concrete working path at the documented supported scope.
- The main product behavior is accessible without a giant dashboard.
- Build, tests, fixtures, renderer assets, source notices, and Quick Start are included.
- There are no fake conversions, placeholder success states, or hidden user-machine dependencies.
- The sample video target is checked against actual bytes and duration.
- Draft limitations and untested OS versions are plainly recorded.
- The app preserves originals for conversion and handles collection removal correctly.
- Repository creation/publication is a separate implementation step; this planning task creates no remote GitHub repository or public release.
