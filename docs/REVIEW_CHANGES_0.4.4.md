# Shelf visual polish — 0.4.4

- Transparent native title bar with a simpler Shelf title and close control
- Compact indigo Copy/Move selector and a quieter Clear after copy control
- Rounded thumbnail cards with filenames, file sizes, subtle borders, and an inset selection highlight
- Softer light/dark backgrounds, consistent spacing, and a file-count footer with a compact actions menu
- File cards and labels use the available width as the shelf resizes; native table insets no longer clip the narrow view

Existing multi-selection, Command-A/C, Quick Look, drag-out Copy/Move, cleanup, and menu actions remain in place. This change does not alter the contextual action palette.

Validation: the isolated native smoke suite passed, including file delivery and copy cleanup. Narrow/wide light-mode and narrow dark-mode content previews were rendered and inspected; viewport-fit assertions passed. Previews are saved in `build/Smoke/shelf-*.png`. No personal files or clipboard contents were used.

The release archive was extracted, its ad hoc signature verified, and its isolated native smoke checks passed.
