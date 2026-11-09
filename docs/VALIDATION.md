# Draft validation — October 31, 2026

Validated locally on Apple Silicon, macOS 27.2, with Xcode 27.2. The package declares macOS 14 as its minimum; that deployment target compiles, but runtime behavior on macOS 14/15 and Intel hardware has not been checked.

## Passed

`Scripts/test.sh`: **10 XCTest cases, zero failures**.

- Multi-step image conversion/resize/compression and source-byte preservation
- Rotation dimensions, horizontal-flip pixels, EXIF orientation normalization
- Actual HEIC encoding and HEIC → JPEG conversion on this machine
- Unique copy/move destinations, content preservation, source removal only for Move
- Workflow parameter/type validation and Codable round-trip
- Word basic formatting/Unicode extraction; presentation relationship order
- Malformed XML rejection; scanned-image PDF rejection with a supported-feature explanation
- Cancellation preserves image input; mid-encode video cancellation cleans the output
- Impossibly small video target rejects clearly
- Actual ≤250,000-byte video export: complete ~4-second duration, audio track, decodable first and late frames

`Scripts/smoke.sh`: **passed** using an isolated application-support directory and named test pasteboard.

- Native shelf, clipboard, workflow and editor windows instantiated
- Shelf persistence, copying multiple file references to the native pasteboard, and mixed-batch success/skipped reporting
- Text and image clipboard capture/recopy; pinned entry persisted
- Offline Markdown + KaTeX rendering and literal HTML escaping
- Native WebKit snapshot inspected: heading, formatted text, fraction equation, and escaped script text visible
- **16-page** export of an 80-section Markdown document; first page contains the beginning, final page contains Section 80, and the last section does not appear on the first page

The engine and integration tests use generated sample data. The user's general clipboard is not recorded during integration testing.

The final release ZIP was also extracted outside the build directory, its strict code signature verified, and the same isolated integration check passed from the extracted app.

## Manual checks still required

The desktop automation connection could not reliably inspect the background menu-bar app; desktop capture returned a blank image. Therefore a real Finder Shift-drag/drop interaction has **not** been verified end to end by automation. Check the walkthrough's gesture checklist before presenting.

Also unverified: external/multiple displays, fullscreen apps, VoiceOver, macOS 14/15 pasteboard permissions, Intel execution, very large or unusual Office/video inputs, and public notarized distribution. GitHub Actions is configured but has not run remotely.

## Packaging

The local build is ad-hoc signed for development. Packaging stages outside iCloud, strips generated Finder metadata, signs, verifies, and creates a ZIP without extended attributes. This avoids iCloud's file-provider metadata invalidating strict signature checks on the generated application folder. A public release requires Developer ID signing and notarization.
