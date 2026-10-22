# iScoreboard localization pipeline

This directory keeps machine drafts and human review state separate from the
resources shipped in the app. A new locale is not written to `jifen/Resources`
until every ordinary, Info.plist, and plural row has a fresh reviewed source
hash and passes `validate`.

Group copy also keeps the exact reviewed English source snapshot in
`group-copy-20261017.json` (`reviewed_sources`). Both group copy writers reject
source changes before any writes. Review the affected native wording and update
the explicit review data before changing that snapshot; updating catalog hashes
alone does not constitute a translation review. The 2026-10-21 corrections and
deliberately retained native wording are recorded in `group-copy-review-20261021.json`.

## Credentials

Create an Azure Translator F0 resource, then export credentials in the current
shell. Do not create a repository `.env` file.

```sh
export AZURE_TRANSLATOR_KEY='...'
export AZURE_TRANSLATOR_REGION='...'
# Optional for a custom or sovereign endpoint:
export AZURE_TRANSLATOR_ENDPOINT='https://api.cognitive.microsofttranslator.com'
```

## Workflow

Current project policy: the existing provider output is retained only as an
unreviewed draft. Acceptance, corrections, and final wording are produced by
Codex reviewers without calling Azure, Google, `googletrans`, or any other
third-party translation service. The provider commands below are preserved for
catalog provenance and reproducibility, but must not be run for the current
review campaign.

```sh
# Inventory, exact source counts, and the hard Azure character budget.
python3 scripts/localization/localize.py inventory --all

# Resumable Azure pass. Every completed batch is cached and added to the
# current-month usage ledger immediately; projected usage is hard-gated.
python3 scripts/localization/localize.py translate --all --resume

# Credential-free alternative: operate the public Google Translate website in
# local Chrome. Results use the same resumable catalogs and review gates.
npm install --prefix build/localization/browser playwright-core@1.55.1
python3 scripts/localization/localize.py translate-google-web --all --resume

# Optional non-gating sample. Install into a venv under build/, not the repo.
python3 -m venv build/localization/venv
build/localization/venv/bin/pip install -r scripts/localization/requirements-localization.txt
build/localization/venv/bin/python scripts/localization/localize.py sample-google --all

# Emit about 100 rows at a time. Reviews contain only approve/revise decisions.
python3 scripts/localization/localize.py review-packet --locale ja --chunk 0
python3 scripts/localization/localize.py apply-review --locale ja --input path/to/decisions.jsonl

# A locale remains outside the app until both commands succeed.
python3 scripts/localization/localize.py validate --locale ja --require-reviewed
python3 scripts/localization/localize.py promote --locale ja --dry-run
python3 scripts/localization/localize.py promote --locale ja
```

After the priority locales have been reviewed and promoted, run the visual
audit on both a narrow iPhone and iPad. The runner blocks immediately if any
requested locale still contains unreviewed rows or has no promoted `.lproj`:

```sh
scripts/run_localization_visual_audit.sh
```

The generated Markdown report and its screenshots are kept under
`build/localization/visual-audit/`. Japanese, Korean, German, both Spanish and
both Portuguese variants get long-copy coverage. Arabic and Hebrew also emit
frame-coordinate evidence for RTL review; the first pass records issues but
does not automatically mirror custom scoreboard semantics.

French (France/Canada) and Russian also have dedicated visual-audit entry points.
Set `LOCALIZATION_VISUAL_AUDIT_DIR` to preserve earlier screenshots in a separate
directory when running a new audit.

Reviewed `vip_agreement_plain_prefix`, `vip_agreement_link_separator`, and
`vip_agreement_link_middle_separator`, `setup_suffix`, and
`doudizhu_winner_separator` values retain grammatical boundary spaces when saved
and promoted. These fragments are concatenated directly in membership sentences,
setup titles, and winner-name lists. Validation permits one ordinary boundary space for these keys
only; provider drafts and ordinary labels still have padding removed.

Source URLs must remain exact in reviewed translations. The `protected-url`
gate ignores surrounding sentence punctuation and translated brackets, but
blocks changed addresses, missing URLs, or inserted spaces inside a domain.

