> Historical pre-build planning document. The implemented architecture and current scope are described in ARCHITECTURE.md and FEATURES.md.

# Draft implementation backlog

Use this with [the architecture plan](INITIAL_PLAN.md). Paths and scripts below describe the future UtilityApp repository; they are not already implemented.

## Ordered work items

| ID | Concrete work | Depends on | Completion check |
| --- | --- | --- | --- |
| T00 | Record final-PDF requirements, supported formats and extension ledger in docs | None | Every proposal row has a real acceptance check |
| T01 | Create app identity, AppDelegate/menu-bar shell, committed Xcode project, UtilityKit package, resources and build/test/package entry points | T00 | Fresh checkout builds a launchable .app with no dashboard opening at startup |
| T02 | Prototype Finder Shift-drag observation, session state, native drop receiving, cancel region, screen placement and delayed hiding | T01 | Real Finder URLs arrive exactly once; cancel changes nothing; normal drag remains intact |
| T03 | Define FileAsset, selection applicability, ActionDescriptor, typed parameters, requests/results and action registry | T01 | Mixed/homogeneous inputs and parameter validation have meaningful tests |
| T04 | Implement job coordinator, output reservations, bookmarks/file grants, temporary artifacts, commit/cancel and per-item results | T03 | Success, partial failure and cancellation preserve correct output ownership |
| T05 | Implement native image convert/compress/resize/rotate/flip actions | T04 | JPEG/PNG/HEIC fixtures pass dimension, orientation, alpha and corruption checks |
| T06 | Connect contextual UI to image actions and focused parameter forms | T02, T05 | Shift-drag a photo, choose an action, inspect a real generated copy and its location |
| T07 | Build ShelfStore, right-edge panel, previews, selection, removal and restoration | T03, T04 | Collect from three folders, hide/reopen, preserve references; removing an entry does not delete its source |
| T08 | Add shelf Copy To/Move To and processing | T05, T07 | Disposable fixtures transfer correctly; conflicts and partial results are explicit |
| T09 | Prove video size targeting with measured export; determine whether a controlled-bitrate path is necessary | T04 | A full-duration fixture meets a cap; impossible targets fail clearly |
| T10 | Finish video UI, progress/cancellation, bounded retries and actual-size reporting | T09 | Real recording processes from drag/shelf; duration, audio, orientation and original are preserved |
| T11 | Build extracted-document model, Markdown writer and text-PDF reader | T04 | Ordered multi-page text output; correct locked/scanned/empty outcomes |
| T12 | Add ZIPFoundation and bounded DOCX/PPTX readers | T11 | DOCX headings/lists and PPTX relationship-based slide order survive; malformed archives fail safely |
| T13 | Build clipboard monitor/store, search, recopy, persistent pins and access-state handling | T01, T04 | Copy A/B/C externally, retrieve A, pin B, relaunch; no self-copy loop |
| T14 | Build source editor, local Markdown/math assets, debounced preview, Open/Save and unsaved-change behavior | T01, T04 | A real Markdown/math sample can be edited, saved and rendered offline |
| T15 | Add paginated PDF export and shelf/document-to-editor handoff | T07, T11, T12, T14 | Export reflects latest edits and includes equations on readable multi-page output |
| T16 | Implement versioned presets/workflows and compatibility validation | T03, T05 | Reject unknown actions, invalid parameters and incompatible step sequences before execution |
| T17 | Add preset creation/edit/save/reload, contextual entries and real execution | T04, T06, T07, T16 | Create convert → resize → compress in UI, relaunch, run on a batch and inspect results |
| T18 | Integrate all panels and services through AppCoordinator; consistent menu/settings/results | T08, T10, T13, T15, T17 | Every final-proposal module is reachable and connected |
| T19 | Complete tests/fixtures, manual gesture checks, offline run, packaging and Quick Start | T18 | Fresh checkout and packaged app pass the entire draft checklist |
| T20 | Final hardening: extra formats/cases, older-OS runtime checks, wake/displays, idle measurement and reviewer distribution | T19 | Compatibility and limitations match actual validation |

T02 and T09 are early technical proofs, not tasks to postpone. Clipboard, editor and document implementation can proceed independently after the shared contracts exist. This dependency map does not start background agents or other chats.

## Checkpoints and calendar

1. **Launchable shell and real conversion:** T00–T06.
2. **Collection workflow:** T07–T08; test staging separately from moving.
3. **Target-size video:** T09–T10; prove actual bytes and complete duration.
4. **Clipboard and document extraction:** T11–T13.
5. **Editing and export:** T14–T15.
6. **Reusable workflows and integration:** T16–T18.
7. **Reviewable draft:** T19.
8. **Final polish:** T20 and explicitly chosen extensions.

