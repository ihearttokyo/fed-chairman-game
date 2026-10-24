"""Offline selector and supported workflow-shape regressions. No engine."""
import hashlib,importlib.util,json,subprocess,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('ci_scope',ROOT/'scripts/ci-scope.py')
scope=importlib.util.module_from_spec(spec)
with patch('subprocess.run',side_effect=AssertionError('No process during import')):
    spec.loader.exec_module(scope)
A='a'*40;B='b'*40
class ScopeTests(unittest.TestCase):
    def test_selection_all_paths_not_first300(self):
        for paths,expected in [
            (['scripts/research/x.py'],False),(['docs/research/report.json'],False),
            (['scripts/research/x.py','game/model/economy.gd'],True),
            (['game/play/main.gd'],True),(['README.md'],True),
            (['.github/workflows/godot.yml'],True),(['scripts/ci-scope.py'],True),
            (['scripts/tests/test-ci-scope.py'],True),(['scripts/__init__.py'],True),
            ([],True),(['scripts/research/../model.py'],True),
            (['scripts/research/file\nname.py'],False),
            (['scripts/research/'+str(i)+'.py' for i in range(301)]+['game/model/economy.gd'],True)]:
            with self.subTest(paths=paths[:2]):self.assertEqual(scope.select(paths)['native'],expected)
    def runner(self,paths,missing=False):
        calls=[]
        def run(*args):
            calls.append(args)
            if args[0]=='rev-parse':return B.encode()+b'\n'
            if args[0]=='cat-file' and missing:raise subprocess.CalledProcessError(1,args)
            if args[0]=='merge-base':return A.encode()+b'\n'
            if args[0]=='diff':return b''.join(p.encode()+b'\0' for p in paths)
            return b''
        return run,calls
    def test_push_and_pr_complete_diff(self):
        for name,event in [('push',{'before':A}),('pull_request',{'pull_request':{'base':{'sha':A}}})]:
            run,calls=self.runner(['scripts/research/x.py'])
            self.assertFalse(scope.resolve(name,event,run=run)['native'])
            self.assertTrue(any(c[0]=='diff' and all(flag in c for flag in ('--no-ext-diff','--no-textconv','--no-renames','--name-only','-z')) for c in calls))
            self.assertEqual(any(c[0]=='merge-base' for c in calls),name=='pull_request')
    def test_missing_malformed_or_cancelled_selection_never_skips(self):
        for event in ({},{'before':'0'*40},{'before':'bad'},{'before':[]},None):
            self.assertTrue(scope.resolve('push',event)['native'])
        run,calls=self.runner(['scripts/research/x.py'],missing=True)
        self.assertTrue(scope.resolve('push',{'before':A},run=run)['native'])
        self.assertFalse(any(c[0]=='fetch' for c in calls))
        for failure in (subprocess.TimeoutExpired('git',60),OSError('unavailable')):
            def bad(*args):raise failure
            self.assertTrue(scope.resolve('push',{'before':A},run=bad)['native'])
    def test_optional_missing_base_fetch_is_bounded_and_literal(self):
        calls=[];fetched=False
        def run(*args):
            nonlocal fetched
            calls.append(args)
            if args[0]=='rev-parse':return B.encode()
            if args[0]=='cat-file' and not fetched:raise subprocess.CalledProcessError(1,args)
            if args[0]=='fetch':fetched=True;return b''
            if args[0]=='diff':return b'scripts/research/x.py\0'
            return b''
        self.assertFalse(scope.resolve('push',{'before':A},run=run,allow_fetch=True)['native'])
        self.assertEqual([c for c in calls if c[0]=='fetch'],[('fetch','--no-tags','--depth=1','origin',A)])
    def test_truncated_stream_and_unknown_event_select_native(self):
        run,calls=self.runner(['scripts/research/x.py'])
        def bad(*args):return b'scripts/research/x.py' if args[0]=='diff' else run(*args)
        self.assertTrue(scope.resolve('push',{'before':A},run=bad)['native'])
        self.assertTrue(scope.resolve('pull_request_target',{},run=run)['native'])
    def test_real_git_rename_has_deleted_native_path(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)
            def git(*args):return subprocess.run(['git','-C',directory,*args],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout
            git('init','-q');(p/'game').mkdir();(p/'game/old.gd').write_text('content\n')
            git('add','.');git('-c','user.name=ihearttokyo','-c','user.email=ihearttokyo@users.noreply.github.com','commit','-qm','fixture one')
            base=git('rev-parse','HEAD').decode().strip()
            (p/'scripts/research').mkdir(parents=True);(p/'game/old.gd').rename(p/'scripts/research/old.gd')
            git('add','-A');git('-c','user.name=ihearttokyo','-c','user.email=ihearttokyo@users.noreply.github.com','commit','-qm','fixture two')
            result=scope.resolve('push',{'before':base},run=git)
            self.assertTrue(result['native']);self.assertEqual(result['changed_files'],2)
            pr=scope.resolve('pull_request',{'pull_request':{'base':{'sha':base}}},run=git)
            self.assertTrue(pr['native']);self.assertEqual(pr['changed_files'],2)
    def test_output_explicitly_marks_unrun_native(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory);event=p/'event.json';event.write_text(json.dumps({'before':A}))
            output=p/'out';summary=p/'summary'
            with patch.object(scope,'resolve',return_value={'native':False,'reason':'research-only complete diff'}):
                self.assertEqual(scope.main(['--event',str(event),'--event-name','push','--output',str(output),'--summary',str(summary)]),0)
            self.assertEqual(output.read_text(),'native=false\n');self.assertIn('NOT RUN',summary.read_text())
    def test_actual_workflow_retains_every_native_step_and_defaults_to_full(self):
        workflow=(ROOT/'.github/workflows/godot.yml').read_text()
        self.assertNotIn('paths-ignore:',workflow);self.assertNotIn('pull_request_target:',workflow)
        self.assertIn('Policy Lab source verification',workflow)
        self.assertIn('scripts/ci-scope.py',workflow);self.assertIn('fetch-depth: 2',workflow)
        names=['Install checksum-pinned Godot 4.7.2','Focused model channels','Model and packaging safety tests',
               'Import and test playable Godot game','Curated career method and pilot qualification','Current-source 1100-career diagnostic']
        # Run bodies are the verified main baseline; selection must not trim them.
        hashes={
            'Install checksum-pinned Godot 4.7.2':'30058b2ab572cfaafd9782decd4e44b5bcaba55ce15e30e014771f51e98c8d32',
            'Focused model channels':'9269943b20c148a93d91f42c16911f1cc9dcab4e53036146584f84e88c053f32',
            'Model and packaging safety tests':'c4cb3a32a815e254781812769899e709312810299081cecce3620ba0e14e9aee',
            'Import and test playable Godot game':'7c7e06d004b7c646f059db3fa776e90cba3621a9e36327dded5f48477bbc1398',
            'Curated career method and pilot qualification':'09cc2b2a362ad6a93884fab71e6cd89664c2f569744e0f90f0644aeb9a9930d8',
            'Current-source 1100-career diagnostic':'681d7bf6f3b217470ba9a3d5778c5d41ed69a16db645f646ee30d7ecbcddbb60',
        }
        for name in names:
            block=workflow.split('      - name: '+name+'\n',1)[1].split('      - ',1)[0]
            lines=block.splitlines()
            self.assertEqual(lines[0],"        if: steps.scope.outputs.native != 'false'",name)
            i=next(j for j,l in enumerate(lines) if l.startswith('        run:'))
            body='\n'.join(lines[i+1:]) if lines[i]=='        run: |' else lines[i][len('        run: '):]
            self.assertEqual(hashlib.sha256(body.encode()).hexdigest(),hashes[name],name)
        for marker in ['python3 -B -m unittest discover -s scripts/research/funded_production/tests -v',
                       'PASS: 187 release-safe checks','PASS: bundled guidance continuation and comparison',
                       'PASS: bundled mandate assessment and realized feedback','scripts/test-curated-careers.sh pilot',
                       'scripts/test-curated-careers.sh full']:
            self.assertIn(marker,workflow)
        research=workflow.split('      - name: Funded-production research reference\n',1)[1].split('      - ',1)[0]
        self.assertNotIn('if:',research)
    def test_nonshipping_exemption_has_no_literal_native_consumer(self):
        # A limited guard, not proof against every possible dynamic dependency.
        files=subprocess.check_output(['git','ls-files','-z','game'],cwd=ROOT).decode().split('\0')[:-1]
        for name in files:
            if Path(name).suffix in ('.gd','.tscn','.godot'):
                text=(ROOT/name).read_text()
                self.assertNotIn('funded_production',text,name)
                self.assertNotIn('scripts/research',text,name)
if __name__=='__main__':unittest.main()
