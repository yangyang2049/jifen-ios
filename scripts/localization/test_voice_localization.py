import json
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout
import io
import tempfile
from pathlib import Path
import voice_localization as voice
import sync_reviewed_voice_catalogs as exporter

class SportsVoicePipelineTests(unittest.TestCase):
    def test_reachable_semantic_announcements_do_not_use_english_inventory(self):
        packs = json.loads(voice.PACKS.read_text())
        for locale in ['fr', 'fr-CA', 'es-ES', 'es-MX', 'pt-BR', 'pt-PT']:
            native = voice.native_table(packs[locale])
            for key in ['squash.game.to', 'squash.match.to', 'squash.leads', 'squash.games.all',
                        'squash.game.ball', 'squash.match.ball']:
                self.assertNotEqual(native[key], voice.DOCUMENTED_CALLS[key], (locale, key))
        for locale in ['zh-Hans', 'zh-Hant', 'ko']:
            self.assertNotEqual(voice.native_table(packs[locale])['tennis.deciding.point'], voice.DOCUMENTED_CALLS['tennis.deciding.point'])
        self.assertEqual(voice.native_table(packs['ko'])['pingpong.score.all'], '%1$@ 대 %1$@')

    def test_missing_catalog_and_unknown_locale_block_promotion(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(voice,'CATALOG_ROOT',Path(folder)), redirect_stdout(io.StringIO()):
            self.assertEqual(voice.main(['promote','--dry-run']),1)
        with redirect_stdout(io.StringIO()):
            self.assertEqual(voice.main(['promote','--locale','ur','--dry-run']),1)
            self.assertEqual(voice.main(['promote','--locale','unknown','--dry-run']),1)

    def test_promoted_resources_match_reviewed_catalogs(self):
        with redirect_stdout(io.StringIO()):
            self.assertEqual(voice.main(['validate']),0)
    def test_all_46_catalogs_are_fresh_and_match_native_frames(self):
        sources=voice.source_table()
        packs=json.loads(voice.PACKS.read_text())
        paths=list(voice.CATALOG_ROOT.glob('*.json'))
        self.assertEqual(len(paths),46)
        self.assertEqual({p.stem for p in paths},set(packs))
        self.assertNotIn('ur',packs)
        for path in paths:
            sources=voice.source_table(path.stem)
            rows=json.loads(path.read_text())['entries']
            self.assertEqual(voice.validate(path.stem,sources,rows),[])
            expected=sources if path.stem=='en' else voice.native_table(packs[path.stem])
            self.assertEqual({key:row['value'] for key,row in rows.items()},expected)
    def test_rejects_dropped_parameters_stale_sources_and_unreviewed_values(self):
        sources={'call':'Advantage %1$@'}
        good={'call':{'source_hash':voice.digest(sources['call']),'status':'reviewed','value':'Avantage %1$@'}}
        self.assertEqual(voice.validate('fr',sources,good),[])
        for key,value in [('value','Avantage'),('source_hash','stale'),('status','machine')]:
            bad={'call':dict(good['call'],**{key:value})}
            self.assertTrue(voice.validate('fr',sources,bad))
    def test_region_resources_are_independent_and_use_local_terms(self):
        packs=json.loads(voice.PACKS.read_text())
        self.assertNotEqual(voice.native_table(packs['fr']),voice.native_table(packs['fr-CA']))
        self.assertNotEqual(voice.native_table(packs['es-ES']),voice.native_table(packs['es-MX']))
        self.assertNotEqual(voice.native_table(packs['pt-PT']),voice.native_table(packs['pt-BR']))
        self.assertEqual(voice.native_table(packs['pt-PT'])['match point'],'Ponto para vencer o encontro')
    def test_rejects_unsafe_printf_and_accepts_repeated_positional_arguments(self):
        sources={'call':'%1$@-all'}
        row={'source_hash':voice.digest(sources['call']),'status':'reviewed','value':'%1$@ 대 %1$@'}
        self.assertEqual(voice.validate('ko',sources,{'call':row}),[])
        row['value']='%1$@ %n'
        self.assertTrue(voice.validate('ko',sources,{'call':row}))

    def test_cross_platform_export_rejects_stale_and_unsafe_reviewed_rows(self):
        original = json.loads((voice.CATALOG_ROOT / 'en.json').read_text())
        with tempfile.TemporaryDirectory() as folder, patch.object(exporter, 'CATALOGS', Path(folder)):
            target = Path(folder) / 'en.json'
            target.write_text(json.dumps(original))
            self.assertEqual(exporter.phrases('en'), {key: row['value'] for key, row in original['entries'].items()})
            key = 'score.numbers'
            for field, value in [('source_hash', 'stale'), ('value', '%1$@ %n'), ('status', 'machine')]:
                with self.subTest(field=field):
                    payload = json.loads(json.dumps(original))
                    payload['entries'][key][field] = value
                    target.write_text(json.dumps(payload))
                    with self.assertRaises(ValueError):
                        exporter.phrases('en')
            payload = json.loads(json.dumps(original))
            payload['locale'] = 'fr'
            target.write_text(json.dumps(payload))
            with self.assertRaises(ValueError):
                exporter.phrases('en')

    def test_mislabeled_catalog_blocks_promotion(self):
        payload = json.loads((voice.CATALOG_ROOT / 'en.json').read_text())
        payload['locale'] = 'fr'
        with tempfile.TemporaryDirectory() as folder, patch.object(voice, 'CATALOG_ROOT', Path(folder)), redirect_stdout(io.StringIO()):
            (Path(folder) / 'en.json').write_text(json.dumps(payload))
            self.assertEqual(voice.main(['promote', '--locale', 'en', '--dry-run']), 1)

    def test_cross_platform_validation_failure_leaves_projects_untouched(self):
        with patch('sys.argv', ['sync_reviewed_voice_catalogs.py']), \
             patch.object(exporter.voice_localization, 'main', return_value=1), \
             patch.object(exporter, 'phrases') as read_phrases, \
             patch.object(Path, 'write_text') as write:
            with self.assertRaises(ValueError):
                exporter.main()
            read_phrases.assert_not_called()
            write.assert_not_called()

if __name__=='__main__':unittest.main()