After a generated packet has been checked line by line, it can itself be passed
to `apply-review`; unchanged rows are approved with source/draft freshness
checks. Apply a small explicit `revise` JSONL afterwards for the rows that need
wording changes.

Review decision rows use one of these forms:

```json
{"table":"Localizable","key":"scoreboard_start","decision":"approve"}
{"table":"Plural","key":"match_count.one","decision":"revise","value":"%d match","issues":["PLURAL_GRAMMAR"]}
```

`catalogs/<locale>.jsonl` is durable review state and is intended for version
control. Azure/Google caches, generated review packets, and reports are written
under `build/localization/` and are disposable. Spanish locales share the Azure
`es` cache but retain separate review catalogs. App naming is fixed by policy:
all new locales use `iScoreboard`; existing Chinese names remain unchanged.

The 2026-10-17 group copy correction is maintained in
`group-copy-20261017.json`: all 47 locales have explicit sentence translations,
shared terminology aliases, and reviewed exceptions for words such as French
`Source` or Dutch `Training`. It also replaces Hindi fallbacks in Bengali,
Punjabi and Odia. The shared `activity_direct_match_count` and `archived_count`
counters include every locale's plural forms and are written to `.stringsdict`
as well as the catalogs. The writer updates only group and shared-counter
resources and catalog rows. The 25 new Traditional Chinese error messages are preserved in
`zh-Hant-overrides.json`.

```sh
python3 scripts/localization/group_copy_20261017.py
python3 scripts/localization/group_copy_20261017.py --check
python3 -m unittest discover -s scripts/localization -p test_group_localization.py
```

English group navigation titles, section headings, buttons and short field labels
follow the app's Title Case convention. Body copy, hints, notifications, status
values and empty states retain sentence case. Native translations are unchanged.
The heading writer covers every runtime alias of each reviewed label; the UI
reference regression also checks dynamic policy, rule and report options.

```sh
python3 scripts/localization/group_heading_case_20261022.py --check
python3 scripts/localization/group_audit_copy_20261020.py --check
```

These group gates include common keys referenced by group views and do not
suppress unrelated failures in full-corpus validation.
See [the dated recheck](../../docs/groups/group-recheck-and-localization-2026-10-17.md)
for per-language results, backend error-code coverage and the existing baseline.

The 2026-10-22 membership localization correction shortens the English
`vip_feature_no_ads` benefit to `Ad-Free`. Its 44 catalog source snapshots were
reviewed against the unchanged native translations, which retain the same
meaning. Membership interface copy is generated from billing-cycle codes;
legacy server `identitySummary` and `numberLabel` strings must not override it.

The 2026-10-22 report-evidence follow-up adds the ten `group_report_*` image,
supplement and receipt-action keys to the same authored pack and exact English
source snapshot. All 44 additional locales have reviewed resource and catalog
rows; existing English and Chinese wording is preserved. Traditional Chinese
overrides retain its reviewed evidence wording when regenerated. The evidence
hint keeps the three-image limit, JPG/PNG formats, 2 MB per image and visibility
limited to the reporter and platform. Backend business-error mapping parity is
an independent gate and is not waived by this copy update.

`bootstrap-plurals` regenerates the checked-in plural resources for the three
existing locales after `plural-keys.json` changes:

```sh
python3 scripts/localization/localize.py bootstrap-plurals
```

## Existing zh-Hant corpus generator

`gen_zh_hant.mjs` remains the source-to-source pipeline for refreshing the
existing Traditional Chinese table. It uses the iOS zh-Hans file as the
structure, Android zh-CN/zh-TW resources as preferred corpus, and OpenCC as the
fallback:

1. tier1: copy the Android Traditional value when the key and Simplified value match;
2. tier2: match a unique Android Simplified value, with identical placeholders;
3. tier3: convert Simplified to Traditional with OpenCC `cn -> tw`.

The shared `zh-Hant-terms.json` glossary and `zh-Hant-overrides.json` remain the
review layer. Platform-specific cast, AirPlay, share, account, Apple, and login
keys require manual overrides rather than Android wording.

