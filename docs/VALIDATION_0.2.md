# Utility 0.2 validation

November 7, 2026. Local host: Apple Silicon, macOS 27.2, Xcode 27.2. Deployment target: macOS 14. Tests use generated/disposable data.

## Automated checks

The full suite contains 16 XCTest cases covering the existing converters and the new image/layout/transfer behavior:

- Legacy schema-1 workflow decoding and longest-edge behavior
- Explicit resize dimensions, intentional stretching and proportional batch fitting
- Crop output dimensions, crop bounds validation and arbitrary-angle expanded canvases
- Image rotation/flip pixels, EXIF orientation, actual HEIC encoding/decoding, original-file preservation
- PNG compression changes encoded storage while preserving alpha and dimensions
- Radial target count, separation, source-point clearance and screen containment, including corners and a display with negative coordinates
- Collision-free output naming, extensionless files and source preservation
- Exact promised destination collisions fail without deleting the original; successful promised Move verifies content
- Word/PowerPoint ordering, Unicode, malformed input and scanned-PDF rejection
- Video size, duration, audio, decoded first/late frames and cancellation cleanup

The native smoke check uses a temporary app-data folder and a named test pasteboard. It verifies:

- Radial menu creation does not open the shelf
- Activation settings match and persist
- Pause/Resume disables observation, clipboard recording and activity presentation
- Shelf reference copying, clipboard text/image recopy and persistent pins
- Mixed-batch success/skipped reporting and outputs beside the source
- Resize field synchronization/unlock/slider behavior and crop ratio results
- Compression's displayed trial-encode byte count equals a separately generated output
- Native file-promise Move delivery
- Offline Markdown/math preview and HTML escaping
- Complete 16-page PDF export, including the final section on the final page

Packaging stages outside iCloud before signing. The extracted release application is signature-checked and runs the same smoke check independently of the build folder. Test logs and the release smoke JSON remain under the ignored local build artifacts.

## Desktop checks performed

An isolated review app with a distinct bundle ID was exercised through the native desktop automation tools:

- Crop 1:1 preset updated to 1200 × 1200; corner drag retained the square ratio and updated to 995 × 995; Crop created a new output with completion feedback
- Resize width 300 updated locked height to 200; unlocking permitted height 100 while width remained 300
- Compression's native slider changed from 70 to about 60, with size changing from 691 KB to 484 KB on the generated sample
- Rotation 90° preset updated the angle and slider; custom entry 45° updated both
- Compact shelf displayed one column of thumbnails; explicit opening focused the table; Command-A selected both entries; removing the references hid the empty shelf
- Settings displayed the supported triggers and accepted Control + Shift
- Command-W closed the focused adjustment window
- A normal conversion opened the source folder in Finder and selected the newly saved PNG, while the original JPEG remained present
- Crop, resize and compression windows were visually inspected for layout, clipping and the warm/orange control styling

The review app and its temporary Finder window were closed afterward. The user's general clipboard and saved Utility data were not used for these checks.

## Coverage limits

The actual coordinated Finder Shift-drag/drop gesture and multi-file promise drag-out have not been fully automated end to end. Layout, native drag receivers and actual promise delivery are checked separately; the focused retest checklist includes the complete desktop gestures. On-demand folder permission denial/reauthorization, external volumes, multiple physical displays, full-screen spaces, alternate keyboards, VoiceOver, Intel execution and older macOS runtimes still need environment-specific testing. No public notarization or remote CI run is claimed.
