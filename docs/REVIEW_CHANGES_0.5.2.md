# Compact export footers — Utility 0.5.2 / build 12

- Image adjustment windows: destination and Change now share the bottom row with Cancel and Crop/Apply/Compress
- Video compression and speed: destination and Change share the export/action row; default window heights reduced
- Image workflows: destination and Change share the Run workflow row
- PDF organizer: destination and Change share the Export PDF row; editable filename remains a simple separate field, with file/page count moved beside the title
- Removed the full-width shaded destination cards from these windows; folder names stay compact, with the full path on hover
- Errors take extra space only when present
- Markdown editor and its export dialog remain unchanged

Validation uses the existing extracted-package native smoke suite. This is a layout-only change; processing and file-safety behavior are unchanged. Hands-on check: try each footer at a narrow window width with a long folder name; check that Change and the action buttons remain usable.

Packaged release: strict signature verification passed and the isolated smoke suite passed on a fresh-storage rerun. An initial run hit the editor-load assertion; it did not reproduce on rerun. No production editor code was changed in this patch. No new core tests were added for this layout-only change.
