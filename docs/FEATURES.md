# Complete feature reference


This reference describes **Macaroni 0.5.6 / build 16**, organized by input type and module. It distinguishes actions offered in the Shift-drag popup from actions reached through the shelf or editor.

### A. File types at a glance

| Input | Available functions | Where to start |
| --- | --- | --- |
| Still images | JPEG/PNG/HEIC conversion; crop, resize, compress, rotate, flip; PDF creation; image workflows; OCR to Markdown through the shelf | Shift-drag for image tools, PDF and Preset; Shelf → Process selected for OCR |
| Videos | Size-target compression, mute, playback-speed adjustment and preview | Shift-drag |
| PDFs | Text/OCR to Markdown; combine documents; reorder, rotate and remove pages | Shift-drag → Markdown, Adjust PDF or Combine PDFs |
| Word `.docx` | Extract content and basic formatting to Markdown | Shift-drag → Markdown |
| PowerPoint `.pptx` | Extract slide text/tables to Markdown in presentation order | Shift-drag → Markdown |
| Markdown `.md`, `.markdown` | Source editing, live preview, supported math, search, save and PDF export | Shift-drag → Live Editor, or menu-bar menu → Markdown editor |
| UTF-8 `.txt`, `.csv`, `.json`, `.tex` | Save text content as Markdown; open text in the editor through Open | Shift-drag → Markdown, or editor → Open |
| Spreadsheets `.xlsx` and other files | Collect, preview where macOS supports it, copy and move through the shelf; clipboard file references | Shift-drag → Shelf, or copy files in Finder |

A recognized extension is not a promise that every codec or damaged file can be decoded. Spreadsheet conversion, legacy `.doc`/`.ppt` conversion, arbitrary video-format conversion and full LaTeX compilation are not included.

### B. Images: formats, editing and PDF creation

**Inputs:** JPEG/JPG, PNG, HEIC/HEIF and other decodable still-image formats such as single-image TIFF, BMP, WebP and single-frame GIF. Animated and multi-image inputs are rejected by the still-image processing path. Output choices are **JPEG, PNG and HEIC**, subject to the encoders available on the Mac; image editing preserves a supported input format or uses PNG for other decoded input formats.

| Function | Included controls and behavior |
| --- | --- |
| Convert format | Direct JPEG, PNG and HEIC drop targets; one file or a batch; new output files |
| Crop | Visual selection with corner handles, drag-to-move/new selection and pixel-size readout; Free, 1:1, 4:3, 3:2, 16:9 and 9:16 ratios; individual crop review for multiple images |
| Resize | Width and height in pixels; lock/unlock proportions; scale slider; proportional resizing or intentional stretching when unlocked; preview before applying |
| Compress | Smaller–Sharper slider, preview, original/output-size comparison and an actual trial-encode estimate; PNG color reduction retains alpha; reduction depends on the input and is not a guaranteed image byte-size target |
| Rotate | Live preview; clockwise 90°, 180° and 270° tiles; custom angle field/slider; Reset; expanded canvas retains rotated content |
| Flip | Separate immediate **Flip H** and **Flip V** actions |
| Orientation/transparency | EXIF orientation is normalized; alpha-capable outputs retain transparency; JPEG exports use white behind transparent regions or exposed rotation corners |
| Single image → PDF | PDF drop target; preview, rotation and page-size controls; export a new PDF |
| Multiple images → one PDF | Combine to PDF; add files, multi-select, reorder/group-drag, rotate or remove pages; image-sized, US Letter or A4 image pages; adjustable margins for Letter/A4 |
| Image OCR → Markdown | Stage the image on Shelf, open its footer menu → **Process selected → Convert to Markdown**; local printed-text recognition, including English/Chinese; image OCR results open in the editor. This action is deliberately absent from the image Shift-drag popup |
| Reusable processing | Drop images on **Preset** to run a saved, editable sequence; see section G |

The visual crop/resize/compression/rotation windows show the folder and **Change** beside their action buttons. Still-image inputs are limited to 120 megapixels; explicit resize dimensions are limited to 16,000 pixels per edge within that pixel budget.

### C. Videos: compress, mute and change speed

**Primary inputs:** `.mp4`, `.mov`, `.m4v` using codecs macOS can decode. `.avi`, `.mkv` and other movie types may be recognized as videos, but decoding is dependent on AVFoundation; support for those containers is not guaranteed. Outputs are new **MP4** files.

