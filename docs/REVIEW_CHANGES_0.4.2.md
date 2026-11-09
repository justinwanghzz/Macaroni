# Fourth-pass menu changes — 0.4.2

The image popup has four format targets in one row: JPEG, PNG, HEIC, and PDF. Image-to-Markdown is omitted from this popup. The six tools remain Crop, Compress, Resize, Rotate, Flip H, and Flip V, arranged below the file in two rows of three.

Shelf is a centered tile above the format row. The reviewer delegated the remaining placement choice; this uses the above-the-whole-menu interpretation of R038. The file's central space remains clear, and the complete layout translates together near screen boundaries.

```text
               Shelf
     JPEG   PNG   HEIC   PDF

               [file]

       Crop   Compress   Resize
       Rotate  Flip H   Flip V
```

PDF, Word, PowerPoint, and text inputs retain their Markdown conversion target. In mixed selections, that target applies only to the document/text files, not to images. Existing OCR processing and workflows remain available; this change is limited to the popup's choices. Compact video and Markdown menus retain their existing layouts.

Validation:

- Native test suite: 31 tests executed, zero failures, two optional Office-conversion tests skipped because their external backend/fixture were not configured
- Layout tests cover screen edges and a negative-origin display; cards stay on screen, separated, and clear of the dragged file
- Isolated native app smoke checks passed, including the exact image menu, Shelf placement, mixed document/image filtering, and existing file-type menus
- Rendered `build/Smoke/action-palette.png` inspected for the intended arrangement
- Release archive extracted, its ad hoc signature verified, and its isolated smoke checks passed

This validation did not exercise a manual drag in the reviewer's active Finder session. Quit and reopen the updated app to load version 0.4.2.
