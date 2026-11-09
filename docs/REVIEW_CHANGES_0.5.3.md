# Linked editor navigation — Utility 0.5.3 / build 13

- Moving the source caret, selecting a source/search match or editing text reveals the corresponding preview block and marks it with a subtle outline
- Clicking rendered preview content moves the source caret to the corresponding line/block, scrolls it into view and focuses the source editor for continued editing
- Markdown token line maps cover headings, paragraphs, list items, table rows, code and rendered math; fenced/indented code also maps clicked columns where possible
- Formatting changes how source text appears, so paragraph/math navigation is by source block rather than an exact rendered-character position
- UTF-16 offsets preserve Chinese text, emoji, CRLF and CR line endings; caret positions never split an emoji surrogate pair
- Render generations and source snapshots reject clicks on stale maps while an edit is awaiting rendering
- Plain preview text selection and external links keep their normal behavior; navigation does not rewrite the document
- Preview scrolling occurs when the matching content is outside the visible area; typing within an already visible block does not repeatedly recenter it
- Navigation outlines are excluded from PDF export

This adds caret/edit-follow and preview-click navigation; it does not lock both panes' scrollbars together during arbitrary wheel scrolling.

Validation: 40 core tests passed, including four new source-line mapping tests. Native WebKit smoke checks passed source-to-preview navigation across a long document; preview-to-source heading/table/math/code clicks; selection/focus; mapping after inserted lines; rejection of stale/invalid positions; preservation of text selection and document contents; and clean PDF styling. Existing search, media, workflow and paginated-PDF checks remain in the smoke suite. No computer-use automation was used.
