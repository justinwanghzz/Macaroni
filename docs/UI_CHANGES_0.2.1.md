# UI update — 0.2.1

- Replaced scattered circular targets with aligned rounded cards: formats above, shelf on the left, editing tools below
- Targets stay stationary during their short fade; overflow preserves the original activation anchor
- Screen-edge corrections move the whole palette together and keep the dragged file clear
- Updated shared accents to muted indigo/teal with a neutral surface; shelf and image adjustment behavior remain intact
- Removed the default Images for sharing workflow, including unchanged saved copies; edited and custom presets are retained

Validation: 17 native tests passed, including aligned rows, repeatable coordinates, coherent translation, source clearance, corners, and negative-coordinate displays. Full live Finder drag interaction remains a manual retest.
