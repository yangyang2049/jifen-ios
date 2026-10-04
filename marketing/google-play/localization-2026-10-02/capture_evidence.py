"""Bind successful native captures to the exact PNG/XML bytes used downstream."""
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET
from PIL import Image

SCHEMA_VERSION = 1
SOURCE_FILES = tuple(card + extension for card in ('04', '04-trend', '05') for extension in ('.png', '.xml'))
LABEL_KEYS = ('tab_score', 'tab_records', 'tab_badminton', 'cancel', 'record_detail_score_trend')


class CaptureEvidenceError(ValueError):
    pass


def invalidate_capture(folder):
    """A new attempt must never leave the preceding attempt's success marker usable."""
    (folder / 'verification.json').unlink(missing_ok=True)


def _identity(report, locale, names, labels):
    if report.get('status') != 'verified' or report.get('locale') != locale:
        raise CaptureEvidenceError(locale + ': capture not verified for this locale')
    if report.get('names') != names:
        raise CaptureEvidenceError(locale + ': capture names differ from current copy')
    if any(report.get('labels', {}).get(key) != labels.get(key) or not labels.get(key) for key in LABEL_KEYS):
        raise CaptureEvidenceError(locale + ': capture labels differ from current resources')
    if not locale.startswith('en-') and labels['record_detail_score_trend'] == 'Score trend':
        raise CaptureEvidenceError(locale + ': English trend fallback')


def source_manifest(folder, names, labels):
    manifest = {}
    for filename in SOURCE_FILES:
        path = folder / filename
        if not path.is_file():
            raise CaptureEvidenceError(str(path) + ': capture source missing')
        data = path.read_bytes()
        if path.suffix == '.png':
            with Image.open(path) as image:
                image.load()
                if image.size != (1080, 1920):
                    raise CaptureEvidenceError(str(path) + ': unexpected capture dimensions')
        else:
            texts = [node.get('text', '') for node in ET.fromstring(data).iter('node')]
            if not all(any(name in text for text in texts) for name in names):
                raise CaptureEvidenceError(str(path) + ': localized names missing')
            if any(text in ('Sam', 'Steven', 'Stevenx') for text in texts):
                raise CaptureEvidenceError(str(path) + ': English demo names left')
            label = labels['cancel' if path.stem == '05' else 'record_detail_score_trend']
            if label not in texts:
                raise CaptureEvidenceError(str(path) + ': native UI label missing')
        manifest[filename] = {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}
    return manifest


def seal_capture_report(folder, report, locale, names, labels):
    _identity(report, locale, names, labels)
    return dict(report, schemaVersion=SCHEMA_VERSION, sources=source_manifest(folder, names, labels))


def write_capture_report(folder, report):
    # A crash before replacement leaves no success marker for a fresh attempt.
    target = folder / 'verification.json'
    temporary = folder / 'verification.json.tmp'
    temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(target)


def validate_capture_report(folder, locale, names, labels):
    report = json.loads((folder / 'verification.json').read_text())
    _identity(report, locale, names, labels)
    if report.get('schemaVersion') != SCHEMA_VERSION or set(report.get('sources', {})) != set(SOURCE_FILES):
        raise CaptureEvidenceError(locale + ': capture evidence lacks source hashes; use explicit --upgrade-evidence with a trusted inventory')
    actual = source_manifest(folder, names, labels)
    for filename, expected in report['sources'].items():
        if expected != actual[filename]:
            raise CaptureEvidenceError(locale + ': capture source changed: ' + filename)
    return report


def prepare_legacy_upgrade(folder, locale, names, labels, inventory, repository):
    """Only a pre-existing audit snapshot can authorize legacy metadata migration."""
    report = json.loads((folder / 'verification.json').read_text())
    if 'schemaVersion' in report or 'sources' in report:
        return validate_capture_report(folder, locale, names, labels), False
    sealed = seal_capture_report(folder, report, locale, names, labels)
    for filename, actual in sealed['sources'].items():
        key = (folder / filename).relative_to(repository).as_posix()
        expected = inventory.get(key)
        if expected is None or expected.get('sha256') != actual['sha256'] or expected.get('bytes') != actual['bytes']:
            raise CaptureEvidenceError(locale + ': trusted inventory missing or changed source: ' + key)
    sealed['evidenceOrigin'] = 'legacy-offline-inventory-upgrade'
    return sealed, True


def upgrade_evidence(root, locales, copy, labels, inventory_path, backup_directory):
    repository = root.parents[2]
    entries = json.loads(inventory_path.read_text())
    inventory = {entry['file']: entry for entry in entries}
    pending = []
    # Validate the complete batch before backing up or changing any metadata.
    for locale in locales:
        folder = root / 'captures' / locale
        names = [copy[locale]['playerNames'][key] for key in ('score', 'catalog')]
        report, changed = prepare_legacy_upgrade(folder, locale, names, labels[locale], inventory, repository)
        if changed:
            report['auditInventorySha256'] = hashlib.sha256(inventory_path.read_bytes()).hexdigest()
            pending.append((folder, report))
    for folder, report in pending:
        original = folder / 'verification.json'
        backup = backup_directory / original.relative_to(repository)
        backup.parent.mkdir(parents=True, exist_ok=True)
        if backup.exists():
            if backup.read_bytes() != original.read_bytes():
                raise CaptureEvidenceError(str(backup) + ': backup already exists with different contents')
        else:
            shutil.copy2(original, backup)
    for folder, report in pending:
        write_capture_report(folder, report)
    return len(pending)
