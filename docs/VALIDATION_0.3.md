# Validation — 0.3.0

- 21 native XCTest cases passed with no compiler warnings in the final debug test run
- Release build completed; ad-hoc signature verified strictly on the extracted ZIP
- Extracted release app passed the isolated integration suite below
- Desktop checks: rotation presets/custom angle/slider, Command-A field replacement, video MB-to-percentage synchronization, clipboard arrow selection and Enter dismissal, compact result card and dismiss control

## Release integration checks

- activationSettings
- clipboardDefaultAndPersistentPause
- clipboardOlderImageTextDestinationPasteAndEnter
- clipboardTextImageRecopyPin
- copyCleanupOnlyAfterDelivery
- directMarkdownEditor
- explicitCompactShelfAndRadialMenu
- mixedBatch
- nativeFilePromiseMove
- offlineMarkdownMathAndEscaping
- pauseResume
- plannedFileTypeMenus
- sameFolderOutputs
- shelfFileCopy
- videoSizeControlSynchronization
- visualImageControlsAndActualCompressionEstimate

PDF export produced 16 complete pages. Clipboard restoration was tested with both image and text content into an in-process rich-text destination using an isolated named pasteboard. No personal clipboard data was used.

## Remaining manual coverage

Use Testing/RETEST_0.3.md for coordinated Finder Shift-drag, real drag delivery/cancellation, global hotkey conflicts, cross-app Command-V with the installed app's Accessibility permission, different destination applications, multiple monitors and older macOS versions. Cross-app event injection was not exercised by the isolated smoke suite.
