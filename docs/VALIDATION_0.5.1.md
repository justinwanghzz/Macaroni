# Validation — Utility 0.5.1 / build 11

- 36 native core tests passed, zero failures
- Final release package rebuilt, extracted and passed strict code-signature verification
- Extracted release app passed the isolated native smoke suite, including:
  - Custom search counts, case-insensitive/Unicode matches, next/previous/wrap and no-match handling
  - Search header expands only when opened; editor has no permanent export footer
  - Editor export sheet opens and cancels cleanly; existing paginated PDF export remains valid
  - Selecting videos changes the preview; individual rates persist between selections
  - Real two-video export applies 2× and 0.5× respectively, produces the right filenames and verifies 2-second / 8-second durations from the 4-second fixtures
  - Apply speed to all updates every input
  - Workflow action changes initialize crop/resize settings, move PDF last and reject duplicates
- No computer-use automation performed. Styling, pointer interaction and keyboard feel remain manual checks in Testing/UI_RETEST_0.5.1.md

The full packaged-app report is build/Release-Smoke.json. This is an arm64 local-review build targeting macOS 14+.
