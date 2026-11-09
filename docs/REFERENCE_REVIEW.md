> Historical pre-build planning document. The implemented architecture and current scope are described in ARCHITECTURE.md and FEATURES.md.

# FileFlipper implementation review

Reviewed October 31, 2026. Reference commit: [53df099d75b5](https://github.com/Aimee51819/FileFlipper/commit/53df099d75b50ba5edc71f1e5f806ef31222cc6f), committed October 31, 2026 at 21:41 UTC.

This review supports a new, independent macOS application. It is an implementation reference, not a decision to fork or copy the reference source. The submitted proposal remains the scope authority: [final proposal](</Users/hengzhiwang/Downloads/document (3) (1).pdf>).

## What was checked

A read-only snapshot of the current Mac source, app configuration, and build scripts was downloaded into a temporary review directory. I inspected the interaction path, converter entry points and selected internals, permission/output handling, and packaging. The reference app was not installed, executed, or benchmarked. Findings about behavior below are source observations; limitations involving actual OS interaction still require a prototype test.

The snapshot contains 37 downloaded source/configuration/reference files. The Windows implementation and distribution website are not relevant to our macOS-first build. Source links below are pinned to the reviewed commit.

## How the existing application works

```text
Menu-bar application
  -> drag monitor observes mouse, Shift/Option, drag pasteboard
  -> file classification and action catalog
  -> transparent panel containing a directional action picker
  -> actual macOS drop event
  -> converter action
  -> output path and folder access helpers
  -> result notification
```

| Area | Observed implementation | What to carry into our independent design |
| --- | --- | --- |
| Background application | [main.swift, lines 3–7](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/main.swift#L3-L7) creates NSApplication, attaches its delegate, and selects accessory activation. [Info.plist](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Resources/Info.plist#L29-L34) sets LSUIElement. | A menu-bar utility with no main window at launch. Focused editor/settings panels can open when requested. |
| Drag detection | [DragMonitor.swift, lines 21–98](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/DragMonitor.swift#L21-L98) polls mouse/modifier state and the drag pasteboard at 30 Hz on the common run-loop mode. A new drag and Shift reveal the picker; releasing Shift does not dismiss the revealed picker. | Prototype this mechanism against the installed OS before building the rest of the app. Keep gesture observation separate from file processing. |
| Idle and wake behavior | [DragMonitor.swift, lines 27–56](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/DragMonitor.swift#L27-L56) includes an activity assertion and timer restart; [AppDelegate.swift, lines 48–55](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/AppDelegate.swift#L48-L55) restarts after wake/session notifications. | Include sleep, lock, and long-idle testing. Balance any activity assertion with lifecycle cleanup; measure idle behavior rather than assuming it is free. |
| Floating panel | [PickerController.swift, lines 16–47 and 70–97](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/PickerController.swift#L16-L47) positions a transparent nonactivating NSPanel near the pointer and changes placement around screen boundaries. | Use AppKit for native window placement and drag receiving; host our own presentation inside it. Test the active display, full-screen apps, and nonzero/negative display coordinates. |
| Forgiving selection | [BubbleArcView.swift, lines 31–103](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/BubbleArcView.swift#L31-L103) uses directional selection and a cancellation radius, rather than requiring an exact drop on a small icon. | Preserve a forgiving interaction and clear cancel region. Our menu can show a small set of relevant actions plus saved presets and Add to Shelf. |
| Native drop handling | [BubbleArcView.swift, lines 226–267](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/BubbleArcView.swift#L226-L267) registers file URLs, updates the hovered target during a drag, rereads URLs on drop, and schedules processing after the drag event. | The drop event commits an operation. Avoid creating output files merely because the overlay appeared. Use copy semantics for conversion/staging so the source does not disappear. |
| Hide race protection | [PickerController.swift, lines 54–67](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/PickerController.swift#L54-L67) uses a delayed hide and a generation token; the delegate requests a 0.35-second delay after mouse release. | Model drag-session identity explicitly. A stale hide callback must not close a newly opened picker or interrupt the delivery of the drop. |
| File classification | [Catalog.swift, lines 17–56](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Catalog.swift#L17-L56) uses UTType plus extension special cases and chooses available actions from the first file's category. | Classify every input, calculate applicability over the selection, and expose counts/skips for mixed batches. |
| Action representation | [Catalog.swift, lines 4–14](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Catalog.swift#L4-L14) represents a picker item with display metadata, a main-thread flag, and a synchronous throwing closure returning URLs. | Our action descriptor needs stable IDs, serializable parameters, applicability rules, progress, cancellation, and structured per-input results for workflows. |
| Execution and results | [AppDelegate.swift, lines 66–113](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/AppDelegate.swift#L66-L113) dispatches actions to the main/background queue and reports an overall Result via a small notification. | Keep lightweight feedback, but add a shared job model and a results view for partial failures and retries. |
| Image operations | [ImageConverter.swift](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Converters/ImageConverter.swift) uses ImageIO/CoreGraphics, checks available encoders, applies orientation for pixel transforms, and flattens alpha for opaque output formats. | Use native codecs, preserve orientation deliberately, and make JPEG transparency handling explicit. Start with the proposal's JPEG/PNG/HEIC set. |
| Video compression | [MediaConverter.swift, lines 48–55](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Converters/MediaConverter.swift#L48-L55) compresses with a medium-quality export preset. [Export helper](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Converters/MediaConverter.swift#L205-L225) waits for AVAssetExportSession on a background queue. | This is not a target-megabyte encoder. We need requested-byte budgeting, verified export size/duration, bounded retries, and cancellation. |
| PDF extraction | [PDFConverter.swift, lines 51–82](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Converters/PDFConverter.swift#L51-L82) extracts page text, uses OCR when needed, and passes page strings to a Markdown writer. | PDFKit can cover text-based PDFs first. Do not promise semantic reconstruction of arbitrary layouts. Detect scans and explain unsupported extraction until OCR is included. |
| DOCX extraction | [WordMarkdown.swift](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Converters/WordMarkdown.swift) directly reads the Office package XML, styles, numbering, relationships, paragraphs, and tables. | Use a maintained ZIP library plus our own bounded XML-to-document model. A simplistic attributed-string import should not be assumed to preserve heading/list structure. |
| PPTX extraction | [PresentationConverter.swift, lines 78–120](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Converters/PresentationConverter.swift#L78-L120) builds Markdown by reading slide content, sorting its rendered items, and writing slide sections. | We only need text-to-Markdown, not a new PowerPoint renderer. Read presentation relationships for authoritative slide order and extract titles, text, bullets, and simple tables. |
| Supporting code | [ZipArchive.swift](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Converters/ZipArchive.swift) is a custom ZIP reader; [TextRecognizer.swift](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Converters/TextRecognizer.swift) uses Vision. | Use ZIPFoundation to avoid spending the draft on archive parsing. Vision OCR is a possible extension. |
| Folder permissions | [FolderAccess.swift](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/FolderAccess.swift) persists security-scoped bookmarks, requests write locations, and balances temporary access. [Entitlements](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Resources/FileFlipper.entitlements) enable sandbox and user-selected read/write access. | Plan file grants and persistent references from the beginning, including stale bookmarks. A dragged file is not a blanket write grant for every surrounding folder. |
| Output handling | [Support.swift, lines 32–82](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Support.swift#L32-L82) chooses unused names and rejects compression outputs that are not smaller. | Reserve names atomically for concurrent jobs and commit outputs only after success. Say “no reduction with these settings,” not that further compression is impossible. |
| Packaging | [project.yml](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/project.yml), [build-app.sh](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/scripts/build-app.sh), and [build.yml](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/.github/workflows/build.yml) define a macOS 14 app, an Xcode build, ad-hoc local signing, and CI artifacts. | Build a real .app bundle early. Core tests alone do not prove the distributed app has its assets, permissions, and working gesture. |

## Important differences for our app

1. The reference does not provide our persistent file shelf, clipboard-history service, live editor, or reusable workflow system.
2. Its first-file-based catalog should not determine the behavior of an arbitrary mixed selection.
3. The batch helper catches individual errors but returns successes if any exist. Consequently, the overall result does not retain every failure or unsupported input. See [Catalog.swift, lines 251–265](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Catalog.swift#L251-L265).
4. Converter closures own output naming and execution. Our workflow engine needs explicit inputs, intermediate artifacts, destination policy, and final results.
5. Full PowerPoint-to-PDF rendering, spreadsheets, RAW support, and background removal exist in the reference but are not all required by the submitted proposal.
6. The reference has an optional Microsoft Word automation path for Word-to-PDF. We do not need that integration for DOCX-to-Markdown. See [WordAutomation.swift](https://github.com/Aimee51819/FileFlipper/blob/53df099d75b50ba5edc71f1e5f806ef31222cc6f/Sources/FileFlipper/Converters/WordAutomation.swift).
7. The reviewed Package.swift declares no test target. Our draft should include meaningful tests around the new behaviors.

These are architectural fit observations, not claims that a reference feature fails in normal use.

## Primary references checked for the new work

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation): archive entry access for DOCX/PPTX; resolve and pin the chosen version during repository setup.
- [markdown-it](https://github.com/markdown-it/markdown-it): proposed Markdown renderer; bundle assets locally.
- [KaTeX browser integration](https://katex.org/docs/browser): proposed supported-equation renderer; bundle scripts, CSS, and fonts locally.
- [AVVideoAverageBitRateKey](https://developer.apple.com/documentation/avfoundation/avvideoaveragebitratekey): average video encoding rate in bits per second.
- [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) and [PDF generation](https://developer.apple.com/documentation/webkit/wkwebview/createpdf(configuration:completionhandler:)): native hosting and export facilities.

I also inspected the installed Xcode SDK headers. NSPasteboard.h exposes accessBehavior with a macOS 15.4 availability annotation and documents programmatic-read permission behavior. The actual OS enforcement must be tested; do not promise silent background capture on every supported release. AVAssetExportSession.h explicitly says fileLengthLimit can be exceeded slightly and strict limits require checking actual output. WKWebView.h exposes printOperation(with:) for macOS PDF pagination.

## Local preparation verified

Xcode is installed and selected at /Applications/Xcode.app/Contents/Developer. The local xcodebuild reports Xcode 27.2, build 27B52; the host architecture is arm64. No app compilation or implementation test was performed in this planning task. A macOS 14 deployment target is a proposed compatibility baseline, not evidence that older-system behavior has been tested.
