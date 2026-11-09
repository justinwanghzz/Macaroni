# Validation — Utility 0.5.3

- Core XCTest suite: **40 tests, zero failures**, including empty/trailing lines, CRLF/CR, Unicode/emoji boundaries and 500-line source-position round trips
- Real WebKit integration: source caret reveals an off-screen preview section; rendered heading/table/equation/code clicks place the source caret; code click uses browser character geometry; text selection does not trigger a source jump
- Typing a new line refreshes source maps; stale and out-of-range messages are ignored
- Navigation preserves document contents/saved state and excludes outlines from PDF pages
- Existing search, export, PDF/media/file safety and workflow checks also run in the isolated native smoke suite

The release ZIP and the ready-to-submit copy are verified after packaging. Their latest results are included in the corresponding build and submission validation reports. Pointer feel and editing workflow remain hands-on checks using the supplied Linked-preview.md sample.