`zh-Hant-terms.json` also carries `protectedSpans`: regex fragments the glossary
must never rewrite, applied per span rather than per key, so a protected proper
noun can sit in the same sentence as converted wording. Current entries are
`行動數據` (the glossary's 數據→資料 would produce the wrong 行動資料), other
vendors' document titles inside 《…》 (華為/鴻蒙/Apple/Google), and the
`（如無線投屏…）` enumeration whose job is to name the system switch. Add a span
there instead of duplicating a whole value in `zh-Hant-overrides.json`.

```sh
node scripts/localization/gen_zh_hant.mjs
node scripts/localization/gen_zh_hant.mjs --check
```

The generator defaults to sibling `jifen-android` and `jifenqi-website`
directories; use its `--android-cn`, `--android-tw`, and `--website-root`
arguments when the checkout layout differs.

## Sports voice templates

Production announcements use `LocalizedVoiceAnnouncementBuilder.buildReviewed`.
Its sport/language/phase rules are grounded in the sources listed in
[`sports-voice-score-calls-2026-10-03.md`](../../docs/sports-voice-score-calls-2026-10-03.md).
Catalog `reviewed` status validates resource consistency; it does not certify an
officiating expression. Unverified score calls use `score.numbers` with a pause,
without importing another sport's terminology. The documented three-number
pickleball doubles call retains its server number.

To export reviewed catalogs and actual iOS production messages for the existing
domestic Android, Google Android and HarmonyOS parity tests:

```sh
python3 scripts/localization/sync_reviewed_voice_catalogs.py --fixtures
```

The exporter runs a temporary Swift test and removes it when finished. Android
adapts 0/15/30/40/45 displayed points; HarmonyOS retains step counts. Fixtures test
the public production builders, native calls, numeric fallbacks, names, recurring
deuce and documented sides-exchange cues. Exporting catalogs does not add voice
languages or enable unverified expressions.

Before writing any sibling project, the exporter validates every catalog's
source hash, review state, positional arguments, locale identity and promoted
resource. A failed gate leaves the sibling projects untouched.

`ScoreVoice.strings` is independent of UI translations. The 46 voice locales
come from the UI manifest minus Urdu. iOS 26 enables 42; Gujarati, Malayalam,
Odia and Punjabi require iOS 27. Product support determines entry visibility;
installed voices determine whether playback can start. Regional French, Spanish
and Portuguese variants require their exact voice region.

`voice-phrases.json` contains native sentence frames, sports terms, native
numbered game/set captions and quantity forms. `voice_catalogs/<locale>.json`
records reviewed values and source hashes. This campaign was authored and
reviewed by Codex without external translation providers; it does not represent
a separate native-speaker review. English source sentences serve as semantic
IDs; playback never translates through string replacement. Legacy Chinese call
templates remain for compatibility tests; production uses the evidence matrix
above.

```sh
python3 scripts/localization/localize.py voice validate
python3 scripts/localization/localize.py voice promote --locale fr-CA --dry-run
python3 scripts/localization/localize.py voice promote --locale fr-CA
python3 -m unittest discover -s scripts/localization -p 'test_voice_localization.py'
```

Validation rejects missing/extra catalogs, stale/unreviewed rows, empty values,
missing or changed positional arguments, unsafe printf formats and resources
that differ from the reviewed catalog. Repeating a positional argument is
allowed for native constructions such as Korean tied scores. After changing
a frame, inspect every resulting sentence and quantity/name construction,
update its reviewed value/hash, promote it, then run the voice gate and core/app
tests. The common table contains 194 entries; Chinese tables also contain 76
legacy call templates.

Speech uses `AVSpeechSynthesisVoice.speechVoices()` without a system-default
fallback. No speech asset is bundled and no private Settings URL is used.
Download guidance names Settings → Accessibility → VoiceOver → Speech and
explicitly says VoiceOver need not be enabled. The per-match missing-voice
notification budget uses the existing persisted session ID, in memory only.
