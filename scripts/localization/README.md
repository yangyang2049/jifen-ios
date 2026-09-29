# iScoreboard localization pipeline

This directory keeps machine drafts and human review state separate from the
resources shipped in the app. A new locale is not written to `jifen/Resources`
until every ordinary, Info.plist, and plural row has a fresh reviewed source
hash and passes `validate`.

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
`vip_agreement_link_middle_separator` values retain grammatical boundary spaces
when saved and promoted. These three fragments are concatenated directly in the
membership page. Validation permits one ordinary boundary space for these keys
only; provider drafts and ordinary labels still have padding removed.

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
