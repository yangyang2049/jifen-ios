# Temporary Test Artifacts

- Put raw test recordings, full xcresult bundles, exported attachments and diagnostic dumps outside the checkout and its worktrees. Create a batch with `python3 scripts/test_artifacts.py new-run <label> --active` under `~/Library/Developer/jifen-ios-test-artifacts/runs/`. Use explicit screenshot, output and `-resultBundlePath` arguments; reuse an existing DerivedData directory instead of creating one for every command.
- The capture entry points in `scripts/` use managed batches by default. Explicit output overrides remain caller-managed. Store only concise reports, reproducers, fixtures and selected necessary screenshots in the repository. Raw external evidence expires; state that in reports that link to it. Store App Store marketing material and formal release artifacts separately, outside the disposable batches.
- After tests, screenshots or recordings, remove intermediate duplicates once the useful evidence is identified, and finish the batch with `python3 scripts/test_artifacts.py finish <batch-path>`. Add `--failed` for unresolved failures; it pins the evidence with `.keep`. Finish removes `.active` and cleans expired older batches. Never clear another running task's marker. Remove `.keep` only when that evidence has been resolved or explicitly made disposable.
- Retention preserves all batches with activity in the last 14 days, always keeps the latest two, and skips `.active` or `.keep`. Preview with `python3 scripts/test_artifacts.py cleanup`; use `cleanup --apply` for deletion. Automation uses the installed helper under the artifact root's `.maintenance/`, so it survives checkout replacement.
- Automated deletion is limited to recognized batches under that root's `runs/`. Never sweep `.git`, sources, existing documentation, unmarked directories, marketing material, formal releases, signing files, simulator data or another project. Skip live builds and tests. A macOS LaunchAgent runs daily at 04:00 Asia/Shanghai, checks after login, and retries hourly when a daily cleanup is due.

# Action Button Foregrounds

- Solid green Save and Confirm action buttons must use white text. When a local button bypasses shared action components, set its white foreground explicitly; automatic contrast must not turn it black.

# Multiplayer Score Release Gate

- Run `python3 scripts/verify_multi_score_release.py --simulator <iPhone-simulator-UDID>` for every release candidate before store submission or publication, including candidates without multiplayer changes. Use the release candidate checkout and an iPhone simulator.
- Record the candidate version, source revision, and passing result in the release checklist. A failure, skipped case, or missing result blocks submission and publication.
# Test Code Context Discipline

The five test targets hold roughly a third of the repository's Swift (about 57k lines), and most of it is irrelevant to any single change. Treat test code as on-demand reference, not as default reading.

- Do not read test files to understand a module. Read the production sources first; open a test file only when the change touches what that file asserts.
- Before reading anything under `jifenTests/`, `jifenUITests/`, `jifenWatch Watch AppTests/`, `jifenWatch Watch AppUITests/` or `Packages/JifenCore/Tests/`, locate the specific file with a search restricted to that directory and read only the matching region. Do not open whole test targets, do not sample files "for context", and do not read a test file to learn an API that the production source already documents.
- Never bulk-load test fixtures, snapshot data or localization expectation tables. Query the exact case under change.
- Screenshot, walkthrough and visual-audit suites are release tooling, not regression documentation. They are excluded from the default `jifen` scheme's UI test run; run them through the `VisualAudit` scheme or their dedicated `scripts/` entry points. Do not read them while working on app or scoring logic.
- When a change alters a public behaviour that a test asserts, update that assertion in the same commit. Do not rewrite or delete tests to make a build pass unless the user explicitly asks for test reduction.

# Test Suite Layout

- `VisualAudit` scheme: screenshot capture, walkthrough and localization visual audit. `jifenUITests` classes listed in its `SkippedTests` are excluded from the default `jifen` scheme; add new capture-only classes to that list instead of leaving them in the everyday run.
- Unit tests (`jifenTests`, watch unit tests, `JifenCore`) stay in the default scheme; they are the regression net and must keep running on every build.

# Localization Resource Boundaries

The 47 locale folders under `jifen/Resources/*.lproj` and `jifenWatch Watch App/Resources/*.lproj` hold about 175k lines, 93% of it generated from `scripts/localization/catalogs/`. `.ignore` keeps them out of default searches while leaving them fully readable.

- Only `en`, `zh-Hans` and `zh-Hant` are authored by hand. Every other locale is generated; edit the catalog and re-run `localize.py`, never the `.lproj` file directly.
- When a new user-facing string is needed, add the `en` row plus a catalog row for each locale, or the locale silently falls back to English. `python3 scripts/localization/localize.py validate --locale <id> --require-reviewed` reports both stale sources and missing rows.
- `.ignore` excludes non-authored locales, `scripts/localization/catalogs/` and `artifacts/` from default searches. Pass an explicit `path` to search inside them; `read`, `glob` and every build or test command are unaffected.