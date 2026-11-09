# Second-pass changes — 0.3.0

| Review | Implementation |
| --- | --- |
| R016, R022, R024 | Three aligned image columns; Shelf right on the central file row; compact video/Markdown/document/unknown layouts; explicit mixed-type rows and eligible counts; presets on their own paginated group |
| R017 | Blue conversion/editor cards, amber tools, teal Shelf, purple presets; tinted cards and hover feedback |
| R018 | Borderless rounded material result card, output filenames, size change, Reveal, dismiss control, retained success auto-dismiss |
| R019, R020 | Cached image transform updates directly with the rotation slider; visual 90/180/270 tiles, numeric angle, Reset; JPEG white canvas matches export |
| R021 | Persistent Clear after copy, off by default; remove only confirmed successful references, preserve originals/unselected/failed/cancelled items, hide empty shelf; Command-C alone retains references |
| R023 | Source sizes, synchronized percentage/decimal-MB target, 50% initial target, percentage-per-file/fixed-cap batch modes, fresh inputs each time the panel opens |
| R025 | Markdown gets Live Editor; direct source loading, multiple-file selector, protected unsaved edits, Save/PDF export retained; standard text-edit shortcuts |
| R026 | New installations record future clipboard changes by default, persistent Pause/Resume, global utility Pause temporarily suspends recording |
| R027, R028 | Configurable registered Control-Shift-V hotkey, compact searchable popup, newest entry selected, arrows, Enter commit/dismiss, Escape cancellation, Command-V focus restoration and one-shot destination paste |
| R029 | Image restoration publishes PNG and TIFF without stale text; newest restored entry becomes newest history; capture rejects a clipboard snapshot that changes while reading |

## Verification and limits

Native core checks cover the full image grid, compact/mixed geometry, edge displays, video target arithmetic, image transformations and native media output. Isolated app integration checks exercise older-image/newer-text restoration and the reverse using a rich-text NSTextView destination, Enter dismissal, cancellation, settings compatibility, Markdown loading, delivery-confirmed copy cleanup, video controls and paginated PDF export.

The exact original R029 source/destination applications were not provided. The regression scenarios above passed; this does not establish the original report's root cause. Actual global-hotkey and cross-app Command-V testing must include the installed build's Accessibility permission and the user's destination applications. The app prompts for that access only on an automatic-paste attempt; Enter remains available without automatic-paste access. Test suites use an isolated named clipboard and never read the user's general clipboard.
