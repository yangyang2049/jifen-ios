#!/usr/bin/env python3
"""Resumable App localization pipeline for iScoreboard.

The script deliberately separates machine drafts from resources bundled by Xcode.
New locales live in scripts/localization/catalogs until every entry is reviewed and
`promote` is run. Provider output is only a draft; a Codex review decision is the
authority for every value that can be promoted. External providers are retained as
legacy ingestion tools and are disabled by project policy during the current review.

Python 3.9 compatible; the Azure path uses only the standard library.
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import html
import inspect
import json
import os
import random
import re
import subprocess
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import uuid
import plistlib
from datetime import datetime, timezone
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
RESOURCE_ROOT = REPO_ROOT / "jifen" / "Resources"
CATALOG_ROOT = SCRIPT_DIR / "catalogs"
BUILD_ROOT = REPO_ROOT / "build" / "localization"
LOCALE_MANIFEST = SCRIPT_DIR / "locales.json"
PROTECTED_TERMS = SCRIPT_DIR / "protected-terms.json"
PLURAL_MANIFEST = SCRIPT_DIR / "plural-keys.json"
PROJECT_FILE = REPO_ROOT / "jifen.xcodeproj" / "project.pbxproj"
AZURE_USAGE_LEDGER = BUILD_ROOT / "azure-usage.jsonl"
GOOGLE_WEB_HELPER = SCRIPT_DIR / "google_translate_web.mjs"

SOURCE_LOCALIZABLE = RESOURCE_ROOT / "en.lproj" / "Localizable.strings"
SOURCE_INFO_PLIST = RESOURCE_ROOT / "en.lproj" / "InfoPlist.strings"
ZH_HANS_LOCALIZABLE = RESOURCE_ROOT / "zh-Hans.lproj" / "Localizable.strings"

ENTRY_RE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')
FORMAT_RE = re.compile(
    r"%(?:%|(?:(?P<position>\d+)\$)?[-+0 #']*(?:\d+|\*)?(?:\.\d+)?"
    r"(?:hh|h|ll|l|L|z|t|j)?(?P<type>[@dDuUxXoOfFeEgGcCsSpaAi]))"
)
URL_RE = re.compile(r"(?:https?://|mailto:)[^\s<>]+", re.IGNORECASE)
URL_LITERAL_RE = re.compile(r"(?:https?://|mailto:)[^\s<>()\[\]{}（）「」『』《》〈〉«»\"'“”‘’、，。；：！？،؛؟]+", re.IGNORECASE)
SECTION_RE = re.compile(r"^\s*/\*\s*(.*?)\s*\*/\s*$")
BIDI_CONTROLS = set("\u061c\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069")
REVIEW_STATES = {"reviewed", "fixed"}
# These reviewed fragments are concatenated directly into a sentence or title.
# Their boundary spaces are grammatical, not provider padding.
SENTENCE_FRAGMENT_KEYS = {
    "vip_agreement_plain_prefix",
    "vip_agreement_link_separator",
    "vip_agreement_link_middle_separator",
    "setup_suffix",
    "doudizhu_winner_separator",
}
# Web translation providers return several candidates separated by " | " when they are
# unsure. The separator survives into the draft (measured on 1,306 Odia rows, including
# Latin fragments spliced mid-sentence), and no shipped English key contains a pipe, so a
# pipe in any translation is treated as machine residue rather than authored typography.
PIPE_ARTIFACT = "|"
# Machine drafts also lose the space after sentence punctuation ("gemaakt.Doorgaan"), which
# renders as one glued word on the scoreboard. Single-letter abbreviations (t.ex, n.b),
# numbered Romance ordinals (1.º) and web addresses are legitimate, so they are cut first.
GLUE_SKIP_RE = re.compile(r"(?:https?://|www\.)\S+|\b[\w-]{2,6}\.(?:com|net|org|io|app|co)\b", re.IGNORECASE)
GLUE_ORDINALS = "ºª°"


def punctuation_glue(value: str) -> List[str]:
    """Return the sentence-punctuation sites that are missing their trailing space."""
    stripped = GLUE_SKIP_RE.sub(" ", value)
    sites: List[str] = []
    for match in re.finditer(r"[.;:!?](?=[^\W\d_])", stripped):
        index = match.start()
        previous = stripped[index - 1] if index else ""
        following = stripped[index + 1]
        before = stripped[index - 2] if index >= 2 else ""
        if following in GLUE_ORDINALS or previous.isdigit():
            continue
        # An abbreviation such as "t.ex" or "n.b" has exactly one letter before the mark.
        if previous.isalpha() and not (before.isalpha() and before != " "):
            continue
        sites.append(stripped[max(0, index - 14):index + 15])
    return sites


@dataclass(frozen=True)
class Entry:
    table: str
    key: str
    value: str
    section: str
    order: int

    @property
    def identity(self) -> Tuple[str, str]:
        return (self.table, self.key)

    @property
    def source_hash(self) -> str:
        payload = "%s\0%s\0%s" % (self.table, self.key, self.value)
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def decode_apple_string(value: str) -> str:
    def replace(match: re.Match[str]) -> str:
        token = match.group(1)
        if token == "n":
            return "\n"
        if token == "t":
            return "\t"
        if token in ('"', "'", "\\"):
            return token
        if token.startswith("u"):
            return chr(int(token[1:], 16))
        return token

    return re.sub(r"\\(n|t|\\|\"|'|u[0-9a-fA-F]{4})", replace, value)


def encode_apple_string(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )


def parse_strings(path: Path, table: str) -> List[Entry]:
    if not path.exists():
        raise FileNotFoundError(path)
    entries: List[Entry] = []
    seen: Dict[str, int] = {}
    section = "Unsectioned"
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        section_match = SECTION_RE.match(raw)
        if section_match:
            section = section_match.group(1).strip() or section
        match = ENTRY_RE.match(raw)
        if not match:
            continue
        key = decode_apple_string(match.group(1))
        if key in seen:
            raise ValueError("duplicate key %s in %s:%d (first at %d)" % (key, path, line_number, seen[key]))
        seen[key] = line_number
        entries.append(
            Entry(
                table=table,
                key=key,
                value=decode_apple_string(match.group(2)),
                section=section,
                order=len(entries),
            )
        )
    return entries


def base_source_entries() -> List[Entry]:
    return parse_strings(SOURCE_LOCALIZABLE, "Localizable") + parse_strings(SOURCE_INFO_PLIST, "InfoPlist")


def plural_manifest() -> Dict[str, Any]:
    payload = read_json(PLURAL_MANIFEST)
    keys = payload.get("keys", [])
    identifiers = [item["key"] for item in keys]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("plural-keys.json contains duplicate keys")
    source_keys = {entry.key for entry in parse_strings(SOURCE_LOCALIZABLE, "Localizable")}
    missing = sorted(set(identifiers) - source_keys)
    if missing:
        raise ValueError("plural keys are missing from English Localizable.strings: %s" % missing)
    return payload


def plural_entries(locale: str) -> List[Entry]:
    spec = locale_map()[locale]
    categories = spec["plural_categories"]
    rows: List[Entry] = []
    for item in plural_manifest()["keys"]:
        for category in categories:
            source_value = item["one"] if category == "one" else item["other"]
            rows.append(Entry(
                table="Plural",
                key="%s.%s" % (item["key"], category),
                value=source_value,
                section="Plurals",
                order=len(rows),
            ))
    return rows


def source_entries(locale: Optional[str] = None) -> List[Entry]:
    entries = base_source_entries()
    return entries + (plural_entries(locale) if locale else [])


def source_by_identity(locale: Optional[str] = None) -> Dict[Tuple[str, str], Entry]:
    return {entry.identity: entry for entry in source_entries(locale)}


def zh_hans_values() -> Dict[Tuple[str, str], str]:
    values = {
        entry.identity: entry.value
        for entry in parse_strings(ZH_HANS_LOCALIZABLE, "Localizable")
    }
    info_path = RESOURCE_ROOT / "zh-Hans.lproj" / "InfoPlist.strings"
    values.update({entry.identity: entry.value for entry in parse_strings(info_path, "InfoPlist")})
    return values


def manifest() -> Dict[str, Any]:
    payload = read_json(LOCALE_MANIFEST)
    locales = payload.get("locales", [])
    identifiers = [item["ios"] for item in locales]
    if len(locales) != 47 or len(set(identifiers)) != 47:
        raise ValueError("locales.json must contain 47 unique iOS localizations")
    if len([item for item in locales if not item.get("existing")]) != 44:
        raise ValueError("locales.json must contain exactly 44 new localizations")
    return payload


def locale_map() -> Dict[str, Dict[str, Any]]:
    return {item["ios"]: item for item in manifest()["locales"]}


def protected_config() -> Dict[str, Any]:
    return read_json(PROTECTED_TERMS)


def catalog_path(locale: str) -> Path:
    return CATALOG_ROOT / (locale + ".jsonl")


def load_catalog(locale: str) -> Dict[Tuple[str, str], Dict[str, Any]]:
    path = catalog_path(locale)
    if not path.exists():
        return {}
    result: Dict[Tuple[str, str], Dict[str, Any]] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip():
            continue
        row = json.loads(raw)
        identity = (row["table"], row["key"])
        if identity in result:
            raise ValueError("duplicate catalog row %s/%s in %s:%d" % (identity[0], identity[1], path, number))
        result[identity] = row
    return result


def write_catalog(locale: str, catalog: Dict[Tuple[str, str], Dict[str, Any]]) -> None:
    ordered_source = source_entries(locale)
    rows = []
    for entry in ordered_source:
        row = catalog.get(entry.identity)
        if row is not None:
            for field in ("azure", "google_web", "google", "final"):
                if isinstance(row.get(field), str):
                    if field == "final" and entry.table == "Localizable" and entry.key in SENTENCE_FRAGMENT_KEYS:
                        row[field] = unicodedata.normalize("NFC", row[field])
                    else:
                        row[field] = normalize_translation_text(row[field])
            rows.append(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
    extras = sorted(set(catalog) - {entry.identity for entry in ordered_source})
    if extras:
        raise ValueError("catalog contains unknown entries: %s" % extras[:5])
    atomic_write(catalog_path(locale), "\n".join(rows) + "\n")


def choose_locales(args: argparse.Namespace, include_existing: bool = False) -> List[Dict[str, Any]]:
    specs = locale_map()
    if getattr(args, "all", False):
        chosen = list(specs.values())
        if not include_existing:
            chosen = [item for item in chosen if not item.get("existing")]
    else:
        requested = getattr(args, "locale", None) or []
        missing = [locale for locale in requested if locale not in specs]
        if missing:
            raise ValueError("unknown locale(s): %s" % ", ".join(missing))
        chosen = [specs[locale] for locale in requested]
    return sorted(chosen, key=lambda item: (item.get("wave", 99), item.get("order", 99), item["ios"]))


def format_arguments(value: str) -> Tuple[Dict[int, str], bool]:
    arguments: Dict[int, str] = {}
    sequential = 1
    saw_positional = False
    saw_unpositioned = False
    for match in FORMAT_RE.finditer(value):
        token = match.group(0)
        if token == "%%":
            continue
        position_text = match.group("position")
        if position_text:
            position = int(position_text)
            saw_positional = True
        else:
            position = sequential
            sequential += 1
            saw_unpositioned = True
        kind = match.group("type") or ""
        normalized = "object" if kind == "@" else ("integer" if kind in "dDuUxXoOi" else "float")
        if position in arguments and arguments[position] != normalized:
            return ({-1: "conflicting"}, True)
        arguments[position] = normalized
    return arguments, saw_positional and saw_unpositioned


def url_literals(value: str) -> List[str]:
    # Sentence punctuation and translated brackets are not part of the URL.
    return sorted(match.group(0).rstrip(".,;:!?") for match in URL_LITERAL_RE.finditer(value))


def protected_spans(value: str, literal_terms: Sequence[str]) -> Tuple[str, Dict[str, str]]:
    candidates: List[Tuple[int, int, str]] = []
    for match in FORMAT_RE.finditer(value):
        candidates.append((match.start(), match.end(), match.group(0)))
    for match in URL_RE.finditer(value):
        candidates.append((match.start(), match.end(), match.group(0)))
    for term in sorted(literal_terms, key=len, reverse=True):
        for match in re.finditer(re.escape(term), value):
            candidates.append((match.start(), match.end(), match.group(0)))
    for match in re.finditer(r"\n|\t", value):
        candidates.append((match.start(), match.end(), match.group(0)))

    selected: List[Tuple[int, int, str]] = []
    for candidate in sorted(candidates, key=lambda item: (item[0], -(item[1] - item[0]))):
        if any(candidate[0] < end and candidate[1] > start for start, end, _ in selected):
            continue
        selected.append(candidate)
    selected.sort()

    output: List[str] = []
    mapping: Dict[str, str] = {}
    cursor = 0
    for index, (start, end, original) in enumerate(selected):
        output.append(html.escape(value[cursor:start]))
        marker = "__JF_PH_%04d__" % index
        mapping[marker] = original
        output.append('<span translate="no">%s</span>' % marker)
        cursor = end
    output.append(html.escape(value[cursor:]))
    return "".join(output), mapping


def restore_protected(value: str, mapping: Dict[str, str]) -> str:
    cleaned = re.sub(r"</?span(?:\s+[^>]*)?>", "", value, flags=re.IGNORECASE)
    cleaned = html.unescape(cleaned)
    for marker, original in mapping.items():
        if marker not in cleaned:
            raise ValueError("translation response lost protected marker %s" % marker)
        cleaned = cleaned.replace(marker, original)
    leftovers = re.findall(r"__JF_PH_\d{4}__", cleaned)
    if leftovers:
        raise ValueError("translation response contains unknown protected markers: %s" % leftovers)
    return cleaned


def protected_tokens(value: str, literal_terms: Sequence[str]) -> Tuple[str, Dict[str, str]]:
    candidates: List[Tuple[int, int, str]] = []
    for match in FORMAT_RE.finditer(value):
        candidates.append((match.start(), match.end(), match.group(0)))
    for match in URL_RE.finditer(value):
        candidates.append((match.start(), match.end(), match.group(0)))
    for term in sorted(literal_terms, key=len, reverse=True):
        for match in re.finditer(re.escape(term), value):
            candidates.append((match.start(), match.end(), match.group(0)))
    for match in re.finditer(r"\n|\t", value):
        candidates.append((match.start(), match.end(), match.group(0)))

    selected: List[Tuple[int, int, str]] = []
    for candidate in sorted(candidates, key=lambda item: (item[0], -(item[1] - item[0]))):
        if any(candidate[0] < end and candidate[1] > start for start, end, _ in selected):
            continue
        selected.append(candidate)
    selected.sort()

    output: List[str] = []
    mapping: Dict[str, str] = {}
    cursor = 0
    for index, (start, end, original) in enumerate(selected):
        output.append(value[cursor:start])
        # Angle-bracket variable tokens have proven stable on the live Google
        # webpage across scripts. Keep the suffix deliberately meaningless:
        # readable hints such as Apple or FORMATVALUE can themselves be
        # translated. The local mapping retains the actual type and value.
        marker = "<JFP%04d_ZXQ>" % index
        mapping[marker] = original
        output.append(marker)
        cursor = end
    output.append(value[cursor:])
    return "".join(output), mapping


def restore_protected_tokens(value: str, mapping: Dict[str, str]) -> str:
    restored = value
    for marker, original in mapping.items():
        if marker not in restored:
            raise ValueError("Google web response lost protected marker %s" % marker)
        restored = restored.replace(marker, original)
    leftovers = re.findall(r"<JFP\d{4}_ZXQ>", restored)
    if leftovers:
        raise ValueError("Google web response contains unknown protected markers: %s" % leftovers)
    return restored


class GoogleWebTranslator:
    def __init__(self) -> None:
        self.process: Optional[subprocess.Popen[str]] = None
        self.request_id = 0

    def __enter__(self) -> "GoogleWebTranslator":
        if not GOOGLE_WEB_HELPER.exists():
            raise RuntimeError("Google web helper is missing: %s" % GOOGLE_WEB_HELPER)
        self.process = subprocess.Popen(
            ["node", str(GOOGLE_WEB_HELPER)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        return self

    def __exit__(self, exc_type: Any, exc: Any, traceback: Any) -> None:
        if self.process is None:
            return
        if self.process.stdin:
            self.process.stdin.close()
        try:
            self.process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=10)

    def translate(self, texts: Sequence[str], target: str) -> List[str]:
        if self.process is None or self.process.stdin is None or self.process.stdout is None:
            raise RuntimeError("Google web browser helper is not running")
        self.request_id += 1
        request = {"id": self.request_id, "target": target, "texts": list(texts)}
        self.process.stdin.write(json.dumps(request, ensure_ascii=False, separators=(",", ":")) + "\n")
        self.process.stdin.flush()
        raw = self.process.stdout.readline()
        if not raw:
            raise RuntimeError("Google web browser helper exited unexpectedly")
        response = json.loads(raw)
        if response.get("id") != self.request_id:
            raise RuntimeError("Google web browser helper returned an unexpected response id")
        if response.get("error"):
            raise RuntimeError("Google web translation failed: %s" % response["error"])
        output = response.get("translations")
        if not isinstance(output, list) or len(output) != len(texts):
            raise RuntimeError("Google web browser helper returned an unexpected item count")
        return [str(value) for value in output]


class AzureTranslator:
    def __init__(self, rate_chars_per_minute: int = 25000) -> None:
        self.key = os.environ.get("AZURE_TRANSLATOR_KEY", "")
        self.region = os.environ.get("AZURE_TRANSLATOR_REGION", "")
        self.endpoint = os.environ.get(
            "AZURE_TRANSLATOR_ENDPOINT",
            "https://api.cognitive.microsofttranslator.com",
        ).rstrip("/")
        self.rate_chars_per_minute = rate_chars_per_minute
        self.last_request_finished = 0.0

    def ensure_configured(self) -> None:
        if not self.key:
            raise RuntimeError(
                "AZURE_TRANSLATOR_KEY is not configured. Create an Azure Translator F0 resource, "
                "then export AZURE_TRANSLATOR_KEY and AZURE_TRANSLATOR_REGION."
            )

    def translate(self, texts: Sequence[str], target: str) -> List[str]:
        self.ensure_configured()
        if not texts:
            return []
        billable = sum(len(text) for text in texts)
        if billable > 50000 or len(texts) > 1000:
            raise ValueError("Azure request exceeds text translation limits")

        minimum_interval = (billable / float(self.rate_chars_per_minute)) * 60.0
        elapsed = time.monotonic() - self.last_request_finished
        if self.last_request_finished and elapsed < minimum_interval:
            time.sleep(minimum_interval - elapsed)

        query = urllib.parse.urlencode(
            {"api-version": "3.0", "from": "en", "to": target, "textType": "html"}
        )
        url = self.endpoint + "/translate?" + query
        body = json.dumps([{"Text": text} for text in texts], ensure_ascii=False).encode("utf-8")
        headers = {
            "Content-Type": "application/json; charset=UTF-8",
            "Ocp-Apim-Subscription-Key": self.key,
            "X-ClientTraceId": str(uuid.uuid4()),
        }
        if self.region:
            headers["Ocp-Apim-Subscription-Region"] = self.region

        for attempt in range(5):
            request = urllib.request.Request(url, data=body, headers=headers, method="POST")
            try:
                with urllib.request.urlopen(request, timeout=45) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                output = [item["translations"][0]["text"] for item in payload]
                if len(output) != len(texts):
                    raise RuntimeError("Azure returned an unexpected item count")
                self.last_request_finished = time.monotonic()
                return output
            except urllib.error.HTTPError as error:
                retryable = error.code == 429 or 500 <= error.code < 600
                if not retryable or attempt == 4:
                    detail = error.read().decode("utf-8", errors="replace")
                    raise RuntimeError("Azure HTTP %d: %s" % (error.code, detail[:500])) from error
                retry_after = error.headers.get("Retry-After")
                delay = float(retry_after) if retry_after and retry_after.isdigit() else float(2 ** attempt)
                time.sleep(delay)
            except urllib.error.URLError as error:
                if attempt == 4:
                    raise RuntimeError("Azure network error: %s" % error) from error
                time.sleep(float(2 ** attempt))
        raise RuntimeError("Azure translation failed after retries")


def provider_cache_path(group: str) -> Path:
    safe_group = re.sub(r"[^A-Za-z0-9_.-]", "_", group)
    return BUILD_ROOT / "cache" / "azure" / (safe_group + ".json")


def load_provider_cache(group: str) -> Dict[str, str]:
    path = provider_cache_path(group)
    return read_json(path) if path.exists() else {}


def save_provider_cache(group: str, cache: Dict[str, str]) -> None:
    atomic_write(provider_cache_path(group), json.dumps(cache, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def google_web_cache_path(target: str) -> Path:
    safe_target = re.sub(r"[^A-Za-z0-9_.-]", "_", target)
    return BUILD_ROOT / "cache" / "google-web" / (safe_target + ".json")


def load_google_web_cache(target: str) -> Dict[str, str]:
    path = google_web_cache_path(target)
    return read_json(path) if path.exists() else {}


def save_google_web_cache(target: str, cache: Dict[str, str]) -> None:
    atomic_write(google_web_cache_path(target), json.dumps(cache, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def current_month_azure_usage() -> int:
    if not AZURE_USAGE_LEDGER.exists():
        return 0
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    total = 0
    for raw in AZURE_USAGE_LEDGER.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        row = json.loads(raw)
        if str(row.get("timestamp", "")).startswith(month):
            total += int(row.get("characters", 0))
    return total


def record_azure_usage(locale: str, group: str, entries: Sequence[Entry]) -> None:
    previous = AZURE_USAGE_LEDGER.read_text(encoding="utf-8") if AZURE_USAGE_LEDGER.exists() else ""
    row = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "locale": locale,
        "machine_group": group,
        "characters": sum(len(entry.value) for entry in entries),
        "rows": len(entries),
        "source_hashes": [entry.source_hash for entry in entries],
    }
    atomic_write(AZURE_USAGE_LEDGER, previous + json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")


def fixed_value(entry: Entry, locale: str) -> Optional[str]:
    if entry.table == "Plural":
        return None
    config = protected_config()
    if entry.table == "Localizable":
        fixed = config.get("fixed_localizable_values", {})
    else:
        fixed = config.get("fixed_info_plist_values", {})
    if entry.key not in fixed:
        return None
    if locale == "zh-Hans":
        values = {item.key: item.value for item in parse_strings(RESOURCE_ROOT / "zh-Hans.lproj" / (entry.table + ".strings"), entry.table)}
        return values.get(entry.key, fixed[entry.key])
    if locale == "zh-Hant":
        values = {item.key: item.value for item in parse_strings(RESOURCE_ROOT / "zh-Hant.lproj" / (entry.table + ".strings"), entry.table)}
        return values.get(entry.key, fixed[entry.key])
    return fixed[entry.key]


def current_or_new_row(entry: Entry, previous: Optional[Dict[str, Any]], locale: str) -> Dict[str, Any]:
    fixed = fixed_value(entry, locale)
    if fixed is None and previous and previous.get("source_hash") == entry.source_hash:
        return dict(previous)
    return {
        "table": entry.table,
        "key": entry.key,
        "source_hash": entry.source_hash,
        "azure": fixed,
        "google_web": fixed,
        "google": None,
        "final": fixed,
        "status": "fixed" if fixed is not None else "pending",
        "flags": [],
        "note": "product-fixed" if fixed is not None else None,
    }


def normalize_translation_text(value: str) -> str:
    """Remove provider-added edge whitespace and keep catalog text NFC."""
    return unicodedata.normalize("NFC", value.strip())


def machine_candidate(row: Dict[str, Any]) -> Optional[str]:
    candidate = row.get("google_web") or row.get("azure")
    return normalize_translation_text(candidate) if isinstance(candidate, str) else None


def risk_flags(entry: Entry, locale_spec: Dict[str, Any]) -> List[str]:
    config = protected_config()
    flags: List[str] = []
    if any(entry.key.startswith(prefix) for prefix in config.get("critical_key_prefixes", [])):
        flags.append("critical-domain")
    if FORMAT_RE.search(entry.value):
        flags.append("format")
    if "\n" in entry.value:
        flags.append("multiline")
    if len(entry.value) <= 16:
        flags.append("short-ambiguous")
    if len(entry.value) >= 180:
        flags.append("long-copy")
    if locale_spec.get("rtl"):
        flags.append("rtl")
    if entry.table == "InfoPlist":
        flags.append("permission")
    return flags


def risk_score(flags: Sequence[str]) -> int:
    weights = {
        "critical-domain": 5,
        "permission": 5,
        "format": 4,
        "rtl": 4,
        "short-ambiguous": 3,
        "long-copy": 3,
        "multiline": 2,
    }
    return sum(weights.get(flag, 0) for flag in flags)


def batch_entries(entries: Sequence[Entry], max_chars: int = 4000, max_items: int = 100) -> Iterable[List[Entry]]:
    batch: List[Entry] = []
    characters = 0
    for entry in entries:
        size = len(entry.value)
        if batch and (characters + size > max_chars or len(batch) >= max_items):
            yield batch
            batch = []
            characters = 0
        batch.append(entry)
        characters += size
    if batch:
        yield batch


def command_inventory(args: argparse.Namespace) -> int:
    entries = base_source_entries()
    locales = choose_locales(args)
    unique_groups: Dict[str, Dict[str, Any]] = {}
    for spec in locales:
        group = spec.get("machine_group", spec["ios"])
        unique_groups.setdefault(group, spec)
    translatable = [entry for entry in entries if fixed_value(entry, "ja") is None]
    per_locale_chars = sum(len(entry.value) for entry in translatable)
    estimated = 0
    for spec in unique_groups.values():
        estimated += per_locale_chars + sum(len(entry.value) for entry in plural_entries(spec["ios"]))
    formatted = sum(1 for entry in entries if FORMAT_RE.search(entry.value))
    multiline = sum(1 for entry in entries if "\n" in entry.value)
    payload = {
        "source": {
            "Localizable": sum(1 for entry in entries if entry.table == "Localizable"),
            "InfoPlist": sum(1 for entry in entries if entry.table == "InfoPlist"),
            "formatted": formatted,
            "multiline": multiline,
            "translatable_characters": per_locale_chars,
            "plural_keys": len(plural_manifest()["keys"]),
        },
        "selected_locales": [item["ios"] for item in locales],
        "unique_machine_groups": sorted(unique_groups),
        "estimated_azure_characters": estimated,
        "azure_current_month_recorded_usage": current_month_azure_usage(),
        "azure_budget": args.max_billable_chars,
        "within_budget": estimated <= args.max_billable_chars,
        "catalogs": {},
    }
    for spec in locales:
        source_map = source_by_identity(spec["ios"])
        catalog = load_catalog(spec["ios"])
        fresh = sum(1 for identity, row in catalog.items() if identity in source_map and row.get("source_hash") == source_map[identity].source_hash)
        reviewed = sum(1 for row in catalog.values() if row.get("status") in REVIEW_STATES)
        missing = sorted(set(source_map) - set(catalog))
        stale = sorted(
            identity for identity in set(source_map).intersection(catalog)
            if catalog[identity].get("source_hash") != source_map[identity].source_hash
        )
        expired = sorted(set(catalog) - set(source_map))
        detail: Dict[str, Any] = {
            "rows": len(catalog),
            "fresh": fresh,
            "reviewed": reviewed,
            "new": len(missing),
            "stale": len(stale),
            "expired": len(expired),
        }
        if catalog:
            detail["new_keys"] = ["%s/%s" % identity for identity in missing]
            detail["stale_keys"] = ["%s/%s" % identity for identity in stale]
            detail["expired_keys"] = ["%s/%s" % identity for identity in expired]
        else:
            detail["state"] = "not_started"
        payload["catalogs"][spec["ios"]] = detail
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0 if payload["within_budget"] else 2


def command_translate(args: argparse.Namespace) -> int:
    specs = choose_locales(args)
    grouped_specs: Dict[str, Dict[str, Any]] = {}
    for spec in specs:
        grouped_specs.setdefault(spec.get("machine_group", spec["ios"]), spec)
    groups = set(grouped_specs)
    estimate = 0
    for group, spec in grouped_specs.items():
        cache = load_provider_cache(group)
        for entry in source_entries(spec["ios"]):
            if fixed_value(entry, spec["ios"]) is not None:
                continue
            cache_key = "%s:%s:%s" % (entry.table, entry.key, entry.source_hash)
            if cache_key not in cache:
                estimate += len(entry.value)
    month_usage = current_month_azure_usage()
    if month_usage + estimate > args.max_billable_chars and not args.allow_budget_overrun:
        raise RuntimeError(
            "current-month usage %d + missing drafts %d exceeds budget %d; "
            "use --allow-budget-overrun only after checking Azure billing"
            % (month_usage, estimate, args.max_billable_chars)
        )
    if args.dry_run:
        print("dry-run: locales=%s groups=%s month_usage=%d missing_chars=%d projected=%d" % (
            ",".join(spec["ios"] for spec in specs), ",".join(sorted(groups)), month_usage, estimate, month_usage + estimate
        ))
        return 0

    translator = AzureTranslator(rate_chars_per_minute=args.rate_chars_per_minute)
    translator.ensure_configured()
    literal_terms = protected_config().get("literal_terms", [])

    for spec in specs:
        locale = spec["ios"]
        entries = source_entries(locale)
        group = spec.get("machine_group", locale)
        cache = load_provider_cache(group)
        previous = load_catalog(locale)
        catalog = {entry.identity: current_or_new_row(entry, previous.get(entry.identity), locale) for entry in entries}

        pending: List[Entry] = []
        for entry in entries:
            row = catalog[entry.identity]
            row["flags"] = risk_flags(entry, spec)
            if row.get("status") == "fixed":
                continue
            cache_key = "%s:%s:%s" % (entry.table, entry.key, entry.source_hash)
            if cache_key in cache:
                row["azure"] = cache[cache_key]
                if row.get("status") == "pending":
                    row["status"] = "machine"
            elif row.get("azure") and row.get("source_hash") == entry.source_hash:
                cache[cache_key] = row["azure"]
            else:
                pending.append(entry)

        print("%s: %d cached/fixed, %d pending" % (locale, len(entries) - len(pending), len(pending)))
        for batch_number, batch in enumerate(batch_entries(pending), 1):
            wrapped: List[str] = []
            mappings: List[Dict[str, str]] = []
            for entry in batch:
                text, mapping = protected_spans(entry.value, literal_terms)
                wrapped.append(text)
                mappings.append(mapping)
            translated = translator.translate(wrapped, spec["azure"])
            record_azure_usage(locale, group, batch)
            for entry, raw, mapping in zip(batch, translated, mappings):
                restored = restore_protected(raw, mapping)
                row = catalog[entry.identity]
                row["azure"] = restored
                row["status"] = "machine"
                cache_key = "%s:%s:%s" % (entry.table, entry.key, entry.source_hash)
                cache[cache_key] = restored
            save_provider_cache(group, cache)
            write_catalog(locale, catalog)
            print("%s: saved batch %d (%d entries)" % (locale, batch_number, len(batch)))
        write_catalog(locale, catalog)
    return 0


def command_translate_google_web(args: argparse.Namespace) -> int:
    specs = choose_locales(args)
    literal_terms = protected_config().get("literal_terms", [])
    completed_batches = 0

    if args.dry_run:
        totals: Dict[str, Dict[str, int]] = {}
        for spec in specs:
            locale = spec["ios"]
            target = spec["google"]
            cache = load_google_web_cache(target)
            entries = source_entries(locale)
            missing = 0
            characters = 0
            for entry in entries:
                if fixed_value(entry, locale) is not None:
                    continue
                cache_key = "%s:%s:%s" % (entry.table, entry.key, entry.source_hash)
                if cache_key not in cache:
                    missing += 1
                    characters += len(entry.value)
            totals[locale] = {"missing_rows": missing, "source_characters": characters}
        print(json.dumps(totals, ensure_ascii=False, indent=2))
        return 0

    with GoogleWebTranslator() as translator:
        def translate_batch(batch: Sequence[Entry], target: str) -> List[str]:
            wrapped: List[str] = []
            plans: List[List[Optional[Tuple[int, Dict[str, str]]]]] = []
            for entry in batch:
                # Google Translate occasionally merges neighbouring lines in a
                # long paragraph and drops the marker standing in for the
                # newline. Translate each source line as its own webpage row,
                # then rebuild the exact original line structure locally.
                entry_plan: List[Optional[Tuple[int, Dict[str, str]]]] = []
                for segment in entry.value.split("\n"):
                    if not segment:
                        entry_plan.append(None)
                        continue
                    text, mapping = protected_tokens(segment, literal_terms)
                    entry_plan.append((len(wrapped), mapping))
                    wrapped.append(text)
                plans.append(entry_plan)
            try:
                translated = translator.translate(wrapped, target)
                restored_values: List[str] = []
                for entry, entry_plan in zip(batch, plans):
                    restored_segments: List[str] = []
                    for segment_plan in entry_plan:
                        if segment_plan is None:
                            restored_segments.append("")
                            continue
                        translated_index, mapping = segment_plan
                        raw = translated[translated_index]
                        try:
                            restored_segments.append(unicodedata.normalize("NFC", restore_protected_tokens(raw, mapping)))
                        except ValueError as error:
                            raise ValueError("%s/%s: %s; raw=%r" % (entry.table, entry.key, error, raw)) from error
                    restored_values.append("\n".join(restored_segments))
                return restored_values
            except (RuntimeError, ValueError) as error:
                if len(batch) <= 1:
                    raise
                midpoint = len(batch) // 2
                print("Google web batch fallback %d -> %d + %d: %s" % (
                    len(batch), midpoint, len(batch) - midpoint, error
                ), file=sys.stderr, flush=True)
                return translate_batch(batch[:midpoint], target) + translate_batch(batch[midpoint:], target)

        for spec in specs:
            locale = spec["ios"]
            target = spec["google"]
            entries = source_entries(locale)
            cache = load_google_web_cache(target)
            previous = load_catalog(locale)
            catalog = {entry.identity: current_or_new_row(entry, previous.get(entry.identity), locale) for entry in entries}

            pending: List[Entry] = []
            for entry in entries:
                row = catalog[entry.identity]
                row["flags"] = risk_flags(entry, spec)
                if row.get("status") == "fixed":
                    continue
                cache_key = "%s:%s:%s" % (entry.table, entry.key, entry.source_hash)
                if cache_key in cache:
                    row["google_web"] = unicodedata.normalize("NFC", cache[cache_key])
                    row["machine_provider"] = "google-web"
                    if row.get("status") == "pending":
                        row["status"] = "machine"
                elif row.get("google_web") and row.get("source_hash") == entry.source_hash:
                    cache[cache_key] = row["google_web"]
                else:
                    pending.append(entry)

            print("%s: %d cached/fixed, %d pending via Google web" % (
                locale, len(entries) - len(pending), len(pending)
            ), flush=True)
            for batch_number, batch in enumerate(batch_entries(pending, max_chars=args.batch_chars, max_items=args.batch_items), 1):
                translated = translate_batch(batch, target)
                for entry, restored in zip(batch, translated):
                    row = catalog[entry.identity]
                    row["google_web"] = restored
                    row["machine_provider"] = "google-web"
                    row["status"] = "machine"
                    cache_key = "%s:%s:%s" % (entry.table, entry.key, entry.source_hash)
                    cache[cache_key] = restored
                save_google_web_cache(target, cache)
                write_catalog(locale, catalog)
                completed_batches += 1
                print("%s: saved Google web batch %d (%d entries)" % (locale, batch_number, len(batch)), flush=True)
                if args.max_batches and completed_batches >= args.max_batches:
                    print("stopped after requested max batch count; rerun with --resume", flush=True)
                    return 0
                if args.delay_seconds:
                    time.sleep(args.delay_seconds)
            write_catalog(locale, catalog)
    return 0


async def google_translate_values(texts: Sequence[str], source: str, target: str) -> List[str]:
    try:
        from googletrans import Translator  # type: ignore
    except ImportError as error:
        raise RuntimeError(
            "googletrans is optional and not installed; create a venv under build/ and install "
            "scripts/localization/requirements-localization.txt"
        ) from error
    translator = Translator()
    try:
        result = translator.translate(list(texts), src=source, dest=target)
        if inspect.isawaitable(result):
            result = await result
        if not isinstance(result, list):
            result = [result]
        return [item.text for item in result]
    finally:
        close = getattr(translator, "close", None)
        if close is not None:
            closed = close()
            if inspect.isawaitable(closed):
                await closed


def command_sample_google(args: argparse.Namespace) -> int:
    specs = choose_locales(args)
    literal_terms = protected_config().get("literal_terms", [])
    remaining_budget = args.max_chars
    randomizer = random.Random(args.seed)

    for spec in specs:
        if remaining_budget <= 0:
            break
        locale = spec["ios"]
        entries = source_entries(locale)
        source_map = {entry.identity: entry for entry in entries}
        catalog = load_catalog(locale)
        candidates: List[Tuple[int, float, Entry]] = []
        for identity, row in catalog.items():
            entry = source_map.get(identity)
            if not entry or row.get("source_hash") != entry.source_hash or not machine_candidate(row) or row.get("google"):
                continue
            score = risk_score(row.get("flags", []))
            candidates.append((score, randomizer.random(), entry))
        candidates.sort(key=lambda item: (-item[0], item[1]))

        selected: List[Entry] = []
        used = 0
        for _, _, entry in candidates:
            if used + len(entry.value) > remaining_budget:
                continue
            selected.append(entry)
            used += len(entry.value)
            if used >= min(args.locale_max_chars, remaining_budget):
                break
        if not selected:
            continue

        print("%s: google sample %d entries / %d source characters" % (locale, len(selected), used))
        for batch in batch_entries(selected, max_chars=3500, max_items=50):
            wrapped: List[str] = []
            mappings: List[Dict[str, str]] = []
            for entry in batch:
                text, mapping = protected_spans(entry.value, literal_terms)
                wrapped.append(text)
                mappings.append(mapping)
            try:
                raw_values = asyncio.run(google_translate_values(wrapped, "en", spec["google"]))
                for entry, raw, mapping in zip(batch, raw_values, mappings):
                    catalog[entry.identity]["google"] = restore_protected(raw, mapping)
                write_catalog(locale, catalog)
                time.sleep(args.delay_seconds)
            except Exception as error:
                print("warning: google sample stopped for %s: %s" % (locale, error), file=sys.stderr)
                break
        remaining_budget -= used
    return 0


def command_review_packet(args: argparse.Namespace) -> int:
    spec = locale_map()[args.locale]
    entries = source_entries(args.locale)
    source_map = {entry.identity: entry for entry in entries}
    chinese = zh_hans_values()
    catalog = load_catalog(args.locale)
    pending: List[Entry] = []
    for entry in entries:
        row = catalog.get(entry.identity)
        if row and row.get("source_hash") == entry.source_hash and machine_candidate(row) and row.get("status") not in REVIEW_STATES:
            pending.append(entry)
    start = args.chunk * args.chunk_size
    chunk = pending[start:start + args.chunk_size]
    if not chunk:
        print("no pending review entries for chunk %d" % args.chunk)
        return 0
    output = args.output or (BUILD_ROOT / "review" / args.locale / ("chunk-%04d.jsonl" % args.chunk))
    lines: List[str] = []
    for entry in chunk:
        row = catalog[entry.identity]
        flags = row.get("flags", [])
        item: Dict[str, Any] = {
            "table": entry.table,
            "section": entry.section,
            "key": entry.key,
            "en": entry.value,
            "draft": machine_candidate(row),
            "draft_provider": row.get("machine_provider") or ("azure" if row.get("azure") else None),
            "flags": flags,
        }
        if risk_score(flags) >= args.chinese_threshold or row.get("google"):
            if entry.table == "Plural":
                base_key = entry.key.rsplit(".", 1)[0]
                item["zh-Hans"] = chinese.get(("Localizable", base_key))
            else:
                item["zh-Hans"] = chinese.get(entry.identity)
        if row.get("google"):
            item["google"] = row["google"]
        lines.append(json.dumps(item, ensure_ascii=False, separators=(",", ":")))
    atomic_write(Path(output), "\n".join(lines) + "\n")
    print("wrote %d entries to %s (remaining after chunk: %d)" % (len(chunk), output, max(0, len(pending) - start - len(chunk))))
    if spec.get("rtl"):
        print("note: %s is RTL; include directional layout review" % args.locale)
    return 0


def command_apply_review(args: argparse.Namespace) -> int:
    entries = source_by_identity(args.locale)
    catalog = load_catalog(args.locale)
    decisions = Path(args.input).read_text(encoding="utf-8").splitlines()
    changed = 0
    for number, raw in enumerate(decisions, 1):
        if not raw.strip():
            continue
        decision = json.loads(raw)
        identity = (decision.get("table", "Localizable"), decision["key"])
        entry = entries.get(identity)
        row = catalog.get(identity)
        if not entry or not row:
            raise ValueError("unknown review identity %s/%s at line %d" % (identity[0], identity[1], number))
        if row.get("source_hash") != entry.source_hash:
            raise ValueError("stale review for %s/%s at line %d" % (identity[0], identity[1], number))
        action = decision.get("decision")
        if action is None and "draft" in decision:
            # A generated review packet may be applied directly after it has
            # been checked. Guard against stale or hand-edited packets; focused
            # revisions can then be overlaid with a smaller decisions file.
            if decision.get("en") != entry.value or decision.get("draft") != machine_candidate(row):
                raise ValueError("stale review packet for %s/%s at line %d" % (identity[0], identity[1], number))
            action = "approve"
        if action == "approve":
            row["final"] = machine_candidate(row)
        elif action == "revise":
            value = decision.get("value")
            if not isinstance(value, str) or not value:
                raise ValueError("revise requires a non-empty value at line %d" % number)
            row["final"] = value
        else:
            raise ValueError("decision must be approve or revise at line %d" % number)
        row["status"] = "reviewed"
        row["note"] = decision.get("note")
        row["issues"] = decision.get("issues", [])
        changed += 1
    write_catalog(args.locale, catalog)
    print("applied %d review decisions to %s" % (changed, args.locale))
    return 0


def value_for_row(row: Dict[str, Any]) -> Optional[str]:
    if row.get("status") in REVIEW_STATES and row.get("final") is not None:
        return row.get("final")
    return machine_candidate(row)


def validate_locale(locale: str, require_reviewed: bool) -> Dict[str, Any]:
    spec = locale_map()[locale]
    entries = source_entries(locale)
    expected = {entry.identity: entry for entry in entries}
    catalog = load_catalog(locale)
    blockers: List[Dict[str, Any]] = []
    warnings: List[Dict[str, Any]] = []
    config = protected_config()

    def report(target: List[Dict[str, Any]], code: str, entry: Optional[Entry], detail: str) -> None:
        target.append({
            "code": code,
            "table": entry.table if entry else None,
            "key": entry.key if entry else None,
            "detail": detail,
        })

    for identity in sorted(set(catalog) - set(expected)):
        report(blockers, "unknown-key", None, "%s/%s" % identity)
    for entry in entries:
        row = catalog.get(entry.identity)
        if row is None:
            report(blockers, "missing-key", entry, "catalog row is missing")
            continue
        if row.get("source_hash") != entry.source_hash:
            report(blockers, "stale-source", entry, "source changed after translation")
            continue
        value = value_for_row(row)
        expected_fixed = fixed_value(entry, locale)
        if not isinstance(value, str) or (not value and expected_fixed != ""):
            report(blockers, "empty", entry, "translation is empty")
            continue
        if require_reviewed and row.get("status") not in REVIEW_STATES:
            report(blockers, "unreviewed", entry, "status=%s" % row.get("status"))

        source_arguments, source_mixed = format_arguments(entry.value)
        target_arguments, target_mixed = format_arguments(value)
        if source_mixed or target_mixed:
            report(blockers, "mixed-format-indexing", entry, "do not mix positional and sequential placeholders")
        if source_arguments != target_arguments:
            report(blockers, "format-mismatch", entry, "%s != %s" % (source_arguments, target_arguments))
        if entry.value.count("\n") != value.count("\n"):
            report(blockers, "newline-mismatch", entry, "%d != %d" % (entry.value.count("\n"), value.count("\n")))
        if unicodedata.normalize("NFC", value) != value:
            report(blockers, "unicode-not-nfc", entry, "value must be normalized to NFC")
        is_sentence_fragment = entry.table == "Localizable" and entry.key in SENTENCE_FRAGMENT_KEYS
        # Permit at most one ordinary space on each edge of reviewed fragments.
        # Keep rejecting tabs, newlines, and accidental padding everywhere else.
        allowed_fragment_spaces = (
            is_sentence_fragment
            and value.strip(" ") == value.strip()
            and not value.startswith("  ")
            and not value.endswith("  ")
        )
        if value != value.strip() and not allowed_fragment_spaces:
            report(blockers, "edge-whitespace", entry, "translation has unexpected leading or trailing whitespace")
        # Providers copied the Chinese source's CJK word spacing into reviewed strings.
        # Only judge rows that ship; machine drafts are still allowed to carry the artefact.
        if row.get("status") in REVIEW_STATES and re.search(r"\S {2,}\S", value) and not re.search(r"\S {2,}\S", entry.value):
            report(blockers, "internal-multi-space", entry, "CJK-style double space in %r" % value[:60])
        if row.get("status") in REVIEW_STATES:
            glued = punctuation_glue(value)
            if glued:
                report(blockers, "punctuation-glue", entry, "missing space after punctuation in %r" % glued[0])
        bad_controls = sorted({character for character in value if unicodedata.category(character) == "Cc" and character not in "\n\t"})
        if bad_controls:
            report(blockers, "control-character", entry, repr(bad_controls))
        bidi = sorted(set(value).intersection(BIDI_CONTROLS))
        if bidi:
            report(blockers, "manual-bidi-control", entry, repr(bidi))
        if PIPE_ARTIFACT in value and PIPE_ARTIFACT not in entry.value:
            report(blockers, "provider-artifact", entry, "machine multi-alternative residue: %r" % value[:60])
        source_urls = url_literals(entry.value)
        if source_urls and url_literals(value) != source_urls:
            report(blockers, "protected-url", entry, "source URL was changed, removed, or split by whitespace")
        for term in config.get("literal_terms", []):
            if term in entry.value and term not in value:
                report(blockers, "protected-term", entry, "%s was changed or removed" % term)
        if expected_fixed is not None and value != expected_fixed:
            report(blockers, "fixed-value", entry, "expected %r" % expected_fixed)
        if locale != "en" and value == entry.value and re.search(r"[A-Za-z]", entry.value):
            if not any(term == entry.value for term in config.get("literal_terms", [])):
                report(warnings, "source-equality", entry, "translation equals English source")
        if len(entry.value) >= 10 and len(value) > len(entry.value) * 3.0:
            report(warnings, "length-expansion", entry, "%d -> %d" % (len(entry.value), len(value)))

    status_counts: Dict[str, int] = {}
    for row in catalog.values():
        status = str(row.get("status"))
        status_counts[status] = status_counts.get(status, 0) + 1
    return {
        "locale": locale,
        "rtl": bool(spec.get("rtl")),
        "expected_rows": len(entries),
        "catalog_rows": len(catalog),
        "status_counts": status_counts,
        "blockers": blockers,
        "warnings": warnings,
        "passed": not blockers,
    }


def command_validate(args: argparse.Namespace) -> int:
    specs = choose_locales(args)
    reports = [validate_locale(spec["ios"], args.require_reviewed) for spec in specs]
    output = args.output or (BUILD_ROOT / "reports" / "validation.json")
    atomic_write(Path(output), json.dumps(reports, ensure_ascii=False, indent=2) + "\n")
    for report in reports:
        print("%s: blockers=%d warnings=%d statuses=%s" % (
            report["locale"], len(report["blockers"]), len(report["warnings"]), report["status_counts"]
        ))
    print("report -> %s" % output)
    return 0 if all(report["passed"] for report in reports) else 2


def render_strings(template: Path, table: str, catalog: Dict[Tuple[str, str], Dict[str, Any]]) -> str:
    output: List[str] = []
    for raw in template.read_text(encoding="utf-8").splitlines():
        match = ENTRY_RE.match(raw)
        if not match:
            output.append(raw)
            continue
        key = decode_apple_string(match.group(1))
        row = catalog[(table, key)]
        value = value_for_row(row)
        if value is None:
            raise ValueError("missing rendered value for %s/%s" % (table, key))
        output.append('"%s" = "%s";' % (encode_apple_string(key), encode_apple_string(value)))
    return "\n".join(output) + "\n"


def render_stringsdict(locale: str, catalog: Dict[Tuple[str, str], Dict[str, Any]]) -> bytes:
    payload: Dict[str, Any] = {}
    value_type = plural_manifest().get("value_type", "d")
    for item in plural_manifest()["keys"]:
        forms: Dict[str, str] = {
            "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
            "NSStringFormatValueTypeKey": value_type,
        }
        for category in locale_map()[locale]["plural_categories"]:
            row = catalog[("Plural", "%s.%s" % (item["key"], category))]
            value = value_for_row(row)
            if value is None:
                raise ValueError("missing plural value for %s/%s" % (item["key"], category))
            forms[category] = value
        payload[item["key"]] = {
            "NSStringLocalizedFormatKey": "%#@count@",
            "count": forms,
        }
    return plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=False)


def existing_stringsdict(locale: str) -> bytes:
    source_values = {
        entry.key: entry.value
        for entry in parse_strings(RESOURCE_ROOT / (locale + ".lproj") / "Localizable.strings", "Localizable")
    }
    payload: Dict[str, Any] = {}
    value_type = plural_manifest().get("value_type", "d")
    for item in plural_manifest()["keys"]:
        forms: Dict[str, str] = {
            "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
            "NSStringFormatValueTypeKey": value_type,
        }
        for category in locale_map()[locale]["plural_categories"]:
            if locale == "en":
                forms[category] = item["one"] if category == "one" else item["other"]
            else:
                forms[category] = source_values[item["key"]]
        payload[item["key"]] = {
            "NSStringLocalizedFormatKey": "%#@count@",
            "count": forms,
        }
    return plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=False)


def command_bootstrap_plurals(args: argparse.Namespace) -> int:
    for locale in ("en", "zh-Hans", "zh-Hant"):
        destination = RESOURCE_ROOT / (locale + ".lproj") / "Localizable.stringsdict"
        data = existing_stringsdict(locale)
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_suffix(destination.suffix + ".tmp")
        temporary.write_bytes(data)
        temporary.replace(destination)
        result = subprocess.run(["plutil", "-lint", str(destination)], capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError("plutil failed for %s: %s" % (destination, result.stdout + result.stderr))
        print("wrote %s" % destination)
    return 0


def add_known_region(locale: str) -> None:
    text = PROJECT_FILE.read_text(encoding="utf-8")
    match = re.search(r"(?P<head>knownRegions\s*=\s*\(\n)(?P<body>.*?)(?P<tail>\n\s*\);)", text, re.DOTALL)
    if not match:
        raise ValueError("could not find knownRegions in project.pbxproj")
    existing = []
    for raw in match.group("body").splitlines():
        item = raw.strip().rstrip(",").strip('"')
        if item:
            existing.append(item)
    if locale in existing:
        return
    existing.append(locale)
    indent_match = re.search(r"^(\s*)\S", match.group("body"), re.MULTILINE)
    indent = indent_match.group(1) if indent_match else "\t\t\t\t"
    body = "\n".join("%s%s," % (indent, ('"%s"' % item) if "-" in item else item) for item in existing)
    updated = text[:match.start()] + match.group("head") + body + match.group("tail") + text[match.end():]
    atomic_write(PROJECT_FILE, updated)


def command_promote(args: argparse.Namespace) -> int:
    report = validate_locale(args.locale, require_reviewed=True)
    if not report["passed"]:
        output = BUILD_ROOT / "reports" / (args.locale + "-promotion-blocked.json")
        atomic_write(output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print("promotion blocked: %d blockers; report -> %s" % (len(report["blockers"]), output), file=sys.stderr)
        return 2
    catalog = load_catalog(args.locale)
    localizable = render_strings(SOURCE_LOCALIZABLE, "Localizable", catalog)
    info_plist = render_strings(SOURCE_INFO_PLIST, "InfoPlist", catalog)
    stringsdict = render_stringsdict(args.locale, catalog)
    destination = RESOURCE_ROOT / (args.locale + ".lproj")
    if args.dry_run:
        print("dry-run: would write %s and add %s to knownRegions" % (destination, args.locale))
        return 0
    destination.mkdir(parents=True, exist_ok=True)
    atomic_write(destination / "Localizable.strings", localizable)
    atomic_write(destination / "InfoPlist.strings", info_plist)
    stringsdict_path = destination / "Localizable.stringsdict"
    stringsdict_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = stringsdict_path.with_suffix(stringsdict_path.suffix + ".tmp")
    temporary.write_bytes(stringsdict)
    temporary.replace(stringsdict_path)
    for path in [destination / "Localizable.strings", destination / "InfoPlist.strings", stringsdict_path]:
        result = subprocess.run(["plutil", "-lint", str(path)], capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError("plutil failed for %s: %s" % (path, result.stdout + result.stderr))
    add_known_region(args.locale)
    print("promoted %s -> %s" % (args.locale, destination))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_selection(command: argparse.ArgumentParser) -> None:
        group = command.add_mutually_exclusive_group(required=True)
        group.add_argument("--locale", action="append", help="iOS locale identifier; repeatable")
        group.add_argument("--all", action="store_true", help="all 44 new locales")

    voice = subparsers.add_parser("voice", help="validate/promote the reviewed sports voice table")
    voice.add_argument("action", choices=["validate", "promote"])
    voice.add_argument("--locale", action="append")
    voice.add_argument("--dry-run", action="store_true")
    def run_voice(args: argparse.Namespace) -> int:
        import voice_localization
        selected = [args.action]
        for locale in args.locale or []:
            selected += ["--locale", locale]
        if args.dry_run: selected.append("--dry-run")
        return voice_localization.main(selected)
    voice.set_defaults(handler=run_voice)

    inventory = subparsers.add_parser("inventory", help="show source and cost inventory")
    add_selection(inventory)
    inventory.add_argument("--max-billable-chars", type=int, default=1850000)
    inventory.set_defaults(handler=command_inventory)

    bootstrap = subparsers.add_parser("bootstrap-plurals", help="generate checked-in plural resources for existing locales")
    bootstrap.set_defaults(handler=command_bootstrap_plurals)

    translate = subparsers.add_parser("translate", help="generate or resume Azure machine drafts")
    add_selection(translate)
    translate.add_argument("--dry-run", action="store_true")
    translate.add_argument("--resume", action="store_true", help="explicitly document the default cache/resume behavior")
    translate.add_argument("--rate-chars-per-minute", type=int, default=25000)
    translate.add_argument("--max-billable-chars", type=int, default=1850000)
    translate.add_argument("--allow-budget-overrun", action="store_true")
    translate.set_defaults(handler=command_translate)

    google_web = subparsers.add_parser("translate-google-web", help="drive the public Google Translate web page in Chrome")
    add_selection(google_web)
    google_web.add_argument("--dry-run", action="store_true")
    google_web.add_argument("--resume", action="store_true", help="explicitly document the default cache/resume behavior")
    google_web.add_argument("--batch-chars", type=int, default=3000)
    google_web.add_argument("--batch-items", type=int, default=80)
    google_web.add_argument("--delay-seconds", type=float, default=2.0)
    google_web.add_argument("--max-batches", type=int, default=0, help="stop safely after N batches; zero means unlimited")
    google_web.set_defaults(handler=command_translate_google_web)

    google = subparsers.add_parser("sample-google", help="non-gating googletrans sample")
    add_selection(google)
    google.add_argument("--max-chars", type=int, default=250000)
    google.add_argument("--locale-max-chars", type=int, default=12000)
    google.add_argument("--seed", type=int, default=20260925)
    google.add_argument("--delay-seconds", type=float, default=1.5)
    google.set_defaults(handler=command_sample_google)

    packet = subparsers.add_parser("review-packet", help="emit a compact Codex review packet")
    packet.add_argument("--locale", required=True, choices=sorted(locale_map()))
    packet.add_argument("--chunk", type=int, default=0)
    packet.add_argument("--chunk-size", type=int, default=100)
    packet.add_argument("--chinese-threshold", type=int, default=5)
    packet.add_argument("--output", type=Path)
    packet.set_defaults(handler=command_review_packet)

    apply_review = subparsers.add_parser("apply-review", help="apply approve/revise JSONL decisions")
    apply_review.add_argument("--locale", required=True, choices=sorted(locale_map()))
    apply_review.add_argument("--input", required=True, type=Path)
    apply_review.set_defaults(handler=command_apply_review)

    validate = subparsers.add_parser("validate", help="run deterministic catalog gates")
    add_selection(validate)
    validate.add_argument("--require-reviewed", action="store_true")
    validate.add_argument("--output", type=Path)
    validate.set_defaults(handler=command_validate)

    promote = subparsers.add_parser("promote", help="bundle one fully reviewed locale")
    promote.add_argument("--locale", required=True, choices=sorted(item["ios"] for item in manifest()["locales"] if not item.get("existing")))
    promote.add_argument("--dry-run", action="store_true")
    promote.set_defaults(handler=command_promote)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.handler(args))
    except (FileNotFoundError, ValueError, RuntimeError) as error:
        print("error: %s" % error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
