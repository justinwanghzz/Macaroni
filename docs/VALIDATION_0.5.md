# Automated validation — Utility 0.5.0

November 8, 2026. Native Apple Silicon host; macOS 14 deployment target. No computer-use automation was used.

- Core suite: **36 tests passed**, 0 failures (10.8 seconds).
- Isolated debug app smoke: passed, including direct PDF export/collision handling/window closure, workflow autosave/pin/run/delete, visual crop returning a region without export, shelf adaptive default, editor and clipboard checks.
- Expanded Preset geometry test checks centered/edge anchors, negative display coordinates, source clearance and target separation.
- Video coverage: mute plus 0.25×, 0.5×, 2× and 3×; audio track presence, duration, final video frame and dominant audio frequency. Existing-output protection and cancellation clean-up also pass.
- Video duration regression found during this pass: the export session needed an explicit time range to prevent a short stretched-audio tail. The test now checks this behavior.

## OCR comparison

Same supplied English/Chinese image-only PDF, with Vision warmed before both renderers. The three-page input repeats the scanned page. The old path uses PDFKit thumbnails; the new path draws a bounded Core Graphics bitmap. The after measurement includes constructing/writing the multipage sample and converting it to Markdown; it is not a pure renderer microbenchmark.

| Input | Previous path | New path | Reduction |
| --- | ---: | ---: | ---: |
| 1 scanned page | 0.212 s | 0.176 s | 17% |
| 3 scanned pages | 0.512 s | 0.443 s | 13% |

New single-page raster: 2600 × 1445 pixels. A separate phase sample measured rendering at 0.010 s and Vision recognition at 0.119 s; recognition accounts for most of the measured work.

All English phrases and the Chinese characters 文件转换测试 remain present. A whitespace difference inside the Chinese phrase was observed; OCR output should still be reviewed. Full extracted before/after text and raw timings: `OCR_BENCHMARK_0.5.json`.

These short, warm local measurements do not establish latency for large scans, small type, complex layouts, cold model startup or other machines. Accurate OCR remains a per-page operation; progress now advances per page.

## Manual checks remaining

Follow `../../Testing/FIFTH_PASS_RETEST.md`. Finder dragging, actual hotkey conflicts, sidebar second-click/Return focus, player scrubbing, perceived appearance and multiple real displays have not been claimed as manually verified. The clipboard shortcut remains Option + Shift + V.

## Package verification

The final release ZIP was extracted, passed strict signature verification, and passed the isolated app smoke suite. Results: `../build/Release-Smoke.json`. The bundle reports version 0.5.0 / build 10; the packaged binary is arm64.