| Function | Included controls and behavior |
| --- | --- |
| Compress to a size target | Source size shown; synchronized percentage slider and maximum-size field in decimal MB; starts at **100%** of the original size |
| Batch compression | Choose a percentage of each video's original size or a common maximum MB per video |
| Measured compression | H.264 video/AAC audio encoding; checks actual bytes and complete duration; retries encoding when needed, or reports an unmet/impossibly small target |
| Mute video | Export a video without its audio track through the Mute video action |
| Adjust speed | **0.25×–3×**, initially 1×; slider and quick-rate buttons; exported duration changes inversely with speed; audio pitch is preserved |
| Preview | Native player with play/pause and a draggable timeline; preview reflects the chosen playback rate |
| Multiple video previews | Preview selector switches between the supplied clips |
| Individual batch rates | Each clip retains its own speed; **Apply this speed to all** optionally copies the selected rate to every clip; the export button states the batch count |
| Destination | Compact folder/Change control on the same line as Compress/Export |

Compression may reduce resolution and frame rate to meet the budget (up to a 1920-pixel longest edge and 30 fps in that encoding path). This is not a professional HDR or multi-track fidelity editor; there are no timeline-cutting, cropping, soundtrack-editing or arbitrary resolution/format menus.

### D. PDFs, Word, PowerPoint and plain text

| Input / function | Included behavior |
| --- | --- |
| Readable PDF → Markdown | Extract text with page headings and page order preserved |
| Scanned PDF → Markdown | Automatically OCR pages without readable text; local recognition for printed English/Chinese; progress advances per page |
| Adjust one PDF | Page thumbnails, selection, reordering, 90° rotation increments and removal; export a separate edited PDF |
| Combine PDFs | Start with whole-document ordering, then switch to **Organize pages** for individual/multiple-page ordering, rotation and removal |
| Interleave PDF pages | Mix pages from different documents; switching views does not silently undo the current interleaved order |
| Mix images and PDFs | Use **Add files** in the shared PDF organizer to assemble images and PDF pages together; existing PDF page content/text is retained |
| PDF export controls | Editable filename; compact destination/Change control; new uniquely named output; organizer closes after successful export |
| Word `.docx` → Markdown | Paragraphs, headings, basic bold/italic, lists, tables and supported links; text extraction rather than a visual replica of the Word layout |
| PowerPoint `.pptx` → Markdown | Slide text, supported bullets and tables; follows the presentation's slide order rather than filename sorting |
| UTF-8 text → Markdown | Retains text content; CSV/JSON are not automatically interpreted as formatted tables or new structured documents; `.tex` is treated as text, not compiled |

PDF processing is limited to 500 pages. Locked/password-protected PDFs are not unlocked by the app. OCR is text recognition, not full layout/table/equation reconstruction. Embedded Office images and complete Office layout fidelity are not promised. **Excel/PowerPoint-to-PDF through LibreOffice is not included**, and no Office application installation is needed for the supported Markdown extraction.

### E. Markdown/math editor

| Function | Included behavior |
| --- | --- |
| Open documents | Drop Markdown onto Live Editor, use the menu-bar editor entry, or Open from the toolbar; multiple opened documents have a file selector |
| Edit and preview | Lightweight plain-text source pane and live rendered preview; headings, emphasis, lists, links, code blocks and tables; supported LaTeX-style inline/display math through the bundled renderer |
| Search | Search button or **Command-F** opens a compact search strip; case-insensitive/Unicode matches, highlights and a match count; previous/next with wrapping; **Command-G / Shift-Command-G** navigate; Escape closes search |
| Linked source/preview navigation | Moving the source caret or editing brings the matching preview block into view; clicking a rendered block scrolls/focuses its source. Supports headings, paragraphs, lists, table rows, code and math; formatted content maps by block/line, with code columns where available. Selecting preview text and clicking links keep their normal behavior |
| Standard editing | Cut, copy, paste, select all and undo/redo |
| Save | Save updates the existing file; **Save As** is in the toolbar's file-actions menu and suggests the current name; unnamed documents suggest Untitled.md |
| Unsaved changes | Save/Discard/Cancel protection when switching documents or closing |
| PDF export | Export PDF opens an attached dialog with filename and destination/Change; paginated PDF output, including long documents; source-based filename or Untitled.pdf for an unnamed document |
| Offline rendering | Renderer/math assets are bundled; raw HTML/script input is displayed safely rather than executed; external links open only when clicked |

The editor supports Markdown with a math subset, not an Overleaf replacement or a general `.tex` compiler. Very tall individual blocks may need to be split for PDF export. There is no search-and-replace feature.

