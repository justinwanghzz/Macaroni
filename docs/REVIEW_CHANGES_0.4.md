# Third-pass changes — 0.4.0

| Review | Change |
| --- | --- |
| R030 | PDF target for one image and Combine to PDF for multiple images. Shared organizer supports native group selection/reordering, rotation, removal, image-sized/Letter/A4 pages and margins |
| R031 | On-device Vision image OCR to Markdown; scanned PDF pages use OCR when no text layer is readable; image OCR results open in the existing live editor |
| R032 | Combine PDFs starts with whole-document order; Organize pages supports per-page/group reorder, rotation and removal; interleaved pages are not silently regrouped |
| R033 | Adjust PDF opens the same organizer for a single PDF; existing PDF page content/text is retained, and export requires a new source-preserving filename |
| R034 | Local LibreOffice backend for XLSX/PPTX, worksheet selection, optional fit-to-width, PDF preview and save. Installed converter is detected or selected; no development runtime is hard-coded |
| R035 | Fn-Shift-V default with exact Fn/Shift/V filtering, autorepeat suppression and modifier/key release handling; existing explicit alternatives retained; keyboard access setup exposed in Settings |
| R036 | Distinct text/image/file entry types, native multiple file URL restoration and bookmarks, missing-file validation, PNG/TIFF pixel restoration, faster capture and nonactivating clipboard popup |

## Reference audit

Read FileFlipper's public TextRecognizer.swift on November 7/8, 2026: it uses accurate local Vision recognition, language correction/detection and scanned-page rendering. Our OCR/paragraph handling is implemented independently. No reference code was copied into the product. Source: https://github.com/Aimee51819/FileFlipper/blob/main/Sources/FileFlipper/Converters/TextRecognizer.swift

## Defaults

Image PDF pages fit each image unless Letter/A4 is selected. PDF adjustment creates a separate output. OCR targets printed English/Chinese and reports no-readable-text results. Office PDF requires LibreOffice; legacy XLS/PPT support is not advertised. Fn keyboard hardware behavior and cross-app paste access remain subject to the installed app's macOS permissions.
