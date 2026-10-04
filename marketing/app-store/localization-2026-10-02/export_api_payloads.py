#!/usr/bin/env python3
"""Export offline App Store Connect POST/PATCH payloads. Never makes network calls."""
import argparse
import json
from pathlib import Path
from validate import ROOT, check, load_localizations, read_json

BASE = 'https://api.appstoreconnect.apple.com/v1'

def resource_request(kind, attributes, parent_kind, parent_id, existing_id=None):
    if existing_id:
        return {'method':'PATCH','url':f'{BASE}/{kind}/{existing_id}','body':{'data':{'type':kind,'id':existing_id,'attributes':attributes}}}
    return {'method':'POST','url':f'{BASE}/{kind}','body':{'data':{'type':kind,'attributes':attributes,'relationships':{parent_kind:{'data':{'type':{'appInfo':'appInfos','appStoreVersion':'appStoreVersions'}[parent_kind],'id':parent_id}}}}}}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-info-id', default='<APP_INFO_ID>')
    parser.add_argument('--version-id', default='<APP_STORE_VERSION_ID>')
    parser.add_argument('--existing-ids', type=Path, help='JSON with locale→resource ID maps for appInfoLocalizations and appStoreVersionLocalizations')
    parser.add_argument('--locale', action='append', help='Export selected ASC locales; repeat to select several')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    entries = load_localizations()
    errors = check(entries)
    if errors:
        parser.error('; '.join(errors))
    locales = {r['locale'] for r in entries}
    if args.locale:
        unknown = set(args.locale) - locales
        if unknown:
            parser.error(f'Unknown store locale(s): {sorted(unknown)}')
        entries = [r for r in entries if r['locale'] in args.locale]
    existing = read_json(args.existing_ids) if args.existing_ids else {}
    for kind, values in existing.items():
        if kind not in ['appInfoLocalizations','appStoreVersionLocalizations'] or not isinstance(values, dict):
            parser.error('existing-ids must contain only resource-kind keys with locale→ID objects')
        if set(values) - locales or any(not isinstance(v, str) or not v.strip() for v in values.values()):
            parser.error(f'{kind}: unrecognized locale or empty/non-string resource ID')
    requests = []
    for r in entries:
        code = r['locale']
        info_id = existing.get('appInfoLocalizations', {}).get(code)
        version_id = existing.get('appStoreVersionLocalizations', {}).get(code)
        info_attributes = {k:r[k] for k in ['name','subtitle']}
        version_attributes = {'description':r['description']}
        if not info_id:
            info_attributes = {'locale':code,**info_attributes}
        if not version_id:
            version_attributes = {'locale':code,**version_attributes}
        requests += [
            {'locale':code,'scope':'name-and-subtitle',**resource_request('appInfoLocalizations',info_attributes,'appInfo',args.app_info_id,info_id)},
            {'locale':code,'scope':'description',**resource_request('appStoreVersionLocalizations',version_attributes,'appStoreVersion',args.version_id,version_id)},
        ]
    result = {'schemaVersion':1,'mode':'offline-request-plan','uploaded':False,'source':'locales/*.json','notes':[
        'This file wraps requests. Send each body individually to its method/url, not the entire plan.',
        'Replace placeholder parent IDs with the editable AppInfo and AppStoreVersion IDs, not the app Apple ID.',
        'Read existing resource IDs first and pass --existing-ids to PATCH those locales; do not POST duplicates.',
        'Bodies contain only the requested fields. Preserve existing URLs, keywords, promotionalText and whatsNew.',
        'For newly added locales, supply required supportUrl, keywords, privacy policy and release notes as appropriate before submission.',
        'Check live appInfo/version localization sets, editable state and name availability before applying.',
        'Screenshot titles are input for image rendering; the API uploads screenshot images, not title strings.',
    ],'requests':requests}
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(f'Exported {len(requests)} offline request payloads for {len(entries)} locales to {args.out}; nothing uploaded.')

if __name__ == '__main__':
    main()