### F. Shelf and clipboard: useful across file types

**File shelf**

- Collect references to files from different folders without moving them just by staging
- Add through the Shelf drop target, drag into the panel or use Add files
- Switch **List / Icons** independently of **Copy / Move**; resize the panel and retain its size/view preference
- Native single/multiple selection, Command-A, Command-C, filenames/sizes, and Space/double-click preview
- Drag files into Finder or use **Copy to folder / Move to folder**; copy preserves originals; move removes sources only after verified delivery
- Optional **Clear after copy** removes successfully delivered references; cancelled/failed deliveries and unselected items remain
- **Process selected** exposes compatible processing actions and saved workflows; with no explicit selection it uses all shelf references, and incompatible inputs may be skipped
- Remove selected references or Clear shelf without deleting source files; an empty shelf hides

Shelf transfer operations support regular files; directory transfer is not an included operation. Preview availability for unfamiliar formats follows macOS.

**Clipboard history**

- Capture and distinguish text, copied image pixels, and single/multiple Finder file references
- Search previous entries, pin frequently used items and restore older content after newer copies
- Default **Option–Shift–V** popup; arrow-key selection; Enter copies/closes; Escape cancels; a per-entry Copy button is also available
- Command-V in the popup can paste once into the original destination, subject to Accessibility permission
- Persistent local history/pins and recording Pause/Resume; capture starts with subsequent clipboard changes rather than importing old contents at launch
- **Clear unpinned** retains pins; **Clear all** removes every entry; unavailable file references are reported
- Ordinary unpinned history is bounded to 100 entries and a storage budget; oversized text/image entries are not captured

Copying an image's pixels and copying its file icon are different clipboard operations; the history supports both. It is not a rich-text-format history or a cloud-synced clipboard.

### G. Image presets and workflows

- Always-visible **Preset** drop target for images; opens with the dropped image batch as inputs
- Create, select, delete, rename and pin workflows; sidebar second-click naming and a name field in the main pane
- Automatic saving, with no separate Save workflow action
- Up/down select in the sidebar; Enter runs there; Enter inside text fields completes editing
- Add steps, change a step's action through its dropdown, reorder steps and remove steps
- Available steps: **Convert image, Compress, Resize, Rotate, Crop, Flip horizontally, Flip vertically, Export to PDF**
- Compression slider and background batch-size estimate through the first compression step
- Width × height fields and proportion lock; locked workflow resizing fits each image inside the chosen bounds
- Clockwise rotation presets/custom angle and visual crop selection; crop returns a step rather than creating an extra export
- Relative crop region applies to every input, including images with different dimensions
- Export to PDF stays last and produces **one PDF per image**; the separate PDF organizer combines a batch into one document
- Run button uses the supplied images and the selected destination; menu-bar Workflows can load images from the shelf

Workflows are image-only in this interface and allow up to 12 steps. Video processing and document-to-Markdown are separate tools.

### H. Settings, results and output naming

| Area | Included controls / behavior |
| --- | --- |
| Drag activation | Shift by default; optional Control–Shift or Option–Shift |
| Clipboard shortcut | Option–Shift–V by default; Control–Shift–V, Option–Command–V, Command–Shift–V or None are available |
| Shelf preferences | Copy/Move default, optional clear-after-copy, persistent view and explicit resize |
| Output naming | Customize operation suffixes, resize/speed/workflow patterns and default combined-PDF names; example preview and Restore defaults |
| Typical names | `Photo.jpg`, `Photo_compressed.jpg`, `Photo_1600x900.jpg`, `Photo_cropped.jpg`, `Photo_rotated.jpg`, `Photo_flipped.jpg`, `Report_edited.pdf`, `Clip_muted.mp4`, `Clip_2x.mp4`, `Photo_Workflow_name.jpg` |
| Collisions | New outputs receive `_2`, `_3`, etc.; repeated operations avoid duplicating the same suffix; processing does not automatically overwrite originals |
| Destinations | Immediate conversions save beside each source; secondary batches start in the first input's folder, with Change available; editor export options appear in its dialog |
| Completion | Progress, cancellation for running jobs, per-file success/failed/skipped/cancelled results, output sizes, Reveal in Finder, and Recent results |
| Global controls | Menu-bar Pause/Resume suspends activation and clipboard recording; Quit exits |


Internal source module names and the existing storage identity remain `UtilityApp`/`UtilityCore` for compatibility. The product and runnable executable are Macaroni.
