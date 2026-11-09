# Draft architecture

## Interaction and execution

`UtilityDelegate` starts an accessory `NSApplication` and owns the menu-bar item and focused utility windows. `DragMonitor` observes mouse drags and polls mouse/modifier/drag-pasteboard state on a common-mode timer. Shift latches an activation for the current drag. A borderless nonactivating panel contains native file-URL drop targets; it is clamped to the active display. After mouse release, delayed dismissal gives the drop callback time to commit. No file operation is performed merely because a palette was shown.

The actual dropped URLs, not only the initially inspected file, enter the runner. `ActionKind` defines acceptance and output type, `ActionStep` holds typed settings, and `WorkflowDefinition` validates ordered steps before execution. The shared model starts a detached asynchronous job so image/XML work does not block the main thread. Per-file results distinguish success, failure, skipped, and cancelled. One foreground batch runs at a time; the UI can cancel it.

Native image operations use ImageIO and CoreGraphics, including EXIF orientation normalization. Video export controls AVAssetReader/Writer bitrate and render size, checks actual bytes and duration, and retries a bounded number of times. Document extraction uses PDFKit and bounded ZIP/XML parsing. DOCX structure and PPTX relationship order are interpreted without invoking Office or a cloud converter.

## Data and file safety

Shelf records store paths and best-effort security-scoped bookmarks. An `AccessLease` balances scoped access over the job lifetime. Outside the app sandbox, ordinary user filesystem permissions still apply. Missing files yield visible errors.

Each conversion uses a disposable job directory and creates a new uniquely named export. A shared lock serializes output-name selection and commit. Copy/move stages a copy inside the chosen destination and checks size plus SHA-256 before commit; only explicit Move removes the original. Intermediate outputs are cleaned on errors/cancellation. No conversion overwrites its input.

Shelf/workflow/clipboard JSON is written atomically under Application Support. Clipboard collection is opt-in each launch, has separate pasteboard state from drag monitoring, ignores oversized entries, bounds unpinned history, and avoids recapturing its own copies. Pinning is persistent. There is no network transport, analytics, or account system.

## Editor

`EditorController` combines a plain `NSTextView` with a local `WKWebView`. Source edits debounce into a bundled markdown-it renderer; HTML input is escaped. KaTeX renders a supported math subset with untrusted commands disabled. The page's content policy excludes network scripts, images, and fonts. External HTTP(S) links open only on a user click.

PDF export clones the rendered blocks into fixed letter-size pages, keeps ordinary blocks together, moves trailing headings with their following content, then renders each page through `WKWebView.pdf`. PDFKit combines the pages. Oversized individual blocks and documents over 500 pages fail clearly instead of being clipped or starting an unbounded print job. This is a quick Markdown exporter, not a full publication typesetting engine.

## Extending the draft

To add a file action, extend `ActionKind` with its title, symbol, accepted/output types; add typed step parameters/validation; implement its engine branch; add a settings control if required; and add a fixture-based test. Enum-driven shelf and contextual menus will include the action automatically. Workflows have a versioned JSON schema and validate type compatibility between steps.

The draft deliberately uses a Swift package rather than a generated Xcode project. The package is editable in Xcode, the core is testable without running the utility, and the build script supplies the macOS application bundle/resources/metadata. CI builds and tests on a macOS runner; it does not publish a release.
