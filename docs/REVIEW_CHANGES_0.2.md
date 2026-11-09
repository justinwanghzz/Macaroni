# Utility 0.2 review changes

Implemented against the user's approval of R001-R015 and the proposed defaults. The original Testing/REVIEW_LOG.md remains unchanged.

| Review | Implementation |
| --- | --- |
| R001 | Explicit Files bubble; compact, resizable, scrolling shelf; empty shelf hides |
| R002 | Separate native bubble panels around an open center; constrained-edge placement; mixed-file support |
| R003 | Same-folder output policy; unique names; Finder selection for one-folder completion; grouped results for multiple folders |
| R004 | Public interaction, folder-access, naming, converter and crop source reread on November 7; independent implementation |
| R005 | Persistent activation settings for Shift, Control-Shift, and Option-Shift; activation during a fresh file drag |
| R006 | Brief clockwise orbit entrance, unconnected bubbles, settling scale, reduced-motion support |
| R007 | Direct format choices above; separate tools below; Files always available on the first page; hover More for overflow |
| R008 | Interactive normalized crop region; corner handles, moving/new selection, thirds grid, preset ratios, pixel readout, per-image batch review |
| R009 | Width and height, ratio lock, scaling slider, intentional stretching; legacy longest-edge workflows retained |
| R010 | Image preview and actual trial-encode size; cancellable/debounced background work; format-preserving PNG color reduction with retained alpha |
| R011 | Shared warm surfaces and pill controls; concise labels; focused video controls; progress/results separated from shelf |
| R012 | Rotation preview, presets and custom angles; expanded canvas; JPEG white fill; horizontal/vertical flip remain immediate actions |
| R013 | On-demand source-folder picker; persisted scoped folder bookmarks; explicit failure/cancellation instead of silent fallback |
| R014 | Shared visual adjustment window for crop, resize, compression and rotation |
| R015 | Native table selection, Command-A, multi-item file promises, Copy/Move selector, verified delivery before removal, persistent shelf dimensions |

## Integration details

New optional step fields keep schema-1 workflows readable. Image actions accept explicit dimensions, a normalized crop, and custom rotation angles. The old longest-edge behavior remains supported. File commits stage across volumes before the final destination move, and promised destinations fail on collision rather than silently returning a differently named file. Move retains the original if delivery fails.

The compact shelf is independent of conversion results. Successful single-folder conversions reveal/select the output and briefly show completion. Mixed-folder batches retain one result summary with Reveal controls. Recent results reopens the latest summary. Pause hides the new windows and disables the drag observer as well as clipboard recording.

Copy/Move file delivery is implemented through native file promises. The provider owns its delivery delegate so it survives the end of the drag. A cancelled drag that never requests delivery never removes a source. Native Finder file-promise behavior and permissions should also be exercised with the supplied disposable test sessions.

The renderer, clipboard storage and video encoder remain local. New image preview work never uploads files. UI review uses a separate temporary application bundle, data directory and named pasteboard.

## Reference review

Read-only public source was fetched from https://github.com/Aimee51819/FileFlipper on November 7, 2026. Reviewed PickerController, BubbleArcView, AppDelegate, Support, FolderAccess, ImageConverter and CropWindow. The reference confirms same-folder output naming and on-demand folder grants. Its inspected completion handler shows a toast/sound; automatic Finder selection is our approved requirement, not an attributed reference behavior. Its arc adapts direction around screen bounds and supports directional hover/cancel. Our two-group menu instead uses separate bubble windows to leave the center free of an intercepting panel. No reference source or artwork was copied.

## Verification

See VALIDATION_0.2.md for the final local test results and the limits of desktop coverage. See Testing/RETEST_0.2.md for the focused hands-on checklist.
