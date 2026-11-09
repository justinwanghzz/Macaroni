# Contributing

Open `Package.swift` in Xcode, or use the scripts in the README. Keep new features local by default, preserve original files, report per-file failures, and avoid intercepting a drag unless the user activates the interface.

New file actions belong in UtilityCore; focused interface code belongs in UtilityApp. Add a small redistributable fixture or generate one in tests. Prefer tests of resulting pixels, readable text, media duration/size, and original-file preservation over tests that mirror private implementation details.

Run `Scripts/test.sh`. With a logged-in graphical desktop, run `Scripts/smoke.sh`; it uses a named test pasteboard and isolated app data. `Scripts/package.sh` produces an ad-hoc signed ZIP for local review. Check Finder drag behavior manually before changing the gesture implementation.

Dependency upgrades must update `Vendor/manifest.json`, bundled licenses, and the offline renderer check. Never load arbitrary workflow code or execute shell strings from presets.
