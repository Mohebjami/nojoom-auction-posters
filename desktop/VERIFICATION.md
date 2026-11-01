# Integration verification — 2026-10-26

- `flutter analyze`: passed.
- Focused Flutter suite (automation integration, workspace tabs, responsive UI,
  backup screen): 10 tests passed.
- `PW_TEST_CHANNEL=chrome npm test` in `desktop/`: 63 tests passed, including
  real Chrome automation against a local fixture website.
- Packaged-helper smoke test: startup, authenticated API, Excel import,
  destination selection, CSV report, workbook sharing, local price validation,
  and shutdown passed. No live site was visited.
- Complete Mac build and `codesign --verify --deep --strict`: passed.
- Web release build: passed.
- Installed app checked through its native UI: all six workspace destinations
  are available, both automation screens load, the workbook picker belongs to
  the main app, and History displays the existing 36 posters.
- Two existing NCA checkpoint files were copied to the installed app's runtime
  without overwriting state or changing the originals. Previous app bundles
  are retained under `build/previous-installed/`.

The full Flutter suite has five baseline failures, reproduced on an unchanged
`git archive HEAD` checkout in `/private/tmp/nojoom-baseline-check`:

- `studio_ui_test.dart` and `widget_test.dart`: the untracked original artwork
  fixture `reference/Group 11.svg` is absent.
- `history_test.dart`: an earlier expected brand/year value differs from the
  current importer output.
- Two `template_export_test.dart` cases fail existing visibility/scroll checks.

Logs are in `build/automation-verification.log`, `build/integration-test.log`,
`build/combined-mac-build.log`, and `build/combined-web-build.log`. The unchanged
baseline log is `/private/tmp/nojoom-baseline-test.log`.

Live photo searches and NCA preview/publishing were not run during this task.
