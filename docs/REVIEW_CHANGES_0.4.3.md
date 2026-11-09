# Shelf placement — 0.4.3

The image menu keeps four formats above and six tools below. Shelf now sits in the central gap to the right of the file, centered horizontally between HEIC and PDF. It no longer adds a row above the conversions. Compact menus are unchanged.

```text
     JPEG   PNG   HEIC   PDF

               [file]   Shelf

       Crop   Compress   Resize
       Rotate  Flip H   Flip V
```

Validation: all 10 ReviewTests passed, including placement at screen edges and on a negative-origin display. The isolated native smoke checks passed, and the rendered action palette was inspected. The release ZIP was extracted, its ad hoc signature verified, and its native smoke checks passed.
