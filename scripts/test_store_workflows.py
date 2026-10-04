"""Offline regression tests for metadata writes and screenshot recovery."""
import importlib.util
import copy
import io
import json
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor, wait as futures_wait
from contextlib import ExitStack
from pathlib import Path
from threading import Event
from types import SimpleNamespace
from unittest.mock import Mock, patch

import app_store_screenshots as asc
import set_zh_hant_listing as listing

ROOT = Path(__file__).resolve().parents[1]
ROW = {'name': 'Prepared name', 'subtitle': 'Prepared subtitle',
       'description': 'Prepared description', 'promotionalText': 'Prepared promo'}


def resource(kind, key, **attributes):
    return {'type': kind, 'id': key, 'attributes': attributes}


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CatalogAPI(asc.API):
    def __init__(self, missing=False):
        self.writes = []
        self.infos = [] if missing else [resource('appInfoLocalizations', 'info-zh', locale='zh-Hant', name='Old')]
        self.versions = [] if missing else [resource('appStoreVersionLocalizations', 'version-zh', locale='zh-Hant', description='Old')]
        self.ambiguous = False

    def list(self, path):
        if path.endswith('/appStoreVersions'):
            return [resource('appStoreVersions', 'version', platform='IOS',
                             versionString=asc.TARGET_VERSION, appStoreState='PREPARE_FOR_SUBMISSION')]
        if path.endswith('/appInfos'):
            rows = [resource('appInfos', 'published', appStoreState='READY_FOR_SALE'),
                    resource('appInfos', 'editable', appStoreState='PREPARE_FOR_SUBMISSION')]
            return rows + [rows[-1]] if self.ambiguous else rows
        if path == '/appInfos/editable/appInfoLocalizations':
            return self.infos
        if path == '/appStoreVersions/version/appStoreVersionLocalizations':
            return self.versions
        raise AssertionError(path)

    def request(self, method, path, body=None):
        if method == 'GET':
            return {'data': resource('apps', asc.TARGET_APP, bundleId=asc.TARGET_BUNDLE)}
        self.writes.append((method, path, body))
        item = body['data']
        rows = self.infos if item['type'] == 'appInfoLocalizations' else self.versions
        if method == 'POST':
            assert path == '/' + item['type']
            item = {**item, 'id': item['type'] + '-new'}
            rows.append(item)
        else:
            assert path == '/' + item['type'] + '/' + item['id']
            item = next(x for x in rows if x['id'] == item['id'])
            item['attributes'].update(body['data']['attributes'])
        return {'data': item}