If the original class dates still apply, November 1 is the draft checkpoint and November 8 the final checkpoint. The draft should have a narrow working path through every submitted module. Use the final week to improve robustness and compatibility, rather than quietly leave promised modules as placeholder buttons.

Reassess the remaining work after the native gesture and video proofs. These are completion gates, not a guarantee about hours or calendar time.

## Fixture matrix

Create small redistributable examples rather than publishing private user files.

| Fixture | Expected check |
| --- | --- |
| JPEG with an orientation marker | Conversion, resize, rotate and flip produce correct visible orientation/dimensions |
| Portrait HEIC | JPEG output opens with expected orientation |
| Transparent PNG with colored edges | Alpha retained where supported; JPEG flattening is predictable |
| Corrupt image beside valid images | Valid outputs and an explicit individual failure |
| Identical filenames from different folders | Source identity and collision-free output names |
| Short MOV/MP4 with audio and visible start/end markers | Target byte cap, complete ending, audio and decodability |
| Portrait video and audio-free recording | Orientation and missing-audio handling |
| Impossible video target | Useful failure; no truncated output or misleading success |
| Text PDF with several pages and Unicode | Complete ordered text |
| Locked/scanned PDF | Explicit locked/OCR-needed result until those cases are supported |
| DOCX with headings, lists, links and simple table | Bounded structure preserved |
| PPTX with at least 12 slides and nontrivial relationship order | Correct presentation order, rather than lexical filename order |
| Markdown with code, tables, equations and several pages of text | Correct preview and readable PDF pagination |
| Malformed/oversized Office archive | Bounded parsing and explicit failure |

## Draft acceptance checklist

**Interaction**
- [ ] Menu-bar app launches without a main dashboard
- [ ] Shift during a real file drag reveals contextual actions beside the pointer
- [ ] Releasing Shift after activation leaves the current picker available
- [ ] Dropping commits once; cancellation commits nothing
- [ ] Shelf and action drops are mutually exclusive
- [ ] Unmodified Finder dragging still works
- [ ] Repeated drags and display-edge placement work on the development machine

**Modules**
- [ ] Shelf collection, preview, copy, move and processing
- [ ] Image conversion, compression, resize, rotation, flipping and batches
- [ ] Target-size video checked against actual bytes and duration
- [ ] Text PDF, basic DOCX and basic PPTX to Markdown
- [ ] Clipboard view/search/recopy and persistent pins
- [ ] Lightweight editor with live Markdown/math preview and source saving
- [ ] PDF export of the latest content, including a long sample
- [ ] User-created named presets saved/reopened and executed on real files

**Quality and repository**
- [ ] No placeholder success paths in the claimed scope
- [ ] Every input has a success/failed/skipped/canceled result
- [ ] Conversions preserve originals; removing shelf references does not delete sources
- [ ] Renderer scripts, CSS and fonts are bundled
- [ ] No runtime model service or uploads are required
- [ ] No Office, Python, Node or external codec installation is needed to use the packaged draft
- [ ] Build/test scripts, lockfiles and third-party notices are included
- [ ] Tests validate outputs and meaningful failure paths
- [ ] README states supported formats, platform baseline and limitations
- [ ] Fixtures and a five-minute independent review guide are included

## Demonstration and independent review

**Clip A, approximately 15 seconds:** Shift-drag an image, choose a saved preset, and show the final output/shelf result.

**Clip B, approximately 15 seconds:** collect files from different locations and deliver them together, or demonstrate a small recording meeting a size cap. If processing is sped up in a recording, label it.

For the professor's independent review, the Quick Start should cover: launch; photo conversion; multi-folder shelf collection; clipboard recopy/pin; document extraction and quick edit; PDF export; saved workflow; target-size video. Supply small samples so the reviewer need not find their own inputs.

## Development record

At each checkpoint, record:
- Implemented requirements and relevant code changes
- Checks actually run and results
- Where the coding agent helped, where it needed correction, and human design decisions
- Known limitations and next integration work

This supports the course objective without inventing performance claims before a real implementation exists.

## Planned handoff commands

The future repository should provide:

```text
./Scripts/build.sh        # produce a local .app
./Scripts/test.sh         # run the relevant package/integration checks
./Scripts/package.sh      # package tested app and reviewer samples
```

These are planned interfaces, not commands already created or executed. A local draft artifact is the initial deliverable; automatic public-release publishing is not part of setup.
