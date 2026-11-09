# Review guide

## Two memorable interactions

1. **Prepare a photo without opening an app.** Drag `Fixtures/Large-photo.jpg` from Finder, then hold Shift. Drop on the saved **Images for sharing** workflow. The app converts, resizes, and compresses it; the shelf displays the original/output sizes and Reveal opens its new output. The original stays untouched.
2. **Bring scattered files together.** Shift-drag a file onto **Add to shelf**, then collect another file from a different folder. Preview it in the shelf, use Copy files and paste both into a demo folder with ⌘V, or run an appropriate action on the batch. Unsupported file types are reported instead of silently disappearing.

Record these separately and trim each to roughly 15 seconds. Use the rest of the presentation to explain the friction, the contextual interaction, the modules, and what collaborating with a coding agent accelerated.

## Five-minute hands-on review

- Launch Utility, inspect the tray menu, and open the shelf
- Add a large image and a document; confirm persistent references by closing/reopening the shelf
- Run image tools on the mixed batch; check the skipped document result
- Convert `Brief.docx` to Markdown and inspect the output
- Compress `Color-motion.mp4` to **0.25 MB**; verify the final size and play the whole clip with audio
- Open the Markdown editor; paste/edit `Notes.md`, change the equation, and confirm a live preview
- Export PDF with the Save dialog; try a long Markdown document and inspect page boundaries
- Create/save a new image workflow, reorder steps with the arrow buttons, and run it from the palette
- Optionally enable clipboard history, copy a harmless sample phrase/image, recopy it, pin it, then pause and clear the test entries
- Copy/move only disposable demo files when checking transfer behavior

## Gesture checks before presenting

- Finder list and icon views; Shift pressed after dragging starts
- A drag without Shift behaves normally
- Drop onto the action you intend, with no original deleted
- Drop on shelf; shelf stays open after release
- Cancel/escape a drag; no job should run
- Long filenames, mixed batches, missing files, duplicate output names
- Pointer near screen edges; Retina/external display and fullscreen behavior
- Cancel a longer video job and ensure the next operation can start

These manual checks complement the engine tests; they are not implied by a passing test suite.