class ScreenshotBatchWorkflowTests(unittest.TestCase):
    """A completed replacement is the next operation's recovery point."""

    def uploader(self, kind):
        if kind == 'iphone':
            return asc
        previous = asc.TARGET_DISPLAY
        try:
            return load_module('ipad_batch_test', 'marketing/app-store/ipad-screenshots-2026-10-03/upload_ipad.py')
        finally:
            asc.TARGET_DISPLAY = previous

    def images(self, label, count):
        return [{'index': i + 1, 'md5': label.lower() + str(i), 'sha256': label + '-sha-' + str(i),
                 'fileSize': 100, 'width': 1, 'height': 1, 'fileName': label + str(i) + '.png'}
                for i in range(count)]

    def shots(self, label, count):
        return [resource('appScreenshots', label + str(i), sourceFileChecksum=label.lower() + str(i),
                         fileSize=100, fileName=label + str(i) + '.png', imageAsset={'width': 1, 'height': 1},
                         assetDeliveryState={'state': 'COMPLETE'}) for i in range(count)]

    def inventory(self, shots, display):
        return {'locale': 'en-US', 'localizationId': 'locale', 'sets': [{
            'set': resource('appScreenshotSets', 'set', screenshotDisplayType=display),
            'screenshots': copy.deepcopy(shots)}]}

    def run_batch(self, kind, directory, remote, images, fail_image=None, fail_reorder=False):
        uploader = self.uploader(kind)
        display = 'APP_IPHONE_65' if kind == 'iphone' else 'APP_IPAD_PRO_3GEN_129'
        args = SimpleNamespace(out_dir=directory, restore_dir=directory / 'originals',
                               run_stamp='test', processing_timeout=1)
        before = self.inventory(remote, display)
        api = Mock()
        api.request.side_effect = lambda method, path, body=None: {'data': (
            resource('appStoreVersions', 'version', appStoreState='PREPARE_FOR_SUBMISSION')
            if path.startswith('/appStoreVersions/') else
            resource('appStoreVersionLocalizations', 'locale', locale='en-US'))}

        def deliver(api, set_id, image, *unused):
            if image['index'] == fail_image:
                raise RuntimeError('delivery failed')
            existing = asc.complete_match(remote, image)
            if existing:
                return existing, 'reused'
            shot = resource('appScreenshots', image['md5'], sourceFileChecksum=image['md5'],
                            fileSize=100, fileName=image['fileName'], imageAsset={'width': 1, 'height': 1},
                            assetDeliveryState={'state': 'COMPLETE'})
            remote.append(shot)
            return shot, 'uploaded'

        def delete(api, set_id, shot_id):
            remote[:] = [shot for shot in remote if shot['id'] != shot_id]

        def reorder(api, set_id, ids):
            if fail_reorder:
                raise RuntimeError('reorder failed')
            by_id = {shot['id']: shot for shot in remote}
            remote[:] = [by_id[shot_id] for shot_id in ids]

        def restore(api, set_id, originals, *unused):
            remote[:] = copy.deepcopy(originals)
            return [shot['id'] for shot in remote]

        with ExitStack() as stack:
            stack.enter_context(patch.object(asc, 'TARGET_DISPLAY', display))
            stack.enter_context(patch.object(asc, 'make_api', return_value=api))
            ensure = stack.enter_context(patch.object(asc, 'ensure_set', return_value={'id': 'set'}))
            stack.enter_context(patch.object(asc, 'list_shots', side_effect=lambda *unused: copy.deepcopy(remote)))
            stack.enter_context(patch.object(asc, 'restoration_image'))
            stack.enter_context(patch.object(asc, 'deliver', side_effect=deliver))
            delete_mock = stack.enter_context(patch.object(asc, 'delete_shot', side_effect=delete))
            stack.enter_context(patch.object(asc, 'reorder', side_effect=reorder))
            rollback = stack.enter_context(patch.object(asc, 'rollback', side_effect=restore))
            stack.enter_context(patch.object(asc, 'say'))
            if kind == 'iphone':
                stack.enter_context(patch.object(asc, 'await_locale_verified', side_effect=lambda *unused: before))
                result = asc.process_locale({}, args, {'locale': 'en-US', 'images': images}, before, 'version')
            else:
                stack.enter_context(patch.object(uploader, 'backup_originals'))
                stack.enter_context(patch.object(uploader, 'deliver_with_consistent_metadata', side_effect=deliver))
                with ThreadPoolExecutor(max_workers=1) as pool:
                    result = uploader.process({}, {'locale': 'en-US', 'images': images}, before, 'version', args, pool)
        return result, rollback, delete_mock, ensure

    def test_success_then_first_delivery_failure_preserves_last_successful_set(self):
        for kind, count in [('iphone', 7), ('ipad', 5)]:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                out = Path(directory)
                remote = self.shots('A', count)
                result, _, _, _ = self.run_batch(kind, out, remote, self.images('B', count))
                self.assertTrue(result['verified'])
                completed = copy.deepcopy(remote)
                result, rollback, delete, _ = self.run_batch(kind, out, remote, self.images('C', count), fail_image=1)
                self.assertFalse(result['verified'])
                delete.assert_not_called()
                rollback.assert_not_called()
                # iPad workers can finish other C deliveries; every B must survive.
                self.assertEqual([shot for shot in remote if asc.checksum(shot).startswith('b')], completed)

    def test_empty_first_baseline_then_failed_replacement_recovers_last_successful_set(self):
        for kind, count in [('iphone', 7), ('ipad', 5)]:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                out = Path(directory)
                remote = []
                result, _, _, _ = self.run_batch(kind, out, remote, self.images('B', count))
                self.assertTrue(result['verified'])
                completed = copy.deepcopy(remote)
                result, rollback, _, _ = self.run_batch(kind, out, remote, self.images('C', count), fail_reorder=True)
                self.assertFalse(result['verified'])
                self.assertEqual(result['rollback'], 'verified')
                self.assertEqual(rollback.call_args.args[2], completed)
                self.assertEqual(remote, completed)

    def prepare(self, out, shots, images, **kwargs):
        return asc.prepare_screenshot_baseline(
            out / 'baseline.json', out / 'checkpoints/en-US.json',
            self.inventory(shots, asc.TARGET_DISPLAY), 'version', 'en-US', images, **kwargs)

    def test_interrupted_same_batch_keeps_original_baseline_and_batch_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            images = self.images('B', 7)
            first = self.prepare(out, self.shots('A', 7), images)
            resumed = self.prepare(out, self.shots('partial-B', 3), images)
            self.assertEqual(resumed, first)
            self.assertEqual(resumed['screenshots'], self.shots('A', 7))

    def test_interrupted_batch_rejects_changed_target_including_order_without_overwriting_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            images = self.images('B', 7)
            first = self.prepare(out, self.shots('A', 7), images)
            checkpoint = out / 'checkpoints/en-US.json'
            asc.save(checkpoint, {'locale': 'en-US', 'status': 'running', 'batchId': first['batchId']})
            saved_checkpoint = checkpoint.read_bytes()
            saved_baseline = (out / 'baseline.json').read_bytes()
            for changed in [self.images('C', 7), list(reversed(images)),
                            images[:-1] + [{**images[-1], 'fileSize': 101}]]:
                with self.subTest(changed=changed):
                    with self.assertRaisesRegex(RuntimeError, 'unfinished.*different target'):
                        self.prepare(out, self.shots('partial-B', 3), changed)
                    self.assertEqual(checkpoint.read_bytes(), saved_checkpoint)
                    self.assertEqual((out / 'baseline.json').read_bytes(), saved_baseline)

    def test_completed_live_target_without_saved_success_must_still_resume_same_batch(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            images = self.images('B', 7)
            first = self.prepare(out, self.shots('A', 7), images)
            self.assertEqual(self.prepare(out, self.shots('B', 7), images), first)
            with self.assertRaisesRegex(RuntimeError, 'unfinished.*different target'):
                self.prepare(out, self.shots('B', 7), self.images('C', 7))

    def test_read_only_preflight_selects_the_batch_recovery_point_without_changing_ledger(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            images = self.images('B', 7)
            batch = self.prepare(out, self.shots('A', 7), images)
            path = out / 'baseline.json'
            saved = path.read_bytes()
            active = self.prepare(out, self.shots('partial-B', 3), images, persist=False)
            self.assertEqual(active['screenshots'], self.shots('A', 7))
            self.assertEqual(path.read_bytes(), saved)
            asc.finish_screenshot_baseline(path, batch, 'verified')
            saved = path.read_bytes()
            next_batch = self.prepare(out, self.shots('B', 7), self.images('C', 7), persist=False)
            self.assertEqual(next_batch['screenshots'], self.shots('B', 7))
            self.assertNotEqual(next_batch['batchId'], batch['batchId'])
            self.assertEqual(path.read_bytes(), saved)

    def test_baseline_checks_all_target_identity_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            images = self.images('B', 7)
            first = self.prepare(out, self.shots('A', 7), images)
            for key in ['versionId', 'localizationId', 'display', 'locale']:
                asc.save(out / 'baseline.json', {**first, key: 'different-target'})
                with self.subTest(key=key), self.assertRaisesRegex(RuntimeError, 'different target'):
                    self.prepare(out, self.shots('A', 7), images)

    def test_legacy_success_rebases_and_ambiguous_interruption_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            original = self.shots('A', 7)
            legacy = {'versionId': 'version', 'localizationId': 'locale', 'locale': 'en-US', 'screenshots': original}
            asc.save(out / 'baseline.json', legacy)
            asc.save(out / 'checkpoints/en-US.json', {'locale': 'en-US', 'status': 'verified', 'verified': True})
            batch = self.prepare(out, self.shots('B', 7), self.images('C', 7))
            self.assertEqual(batch['screenshots'], self.shots('B', 7))
            asc.save(out / 'baseline.json', legacy)
            asc.save(out / 'checkpoints/en-US.json', {'locale': 'en-US', 'status': 'running', 'images': []})
            with self.assertRaisesRegex(RuntimeError, 'Legacy.*target.*unknown'):
                self.prepare(out, self.shots('partial-B', 3), self.images('C', 7))
            self.assertEqual(json.loads((out / 'baseline.json').read_text()), legacy)

    def test_legacy_iphone_interruption_uses_only_its_linked_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            original = self.shots('A', 7)
            images = self.images('B', 7)
            asc.save(out / 'baseline.json', {'versionId': 'version', 'localizationId': 'locale',
                                            'locale': 'en-US', 'screenshots': original})
            asc.save(out / 'checkpoints/en-US.json', {'locale': 'en-US', 'status': 'running',
                'backup': str(out / 'locale-backups/old-run-en-US.json')})
            asc.save(out / 'plan-old-run.json', {'versionId': 'version', 'display': asc.TARGET_DISPLAY,
                'locales': [{'locale': 'en-US', 'images': images}]})
            asc.save(out / 'plan-new-run.json', {'versionId': 'version', 'display': asc.TARGET_DISPLAY,
                'locales': [{'locale': 'en-US', 'images': self.images('C', 7)}]})
            with self.assertRaisesRegex(RuntimeError, 'unfinished.*different target'):
                self.prepare(out, self.shots('partial-B', 3), self.images('C', 7))
            batch = self.prepare(out, self.shots('partial-B', 3), images)
            self.assertEqual(batch['screenshots'], original)

    def test_legacy_verified_rollback_allows_new_batch_with_reconstructed_resource_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            original = self.shots('A', 7)
            restored = copy.deepcopy(original)
            for shot in restored:
                shot['id'] += '-restored'
            asc.save(out / 'baseline.json', {'versionId': 'version', 'localizationId': 'locale',
                                            'locale': 'en-US', 'screenshots': original})
            asc.save(out / 'checkpoints/en-US.json', {'locale': 'en-US', 'status': 'failed',
                'rollback': 'verified', 'restoredIds': [shot['id'] for shot in restored]})
            batch = self.prepare(out, restored, self.images('C', 7))
            self.assertEqual(batch['screenshots'], restored)

    def test_legacy_verified_rollback_rejects_missing_reordered_or_mismatched_images(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            original = self.shots('A', 7)
            bad_checksum = copy.deepcopy(original)
            bad_checksum[0]['attributes']['sourceFileChecksum'] = 'different'
            bad_size = copy.deepcopy(original)
            bad_size[0]['attributes']['imageAsset']['width'] = 2
            for current in [original[:-1], list(reversed(original)), bad_checksum, bad_size]:
                with self.subTest(current=current):
                    asc.save(out / 'baseline.json', {'versionId': 'version', 'localizationId': 'locale',
                        'locale': 'en-US', 'screenshots': original})
                    asc.save(out / 'checkpoints/en-US.json', {'locale': 'en-US', 'status': 'failed', 'rollback': 'verified'})
                    with self.assertRaisesRegex(RuntimeError, 'Legacy.*rollback.*does not match'):
                        self.prepare(out, current, self.images('C', 7))

    def test_legacy_verified_rollback_accepts_verified_apple_processed_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            restore = out / 'originals'
            restore.mkdir()
            binary = io.BytesIO()
            asc.Image.new('RGB', (1, 1), 'white').save(binary, format='PNG')
            data = binary.getvalue()
            digest = asc.hashlib.md5(data).hexdigest()
            original = self.shots('A', 1)
            original[0]['attributes']['fileSize'] = 999
            restored = copy.deepcopy(original)
            restored[0]['id'] = 'restored-processed'
            restored[0]['attributes']['sourceFileChecksum'] = digest
            restored[0]['attributes']['fileSize'] = len(data)
            (restore / 'A0.png').write_bytes(data)
            asc.save(restore / 'manifest.json', [{'id': 'A0', 'sourceFileChecksum': 'a0',
                'backupMD5': digest, 'bytes': len(data), 'sha256': asc.hashlib.sha256(data).hexdigest()}])
            asc.save(out / 'baseline.json', {'versionId': 'version', 'localizationId': 'locale',
                                            'locale': 'en-US', 'screenshots': original})
            asc.save(out / 'checkpoints/en-US.json', {'locale': 'en-US', 'status': 'failed', 'rollback': 'verified'})
            batch = self.prepare(out, restored, self.images('C', 1), recovery_dir=restore)
            self.assertEqual(batch['screenshots'], restored)

    def test_legacy_ipad_backup_requires_localization_identity_and_does_not_reset_interrupted_data(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            legacy_path = out / 'backups/en-US.json'
            original = self.inventory(self.shots('A', 5), asc.TARGET_DISPLAY)
            asc.save(legacy_path, original)
            batch = self.prepare(out, self.shots('A', 5), self.images('B', 5), legacy_backup_path=legacy_path)
            self.assertEqual(batch['screenshots'], original['sets'][0]['screenshots'])
            (out / 'baseline.json').unlink()
            asc.save(legacy_path, {key: value for key, value in original.items() if key != 'localizationId'})
            with self.assertRaisesRegex(RuntimeError, 'backup.*different target'):
                self.prepare(out, self.shots('A', 5), self.images('B', 5), legacy_backup_path=legacy_path)
            self.assertFalse((out / 'baseline.json').exists())

    def test_process_rejects_changed_target_before_mutations_and_preserves_checkpoint(self):
        for kind, count in [('iphone', 7), ('ipad', 5)]:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                out = Path(directory)
                remote = self.shots('A', count)
                self.run_batch(kind, out, remote, self.images('B', count), fail_image=1)
                checkpoint = out / 'checkpoints/en-US.json'
                saved = checkpoint.read_bytes()
                result, rollback, delete, ensure = self.run_batch(kind, out, remote, self.images('C', count), fail_image=1)
                self.assertFalse(result['verified'])
                self.assertIn('unfinished', result['error'])
                self.assertEqual(checkpoint.read_bytes(), saved)
                ensure.assert_not_called()
                rollback.assert_not_called()
                delete.assert_not_called()


class StoreWorkflowTests(unittest.TestCase):
    def test_plan_never_writes(self):
        api = CatalogAPI()
        result = listing.update_listing(api, ROW)
        self.assertFalse(result['applied'])
        self.assertEqual(api.writes, [])

    def test_existing_locale_uses_resource_patch_and_backups(self):
        api = CatalogAPI()
        with tempfile.TemporaryDirectory() as directory:
            listing.update_listing(api, ROW, apply=True, out_dir=Path(directory))
            self.assertEqual(len(list(Path(directory).glob('before-*.json'))), 1)
        self.assertEqual([x[:2] for x in api.writes], [
            ('PATCH', '/appInfoLocalizations/info-zh'),
            ('PATCH', '/appStoreVersionLocalizations/version-zh')])
        self.assertEqual(api.versions[0]['attributes']['promotionalText'], ROW['promotionalText'])

    def test_new_locale_posts_parent_relationships(self):
        api = CatalogAPI(missing=True)
        with tempfile.TemporaryDirectory() as directory:
            listing.update_listing(api, ROW, apply=True, out_dir=Path(directory))
        self.assertEqual(api.writes[0][2]['data']['relationships']['appInfo']['data']['id'], 'editable')
        self.assertEqual(api.writes[1][2]['data']['relationships']['appStoreVersion']['data']['id'], 'version')

    def test_ambiguous_editable_target_stops_before_writes(self):
        api = CatalogAPI()
        api.ambiguous = True
        with self.assertRaises(RuntimeError):
            listing.update_listing(api, ROW, apply=True, out_dir=Path('/unused'))
        self.assertEqual(api.writes, [])

    def test_unknown_post_reconciles_without_duplicate_create(self):
        api = CatalogAPI(missing=True)
        original = api.request
        def lost_response(method, path, body=None):
            response = original(method, path, body)
            if method == 'POST':
                raise asc.APIError(method, path, network=True)
            return response
        with patch.object(api, 'request', side_effect=lost_response):
            result, action = api.upsert('appInfoLocalizations', 'appInfo', 'editable',
                                        'zh-Hant', {'name': ROW['name']})
        self.assertEqual(len(api.writes), 1)
        self.assertEqual(action, 'verified-after-network-error')
        self.assertEqual(result['attributes']['name'], ROW['name'])

    def test_direct_metadata_http_503_reconciles_a_completed_post(self):
        api = asc.AuthAPI.__new__(asc.AuthAPI)
        api.session = Mock()
        failed = Mock(status_code=503, ok=False)
        failed.json.return_value = {'errors': [{'code': 'TEMPORARY_SERVER_ERROR'}]}
        created = resource('appInfoLocalizations', 'created', locale='zh-Hant', name=ROW['name'])
        fetched = Mock(status_code=200, ok=True)
        fetched.json.return_value = {'data': [created]}
        api.session.request.side_effect = [failed, fetched]
        with patch.object(api, 'authenticate'):
            result, action = api.upsert('appInfoLocalizations', 'appInfo', 'editable',
                                        'zh-Hant', {'name': ROW['name']})
        self.assertEqual(result, created)
        self.assertEqual(action, 'verified-after-network-error')
        self.assertEqual([call.args[0] for call in api.session.request.call_args_list], ['POST', 'GET'])

    def test_ipad_resume_uses_immutable_baseline_and_checks_target_identity(self):
        old_display = asc.TARGET_DISPLAY
        try:
            ipad = load_module('ipad_baseline_test', 'marketing/app-store/ipad-screenshots-2026-10-03/upload_ipad.py')
            original = [resource('appScreenshots', 'old', assetDeliveryState={'state': 'COMPLETE'})]
            before = {'locale': 'en-US', 'localizationId': 'locale', 'sets': [{
                'set': resource('appScreenshotSets', 'set', screenshotDisplayType=asc.TARGET_DISPLAY),
                'screenshots': original}]}
            resumed = {**before, 'sets': [{**before['sets'][0], 'screenshots': [
                resource('appScreenshots', 'new', assetDeliveryState={'state': 'COMPLETE'})]}]}
            images = [{'index': 1, 'md5': 'new', 'fileSize': 100, 'fileName': 'new.png'}]
            with tempfile.TemporaryDirectory() as directory:
                out = Path(directory)
                # Earlier uploader versions already saved this immutable snapshot.
                asc.save(out / 'backups/en-US.json', before)
                self.assertEqual(ipad.prepare_baseline(before, 'version', 'en-US', out, images)['screenshots'], original)
                baseline = out / 'baselines/en-US.json'
                saved = json.loads(baseline.read_text())
                self.assertEqual(ipad.prepare_baseline(resumed, 'version', 'en-US', out, images)['screenshots'], original)
                for key in ['versionId', 'localizationId', 'display', 'locale']:
                    with self.subTest(key=key):
                        asc.save(baseline, {**saved, key: 'different-target'})
                        with self.assertRaises(RuntimeError):
                            ipad.prepare_baseline(resumed, 'version', 'en-US', out, images)
                asc.save(baseline, saved)
        finally:
            asc.TARGET_DISPLAY = old_display

    def test_ipad_backup_retains_deleted_original_metadata_and_reuses_verified_files(self):
        old_display = asc.TARGET_DISPLAY
        try:
            ipad = load_module('ipad_backup_merge_test', 'marketing/app-store/ipad-screenshots-2026-10-03/upload_ipad.py')
            binary = io.BytesIO()
            ipad.Image.new('RGB', (1, 1), 'white').save(binary, format='PNG')
            data = binary.getvalue()
            old = resource('appScreenshots', 'deleted-original', fileName='old.png', fileSize=999,
                           sourceFileChecksum='source-before-apple-reencoding',
                           imageAsset={'width': 1, 'height': 1}, assetDeliveryState={'state': 'COMPLETE'})
            present = resource('appScreenshots', 'current', fileName='current.png', fileSize=len(data),
                               sourceFileChecksum=ipad.hashlib.md5(data).hexdigest(),
                               imageAsset={'width': 1, 'height': 1, 'templateUrl': 'https://example.test/{w}/{h}/{f}'},
                               assetDeliveryState={'state': 'COMPLETE'})
            saved = {'id': old['id'], 'sourceFileChecksum': asc.checksum(old),
                     'backupMD5': ipad.hashlib.md5(data).hexdigest(), 'bytes': len(data),
                     'sha256': ipad.hashlib.sha256(data).hexdigest(), 'copyType': 'processed PNG'}
            response = Mock(content=data)
            with tempfile.TemporaryDirectory() as directory, \
                    patch.object(asc, 'list_shots', return_value=[present]), \
                    patch.object(ipad.requests, 'get', return_value=response) as download:
                folder = Path(directory)
                (folder / (old['id'] + '.png')).write_bytes(data)
                asc.save(folder / 'manifest.json', [saved])
                for _ in range(2):
                    ipad.backup_originals(None, {'id': 'set'}, folder)
                records = json.loads((folder / 'manifest.json').read_text())
                self.assertEqual({row['id'] for row in records}, {old['id'], present['id']})
                self.assertEqual(next(row for row in records if row['id'] == old['id']), saved)
                self.assertEqual(asc.restoration_image(old, folder)['md5'], saved['backupMD5'])
                self.assertEqual(download.call_count, 1)
        finally:
            asc.TARGET_DISPLAY = old_display

    def test_ipad_failed_reorder_restores_reused_original_too(self):
        old_display = asc.TARGET_DISPLAY
        try:
            ipad = load_module('ipad_upload_test', 'marketing/app-store/ipad-screenshots-2026-10-03/upload_ipad.py')
            old = [resource('appScreenshots', 'old' + str(i), sourceFileChecksum='hash' + str(i),
                            assetDeliveryState={'state': 'COMPLETE'}) for i in range(5)]
            images = [{'index': i + 1, 'md5': 'hash0' if i == 0 else 'newhash' + str(i),
                       'fileSize': 100, 'fileName': 'image' + str(i)} for i in range(5)]
            new = [old[0]] + [resource('appScreenshots', 'new' + str(i)) for i in range(1, 5)]
            before = {'localizationId': 'locale', 'sets': [{'set': resource('appScreenshotSets', 'set',
                       screenshotDisplayType=asc.TARGET_DISPLAY), 'screenshots': old}]}
            api = CatalogAPI()
            api.session = type('Session', (), {'close': lambda self: None})()
            def get(method, path, body=None):
                return {'data': resource('appStoreVersions', 'version', appStoreState='PREPARE_FOR_SUBMISSION')
                        if path.startswith('/appStoreVersions/') else
                        resource('appStoreVersionLocalizations', 'locale', locale='en-US')}
            with tempfile.TemporaryDirectory() as directory, ThreadPoolExecutor(max_workers=2) as pool, \
                    patch.object(api, 'request', side_effect=get), patch.object(asc, 'make_api', return_value=api), \
                    patch.object(asc, 'ensure_set', return_value={'id': 'set'}), \
                    patch.object(asc, 'list_shots', side_effect=[old, old + new[1:]]), \
                    patch.object(ipad, 'backup_originals'), patch.object(asc, 'restoration_image'), \
                    patch.object(asc, 'delete_shot'), patch.object(asc, 'reorder', side_effect=RuntimeError('reorder failed')), \
                    patch.object(asc, 'rollback', return_value=['restored']) as rollback, \
                    patch.object(ipad, 'deliver_with_consistent_metadata', side_effect=lambda api, sid, im: (new[im['index']-1], 'reused')):
                args = type('Args', (), {'out_dir': Path(directory)})()
                result = ipad.process({}, {'locale': 'en-US', 'images': images}, before, 'version', args, pool)
                self.assertFalse(result['verified'])
                self.assertEqual(rollback.call_args.args[2], old)
                self.assertEqual(result['rollback'], 'verified')
        finally:
            asc.TARGET_DISPLAY = old_display

    def test_ipad_resumed_delivery_failure_restores_original_baseline(self):
        old_display = asc.TARGET_DISPLAY
        try:
            ipad = load_module('ipad_resumed_rollback_test', 'marketing/app-store/ipad-screenshots-2026-10-03/upload_ipad.py')
            original = [resource('appScreenshots', 'old' + str(i), sourceFileChecksum='hash' + str(i),
                                 assetDeliveryState={'state': 'COMPLETE'}) for i in range(5)]
            current = [original[0], resource('appScreenshots', 'new1', sourceFileChecksum='newhash1',
                       assetDeliveryState={'state': 'COMPLETE'})] + original[2:]
            before = {'locale': 'en-US', 'localizationId': 'locale', 'sets': [{
                'set': resource('appScreenshotSets', 'set', screenshotDisplayType=asc.TARGET_DISPLAY),
                'screenshots': original}]}
            resumed = {**before, 'sets': [{**before['sets'][0], 'screenshots': current}]}
            images = [{'index': i + 1, 'md5': 'hash0' if i == 0 else 'newhash' + str(i),
                       'fileSize': 100, 'fileName': 'image' + str(i)} for i in range(5)]
            api = CatalogAPI()
            api.session = Mock()
            def get(method, path, body=None):
                return {'data': resource('appStoreVersions', 'version', appStoreState='PREPARE_FOR_SUBMISSION')
                        if path.startswith('/appStoreVersions/') else
                        resource('appStoreVersionLocalizations', 'locale', locale='en-US')}
            with tempfile.TemporaryDirectory() as directory, ThreadPoolExecutor(max_workers=2) as pool, \
                    patch.object(api, 'request', side_effect=get), patch.object(asc, 'make_api', return_value=api), \
                    patch.object(asc, 'ensure_set', return_value={'id': 'set'}), \
                    patch.object(asc, 'list_shots', return_value=current), \
                    patch.object(ipad, 'backup_originals'), patch.object(asc, 'restoration_image'), \
                    patch.object(asc, 'delete_shot') as delete, \
                    patch.object(asc, 'rollback', return_value=['restored']) as rollback, \
                    patch.object(ipad, 'deliver_with_consistent_metadata', side_effect=RuntimeError('delivery failed')):
                args = type('Args', (), {'out_dir': Path(directory)})()
                ipad.prepare_baseline(before, 'version', 'en-US', args.out_dir, images)
                result = ipad.process({}, {'locale': 'en-US', 'images': images}, resumed, 'version', args, pool)
                self.assertFalse(result['verified'])
                self.assertEqual(result['rollback'], 'verified')
                self.assertEqual(rollback.call_args.args[2], original)
                delete.assert_not_called()
        finally:
            asc.TARGET_DISPLAY = old_display

    def test_ipad_rollback_waits_for_other_workers_and_keeps_shared_pool_open(self):
        old_display = asc.TARGET_DISPLAY
        try:
            ipad = load_module('ipad_worker_rollback_test', 'marketing/app-store/ipad-screenshots-2026-10-03/upload_ipad.py')
            original = [resource('appScreenshots', 'old' + str(i), sourceFileChecksum='hash' + str(i),
                                 assetDeliveryState={'state': 'COMPLETE'}) for i in range(5)]
            current = [resource('appScreenshots', 'partial', sourceFileChecksum='partial',
                                assetDeliveryState={'state': 'COMPLETE'})]
            before = {'locale': 'en-US', 'localizationId': 'locale', 'sets': [{
                'set': resource('appScreenshotSets', 'set', screenshotDisplayType=asc.TARGET_DISPLAY),
                'screenshots': original}]}
            resumed = {**before, 'sets': [{**before['sets'][0], 'screenshots': current}]}
            images = [{'index': i + 1, 'md5': 'wanted' + str(i),
                       'fileSize': 100, 'fileName': 'image' + str(i)} for i in range(5)]
            started, release, finished = Event(), Event(), Event()
            tracked = []
            def delivery(api, set_id, image):
                if image['index'] == 1:
                    if not started.wait(2):
                        raise RuntimeError('Concurrent worker never started')
                    raise RuntimeError('First delivery failed')
                if image['index'] == 2:
                    started.set()
                if not release.wait(2):
                    raise RuntimeError('Concurrent worker was not released')
                if image['index'] == 2:
                    finished.set()
                return resource('appScreenshots', 'new' + str(image['index'])), 'uploaded'
            def settle(futures):
                tracked.extend(futures)
                self.assertTrue(started.is_set())
                self.assertFalse(finished.is_set())
                release.set()
                return futures_wait(futures)
            def rollback(*args):
                self.assertTrue(finished.is_set())
                self.assertTrue(tracked and all(future.done() for future in tracked))
                return ['restored']
            api = CatalogAPI()
            api.session = Mock()
            def get(method, path, body=None):
                return {'data': resource('appStoreVersions', 'version', appStoreState='PREPARE_FOR_SUBMISSION')
                        if path.startswith('/appStoreVersions/') else
                        resource('appStoreVersionLocalizations', 'locale', locale='en-US')}
            with tempfile.TemporaryDirectory() as directory, ThreadPoolExecutor(max_workers=2) as pool, \
                    patch.object(api, 'request', side_effect=get), patch.object(asc, 'make_api', return_value=api), \
                    patch.object(asc, 'ensure_set', return_value={'id': 'set'}), \
                    patch.object(asc, 'list_shots', return_value=current), \
                    patch.object(ipad, 'backup_originals'), patch.object(asc, 'restoration_image'), \
                    patch.object(ipad, 'deliver_with_consistent_metadata', side_effect=delivery), \
                    patch.object(ipad, 'wait', side_effect=settle) as settled, \
                    patch.object(asc, 'rollback', side_effect=rollback):
                args = type('Args', (), {'out_dir': Path(directory)})()
                ipad.prepare_baseline(before, 'version', 'en-US', args.out_dir, images)
                result = ipad.process({}, {'locale': 'en-US', 'images': images}, resumed, 'version', args, pool)
                self.assertEqual(result['rollback'], 'verified')
                settled.assert_called_once()
                self.assertEqual(pool.submit(lambda: 'still usable').result(), 'still usable')
        finally:
            asc.TARGET_DISPLAY = old_display

    def test_iphone_resumed_early_failure_rolls_back_prior_deleted_originals(self):
        original = [resource('appScreenshots', 'original', sourceFileChecksum='old',
                             assetDeliveryState={'state': 'COMPLETE'})]
        current = [resource('appScreenshots', 'partial', sourceFileChecksum='partial',
                            assetDeliveryState={'state': 'COMPLETE'})]
        api = CatalogAPI()
        api.session = Mock()
        def get(method, path, body=None):
            return {'data': resource('appStoreVersions', 'version', appStoreState='PREPARE_FOR_SUBMISSION')
                    if path.startswith('/appStoreVersions/') else
                    resource('appStoreVersionLocalizations', 'locale', locale='en-US')}
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(asc, 'TARGET_DISPLAY', 'APP_IPHONE_65'), \
                patch.object(api, 'request', side_effect=get), patch.object(asc, 'make_api', return_value=api), \
                patch.object(asc, 'ensure_set', return_value={'id': 'set'}), \
                patch.object(asc, 'list_shots', return_value=current), \
                patch.object(asc, 'deliver', side_effect=RuntimeError('delivery failed')), \
                patch.object(asc, 'delete_shot') as delete, \
                patch.object(asc, 'rollback', return_value=['restored']) as rollback:
            root = Path(directory)
            before = {'localizationId': 'locale', 'sets': [{
                'set': resource('appScreenshotSets', 'set', screenshotDisplayType=asc.TARGET_DISPLAY),
                'screenshots': current}]}
            args = type('Args', (), {'out_dir': root, 'restore_dir': root / 'originals',
                                    'run_stamp': 'test', 'processing_timeout': 1})()
            row = {'locale': 'en-US', 'images': [{'index': 1, 'md5': 'wanted', 'fileSize': 100, 'fileName': 'wanted.png'}]}
            first = {**before, 'sets': [{**before['sets'][0], 'screenshots': original}]}
            asc.prepare_screenshot_baseline(root / 'locale-backups/baseline-en-US.json',
                root / 'checkpoints/en-US.json', first, 'version', 'en-US', row['images'])
            result = asc.process_locale({}, args, row, before, 'version')
            self.assertFalse(result['verified'])
            self.assertEqual(result['rollback'], 'verified')
            self.assertEqual(rollback.call_args.args[2], original)
            delete.assert_not_called()

    def test_capture_resume_rejects_changed_names(self):
        capture = load_module('ipad_capture_test', 'marketing/app-store/ipad-screenshots-2026-10-03/capture_ipad.py')
        entry = {'locale': 'en-US', 'appleLanguage': 'en', 'appleLocale': 'en_US',
                 'names': ['A', 'B'], 'basketballTeams': ['Home', 'Away']}
        self.assertTrue(capture.matches_configuration(entry, entry))
        self.assertFalse(capture.matches_configuration({**entry, 'names': ['C', 'D']}, entry))

    def test_capture_resume_finalizes_all_49_locales(self):
        capture = load_module('ipad_capture_count_test', 'marketing/app-store/ipad-screenshots-2026-10-03/capture_ipad.py')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / 'captures').mkdir()
            image = root / 'test.png'
            image.write_bytes(b'fixture bytes')
            digest = capture.hashlib.sha256(image.read_bytes()).hexdigest()
            entries = [{'locale': str(i), 'appleLanguage': 'en', 'appleLocale': 'en_US',
                        'names': ['A', 'B'], 'basketballTeams': ['Home', 'Away']} for i in range(49)]
            (root / 'capture-config.json').write_text(json.dumps({'localizations': entries}))
            for entry in entries:
                row = {**entry, 'cards': [{'scene': scene, 'file': 'test.png', 'sha256': digest} for scene in capture.SCENES]}
                (root / 'captures' / (entry['locale'] + '.json')).write_text(json.dumps(row))
            with patch.object(capture, 'HERE', root), patch.object(sys, 'argv', ['capture', '--resume']), \
                    patch.object(capture, 'capture', side_effect=AssertionError('resume should reuse verified files')), patch('builtins.print'):
                capture.main()
            manifest = json.loads((root / 'export-manifest.json').read_text())
            self.assertEqual((manifest['localeCount'], manifest['screenshotCount']), (49, 245))
            self.assertEqual(manifest['excludedLocales'], ['zh-Hans'])


if __name__ == '__main__':
    unittest.main()
