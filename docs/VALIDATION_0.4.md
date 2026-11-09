# Validation — 0.4.0

- 30 native XCTest cases passed with no compiler warnings
- Real LibreOffice XLSX export verified selected worksheets and excluded unselected sheets
- Real PPTX export verified a 12-page PDF in slide order
- English/Chinese image OCR and scanned-PDF fallback passed
- PDF edits preserved selectable text; source files stayed unchanged
- Extracted release app passed the integration checks listed below; strict ad-hoc code-signature validation passed

## Desktop verification

A uniquely named isolated review app captured a real three-file Finder copy. After newer text was copied, its Copy control restored the old file entry; Finder recognized Paste 3 Items and pasted all three into a disposable destination. SHA-256 comparisons confirmed all destination contents matched the originals. An earlier desktop harness run was interrupted and is not counted as verification.

Image/text restoration into a rich-text NSTextView and single/multiple file Enter restoration passed in the native/integration tests. The image-to-Preview desktop attempt was interrupted by Preview's file picker and is not counted as an end-to-end image paste check. The test harness restores its saved prior clipboard when quit.

## Extracted-release integration

- activationSettings
- clipboardDefaultAndPersistentPause
- clipboardOlderImageTextDestinationPasteAndEnter
- clipboardSingleAndMultipleFileReferences
- clipboardTextImageRecopyPin
- copyCleanupOnlyAfterDelivery
- directMarkdownEditor
- explicitCompactShelfAndRadialMenu
- fnShiftVExactChord
- mixedBatch
- nativeFilePromiseMove
- offlineMarkdownMathAndEscaping
- pauseResume
- plannedFileTypeMenus
- sameFolderOutputs
- sharedPDFDocumentAndPageOrdering
- shelfFileCopy
- videoSizeControlSynchronization
- visualImageControlsAndActualCompressionEstimate

## Manual checks remaining

Fn/Globe hardware release behavior, permission-dependent automatic cross-app Command-V, and destination-specific image pasting still need the installed build and the user's keyboard/access permissions. Exact Fn/Shift/V modifier matching is covered by the integration suite; this is not a hardware test. Office-to-PDF needs an installed/selected LibreOffice; test-only converter overrides are not stored in the app. Follow Testing/RETEST_0.4.md.
