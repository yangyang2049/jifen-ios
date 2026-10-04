#!/usr/bin/env python3
"""Plan, apply, and verify store metadata through Apple's public API.

Private keys are read from --key-file and JWTs stay in memory. No build, review
submission, release, screenshot upload, or deletion endpoints are called.
"""
import argparse
import base64
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

BASE = 'https://api.appstoreconnect.apple.com/v1'
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'}

class APIRequestError(RuntimeError):
    def __init__(self, message, status):
        self.status = status
        super().__init__(message)

def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

def encode(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=')

class API:
    def __init__(self, key_file, key_id, issuer):
        self.key = serialization.load_pem_private_key(key_file.read_bytes(), password=None)
        self.key_id, self.issuer = key_id, issuer
        self.session = requests.Session()
        self.expires = 0

    def authenticate(self):
        now = int(time.time())
        if now < self.expires - 60:
            return
        header = {'alg':'ES256', 'kid':self.key_id, 'typ':'JWT'}
        payload = {'iat':now-15, 'exp':now+600, 'aud':'appstoreconnect-v1'}
        payload.update({'iss':self.issuer} if self.issuer else {'sub':'user'})
        data = b'.'.join(encode(json.dumps(x, separators=(',',':')).encode()) for x in [header, payload])
        r, s = decode_dss_signature(self.key.sign(data, ec.ECDSA(hashes.SHA256())))
        signature = encode(r.to_bytes(32,'big') + s.to_bytes(32,'big'))
        self.session.headers['Authorization'] = 'Bearer ' + (data+b'.'+signature).decode()
        self.expires = payload['exp']

    def request(self, method, url, body=None):
        url = url if url.startswith('https://') else BASE + url
        if not url.startswith(BASE + '/'):
            raise ValueError('Refusing to send credentials outside the App Store Connect API')
        self.authenticate()
        for attempt in range(4):
            # Do not follow redirects carrying credential headers to an unexpected endpoint.
            response = self.session.request(method, url, json=body, timeout=40, allow_redirects=False)
            if response.status_code == 429 and attempt < 3:
                try:
                    delay = min(30, max(1, int(response.headers.get('Retry-After', 2 ** attempt))))
                except ValueError:
                    delay = 2 ** attempt
                time.sleep(delay)
                continue
            if not response.ok:
                try:
                    details = [{'code':x.get('code'),'detail':x.get('detail'),'source':x.get('source')} for x in response.json().get('errors', [])]
                except ValueError:
                    details = [{'detail':'Response was not JSON'}]
                raise APIRequestError(f'{method} {url}: HTTP {response.status_code}: {json.dumps(details,ensure_ascii=False)}',
                                      response.status_code)
            if response.status_code == 204:
                return {}
            return response.json()
        raise RuntimeError('Rate limit retries exhausted')

    def list(self, path):
        url = path + ('&' if '?' in path else '?') + 'limit=200'
        result = []
        while url:
            page = self.request('GET', url)
            result.extend(page['data'])
            url = page.get('links', {}).get('next')
        return result

    def upsert(self, kind, parent_kind, parent_id, locale, fields, existing=None):
        expected = dict(fields)
        if existing and all(existing['attributes'].get(k) == v for k, v in expected.items()):
            return existing, 'unchanged'
        # Reconcile a write with an unknown outcome before retrying a POST.
        for attempt in range(3):
            if existing:
                method, path = 'PATCH', f'/{kind}/{existing["id"]}'
                body = {'data':{'type':kind,'id':existing['id'],'attributes':expected}}
            else:
                method, path = 'POST', f'/{kind}'
                parent_type = {'appInfo':'appInfos','appStoreVersion':'appStoreVersions'}[parent_kind]
                body = {'data':{'type':kind,'attributes':{'locale':locale,**expected},'relationships':{parent_kind:{'data':{'type':parent_type,'id':parent_id}}}}}
            try:
                return self.request(method,path,body)['data'], method
            except (requests.RequestException, RuntimeError) as error:
                # Apple may automatically create the counterpart localization when
                # the first resource is added. Reconcile locale conflicts as well.
                duplicate = ('ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE' in str(error)
                             and '/data/attributes/locale' in str(error))
                # Sanitized API errors retain status/codes, not server detail.
                # Reconcile uncertain writes through GET before retrying POST.
                status = getattr(error, 'status', None)
                uncertain = (getattr(error, 'network', False) or status in (409, 429)
                             or (status is not None and status >= 500))
                if isinstance(error, RuntimeError) and not (duplicate or uncertain):
                    raise
                if attempt == 2:
                    raise
                parent_type = {'appInfo':'appInfos','appStoreVersion':'appStoreVersions'}[parent_kind]
                current = self.list(f'/{parent_type}/{parent_id}/{kind}')
                existing = next((x for x in current if x['attributes']['locale'] == locale), None)
                if existing and all(existing['attributes'].get(k) == v for k,v in expected.items()):
                    return existing, 'verified-after-network-error'
        raise RuntimeError('Write retries exhausted')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata-dir', type=Path, required=True)
    parser.add_argument('--app-id', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--expected-bundle-id', required=True)
    parser.add_argument('--key-file', type=Path, required=True)
    parser.add_argument('--key-id', required=True)
    parser.add_argument('--issuer-id', help='Omit for an individual API key')
    parser.add_argument('--out-dir', type=Path, required=True)
    parser.add_argument('--apply', action='store_true', help='Apply the metadata; default is read-only planning')
    args = parser.parse_args()
    sys.path.insert(0, str(args.metadata_dir.resolve()))
    from validate import check, load_localizations
    localizations = load_localizations()
    errors = check(localizations)
    if errors:
        parser.error('; '.join(errors))
    api = API(args.key_file, args.key_id, args.issuer_id)
    app = api.request('GET', f'/apps/{args.app_id}')['data']
    if app['attributes']['bundleId'] != args.expected_bundle_id:
        parser.error('The live app bundle ID does not match the requested target')
    versions = api.list(f'/apps/{args.app_id}/appStoreVersions')
    version = next((r for r in versions if r['attributes'].get('platform') == 'IOS' and r['attributes'].get('versionString') == args.version), None)
    if not version or version['attributes'].get('appStoreState') not in EDITABLE:
        parser.error(f'iOS {args.version} does not exist in an editable state; no metadata was changed')
    infos = api.list(f'/apps/{args.app_id}/appInfos')
    editable = [r for r in infos if r['attributes'].get('appStoreState') in EDITABLE]
    if len(editable) != 1:
        parser.error(f'Expected one editable AppInfo, found {len(editable)}; no metadata was changed')
    info = editable[0]
    info_path = f'/appInfos/{info["id"]}/appInfoLocalizations'
    version_path = f'/appStoreVersions/{version["id"]}/appStoreVersionLocalizations'
    info_before, version_before = api.list(info_path), api.list(version_path)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    # Append rather than overwrite each backup, including when rerunning a partial upload.
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    snapshot = {'app':app,'appInfo':info,'appStoreVersion':version,'appInfoLocalizations':info_before,'appStoreVersionLocalizations':version_before}
    backup_name = f'before-{stamp}.json'
    write_json(args.out_dir/backup_name, snapshot)
    info_map = {r['attributes']['locale']:r for r in info_before}
    version_map = {r['attributes']['locale']:r for r in version_before}
    primary = app['attributes']['primaryLocale']
    primary_info = info_map.get(primary, next(iter(info_map.values()), None))
    primary_version = version_map.get(primary, next(iter(version_map.values()), None))
    plan = {'appId':args.app_id,'bundleId':args.expected_bundle_id,'version':args.version,'appInfoId':info['id'],'appStoreVersionId':version['id'],'backup':backup_name,'apply':args.apply,'locales':[]}
    for row in localizations:
        code = row['locale']
        item = {'locale':code,'appInfoAction':'PATCH' if code in info_map else 'POST','versionAction':'PATCH' if code in version_map else 'POST','name':row['name'],'subtitle':row['subtitle'],'description':row['description']}
        plan['locales'].append(item)
    write_json(args.out_dir/f'plan-{stamp}.json', plan)
    print(f'Target: {app["attributes"]["name"]} / {args.expected_bundle_id} / iOS {args.version}; {len(localizations)} locales.', flush=True)
    print(f'Before: {len(info_map)} name localizations, {len(version_map)} version localizations. Backup: {backup_name}', flush=True)
    if not args.apply:
        print('Read-only plan saved; no metadata changed.', flush=True)
        return 0
    results = []
    report = {'appId':args.app_id,'version':args.version,'appInfoId':info['id'],'appStoreVersionId':version['id'],'startedAt':stamp,'backup':backup_name,'results':results,'submittedForReview':False,'released':False,'screenshotUpload':False}
    for index, row in enumerate(localizations, start=1):
        code = row['locale']
        result = {'locale':code,'nameAndSubtitle':'pending','description':'pending'}
        try:
            fields = {k:row[k] for k in ['name','subtitle']}
            if code not in info_map and primary_info:
                for field in ['privacyPolicyUrl', 'privacyChoicesUrl']:
                    value = primary_info['attributes'].get(field)
                    if value:
                        fields[field] = value
            resource, action = api.upsert('appInfoLocalizations','appInfo',info['id'],code,fields,info_map.get(code))
            info_map[code] = resource
            result['nameAndSubtitle'] = action
            if action == 'POST':
                # Current Apple behavior mirrors new AppInfo locales into the
                # version. Read their IDs before choosing POST versus PATCH.
                version_map.update({r['attributes']['locale']:r for r in api.list(version_path)})
            fields = {'description':row['description']}
            if primary_version:
                for field in ['supportUrl', 'marketingUrl']:
                    value = primary_version['attributes'].get(field)
                    if value and not version_map.get(code,{}).get('attributes',{}).get(field):
                        fields[field] = value
            result['filledVersionUrls'] = {k:v for k,v in fields.items() if k != 'description'}
            resource, action = api.upsert('appStoreVersionLocalizations','appStoreVersion',version['id'],code,fields,version_map.get(code))
            version_map[code] = resource
            result['description'] = action
        except (RuntimeError, requests.RequestException) as error:
            result['error'] = str(error)
        results.append(result)
        write_json(args.out_dir/'upload-report.json',report)
        print(f'{index:02d}/{len(localizations)} {code}: name={result["nameAndSubtitle"]}, description={result["description"]}' + (f' ERROR: {result["error"]}' if 'error' in result else ''), flush=True)
    info_after, version_after = api.list(info_path), api.list(version_path)
    write_json(args.out_dir/'after.json',{'appInfoLocalizations':info_after,'appStoreVersionLocalizations':version_after})
    info_after = {r['attributes']['locale']:r for r in info_after}
    version_after = {r['attributes']['locale']:r for r in version_after}
    mismatches = []
    for row in localizations:
        code = row['locale']
        for kind, fields, records in [('appInfoLocalizations',['name','subtitle'],info_after),('appStoreVersionLocalizations',['description'],version_after)]:
            for field in fields:
                actual = records.get(code,{}).get('attributes',{}).get(field)
                if actual != row[field]:
                    mismatches.append({'locale':code,'kind':kind,'field':field})
    preserved_errors = []
    intentional_url_fills = {r['locale']:r.get('filledVersionUrls',{}) for r in results}
    for kind, records, updated, changed in [('appInfoLocalizations',info_before,info_after,{'name','subtitle'}),('appStoreVersionLocalizations',version_before,version_after,{'description'})]:
        for before in records:
            code = before['attributes']['locale']
            for field,value in before['attributes'].items():
                if field in changed:
                    continue
                if kind == 'appStoreVersionLocalizations' and not value:
                    # Missing URLs on Apple's automatically created locales are
                    # explicitly filled from the primary localization above.
                    expected_url = intentional_url_fills.get(code,{}).get(field)
                    if expected_url and updated.get(code,{}).get('attributes',{}).get(field) == expected_url:
                        continue
                if updated.get(code,{}).get('attributes',{}).get(field) != value:
                    preserved_errors.append({'locale':code,'kind':kind,'field':field})
    report.update({'verified':not mismatches and not preserved_errors,'mismatches':mismatches,'unexpectedFieldChanges':preserved_errors,'appInfoLocaleCount':len(info_after),'versionLocaleCount':len(version_after),'localeSetsEqual':set(info_after)==set(version_after),'completedAt':datetime.now(timezone.utc).isoformat()})
    write_json(args.out_dir/'upload-report.json',report)
    print(f'Verification: {"PASS" if report["verified"] else "FAIL"}; {len(mismatches)} text mismatches, {len(preserved_errors)} unexpected changes; locale counts {len(info_after)}/{len(version_after)}.', flush=True)
    return 0 if report['verified'] else 1

if __name__ == '__main__':
    sys.exit(main())
