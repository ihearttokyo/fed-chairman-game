"""Offline selector regressions: mocked failures and disposable real Git histories."""
import hashlib,importlib.util,itertools,json,subprocess,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('ci_scope',ROOT/'scripts/ci-scope.py')
scope=importlib.util.module_from_spec(spec)
with patch('subprocess.run',side_effect=AssertionError('No process during import')):
    spec.loader.exec_module(scope)
A='a'*40;B='b'*40
FULL={'native':True,'research':True,'curated':True}
RESEARCH={'native':False,'research':True,'curated':False}
PRESENTATION={'native':True,'research':False,'curated':False}
PRESENTATION_PATHS=('game/play/committee_docket.gd','game/tests/committee_docket_ui_test.gd','game/README.md')
CI_PATHS=('scripts/ci-scope.py','scripts/tests/test-ci-scope.py','.github/workflows/godot.yml')
class ScopeTests(unittest.TestCase):
    def setUp(self):
        guard=patch('subprocess.run',side_effect=AssertionError('No process permitted in these tests'))
        guard.start();self.addCleanup(guard.stop)
    def assert_suites(self,result,expected):
        self.assertEqual({key:result[key] for key in FULL},expected)
        self.assertTrue(result['reason'])
    def test_exact_allowlists_all_single_and_mixed_variants(self):
        self.assertEqual(scope.PRESENTATION_ONLY,frozenset(PRESENTATION_PATHS))
        self.assertEqual(scope.CI_INFRASTRUCTURE,frozenset(CI_PATHS))
        paths=PRESENTATION_PATHS+CI_PATHS
        for size in range(1,len(paths)+1):
            for subset in itertools.combinations(paths,size):
                with self.subTest(paths=subset):
                    self.assert_suites(scope.select(subset),PRESENTATION)
                    self.assert_suites(scope.select([*subset,'scripts/research/x.py']),FULL)
                    self.assert_suites(scope.select([*subset,'game/model/economy.gd']),FULL)
    def test_research_only_and_complete_diff_not_first300(self):
        for paths in [
            ['scripts/research/x.py'],['docs/research/report.json'],
            ['scripts/research/x.py','docs/research/report.json'],
            ['scripts/research/file\nname.py'],
            ['scripts/research/'+str(i)+'.py' for i in range(1001)],
        ]:
            with self.subTest(paths=paths[:2]):self.assert_suites(scope.select(paths),RESEARCH)
        self.assert_suites(scope.select(
            ['scripts/research/'+str(i)+'.py' for i in range(1001)]+['game/model/economy.gd']),FULL)
    def test_unknown_mixed_economic_and_foreign_paths_fail_closed(self):
        for path in [
            'game/model/economy.gd','parameters.json','game/play/main.gd',
            'game/play/committee_docket.gd.uid','game/play/committee_docket_extra.gd',
            'game/tests/other_ui_test.gd','game/tests/committee_docket_ui_test.gd.uid',
            'README.md','scripts/__init__.py','.github/workflows/new.yml',
            'foreign/game/play/committee_docket.gd','foreign/scripts/research/x.py',
            'scripts/research-other/x.py','docs/research-other/x.md',
        ]:
            for paths in ([path],[*PRESENTATION_PATHS,path],[*CI_PATHS,path],['scripts/research/x.py',path]):
                with self.subTest(paths=paths):self.assert_suites(scope.select(paths),FULL)
    def test_empty_and_malformed_paths_fail_closed(self):
        self.assert_suites(scope.select([]),FULL)
        for path in [
            '',None,1,[],{},'scripts/research/','scripts/research/../model.py',
            'scripts/research/./x.py','scripts/research//x.py','/scripts/research/x.py',
            './game/play/committee_docket.gd','game/play/../play/committee_docket.gd',
            'scripts/research/x\0.py','scripts/research/\udcff.py','scripts\\research\\x.py',
        ]:
            with self.subTest(path=path):
                self.assert_suites(scope.select([path]),FULL)
                self.assert_suites(scope.select([*PRESENTATION_PATHS,path]),FULL)
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
    def test_push_and_pr_complete_no_renames_diff(self):
        for name,event in [('push',{'before':A}),('pull_request',{'pull_request':{'base':{'sha':A}}})]:
            for paths,expected in [(['scripts/research/x.py'],RESEARCH),(PRESENTATION_PATHS,PRESENTATION),([],FULL)]:
                run,calls=self.runner(paths)
                self.assert_suites(scope.resolve(name,event,run=run),expected)
                self.assertIn(('diff','--no-ext-diff','--no-textconv','--no-renames','--name-only','-z',A,B,'--'),calls)
                self.assertEqual(any(c[0]=='merge-base' for c in calls),name=='pull_request')
                self.assertFalse(any(c[0]=='fetch' for c in calls))
    def test_missing_malformed_or_failed_base_never_skips(self):
        for event in ({},{'before':'0'*40},{'before':'bad'},{'before':[]},None,[],{'before':A+'\n'}):
            run,calls=self.runner(PRESENTATION_PATHS)
            self.assert_suites(scope.resolve('push',event,run=run,allow_fetch=True),FULL)
            self.assertEqual(calls,[])
        run,calls=self.runner(['scripts/research/x.py'],missing=True)
        self.assert_suites(scope.resolve('push',{'before':A},run=run),FULL)
        self.assertFalse(any(c[0]=='fetch' for c in calls))
        for stage in ('rev-parse','cat-file','merge-base','diff'):
            for failure in (subprocess.TimeoutExpired('git',60),OSError('unavailable'),subprocess.CalledProcessError(1,'git')):
                run,calls=self.runner(PRESENTATION_PATHS)
                def bad(*args):
                    if args[0]==stage:raise failure
                    return run(*args)
                with self.subTest(stage=stage,failure=type(failure).__name__):
                    self.assert_suites(scope.resolve('pull_request',{'pull_request':{'base':{'sha':A}}},run=bad),FULL)
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
        self.assert_suites(scope.resolve('push',{'before':A},run=run,allow_fetch=True),RESEARCH)
        self.assertEqual([c for c in calls if c[0]=='fetch'],[('fetch','--no-tags','--depth=1','origin',A)])
        # Fetch failure or history still missing after one fetch cannot narrow CI.
        for failed_fetch in (False,True):
            run,calls=self.runner(PRESENTATION_PATHS,missing=True)
            def bad(*args):
                if args[0]=='fetch' and failed_fetch:raise OSError('fetch unavailable')
                return run(*args)
            self.assert_suites(scope.resolve('push',{'before':A},run=bad,allow_fetch=True),FULL)
            self.assertLessEqual(sum(c[0]=='fetch' for c in calls),1)
    def test_truncated_malformed_streams_and_unknown_events_select_all(self):
        for raw in (b'scripts/research/x.py',b'game/play/committee_docket.gd',
                    b'scripts/research/x.py\0game/model/economy.gd',b'\0',
                    b'scripts/research/\xff.py\0',b'scripts/research/x.py\0\0'):
            run,calls=self.runner(PRESENTATION_PATHS)
            def bad(*args):return raw if args[0]=='diff' else run(*args)
            self.assert_suites(scope.resolve('push',{'before':A},run=bad),FULL)
        for stage in ('rev-parse','merge-base'):
            for raw in (b'',b'bad\n',b'\xff',b'0'*40,b'0'*64):
                run,calls=self.runner(PRESENTATION_PATHS)
                def bad(*args):return raw if args[0]==stage else run(*args)
                self.assert_suites(scope.resolve('pull_request',{'pull_request':{'base':{'sha':A}}},run=bad),FULL)
        for name in ('pull_request_target','workflow_dispatch'):
            run,calls=self.runner(PRESENTATION_PATHS)
            self.assert_suites(scope.resolve(name,{},run=run),FULL)
            self.assertEqual(calls,[])
    def test_sha256_comparison_and_newline_paths_remain_literal(self):
        base='a'*64;head='b'*64
        calls=[]
        def run(*args):
            calls.append(args)
            if args[0]=='rev-parse':return head.encode()+b'\n'
            if args[0]=='merge-base':return base.encode()+b'\n'
            if args[0]=='diff':return b'scripts/research/file\nname.py\0'
            return b''
        self.assert_suites(scope.resolve('pull_request',{'pull_request':{'base':{'sha':base}}},run=run),RESEARCH)
        self.assertIn(('cat-file','-e',base+'^{commit}'),calls)
        self.assertIn(('diff','--no-ext-diff','--no-textconv','--no-renames','--name-only','-z',base,head,'--'),calls)
    def test_simulated_no_renames_deletions_and_old_names(self):
        # --no-renames reports deleted old AND new names, preventing scope evasion.
        # These are mocked streams, not evidence from a live Git comparison.
        for paths,expected in [
            (['game/old.gd','scripts/research/old.gd'],FULL),
            (['game/model/economy.gd',PRESENTATION_PATHS[0]],FULL),
            ([PRESENTATION_PATHS[0],'game/play/renamed.gd'],FULL),
            ([PRESENTATION_PATHS[0],'scripts/research/docket.gd'],FULL),
            (['game/model/deleted.gd'],FULL),
            ([PRESENTATION_PATHS[0]],PRESENTATION),
            (['scripts/research/deleted.py'],RESEARCH),
        ]:
            for name,event in [('push',{'before':A}),('pull_request',{'pull_request':{'base':{'sha':A}}})]:
                with self.subTest(paths=paths,name=name):
                    run,calls=self.runner(paths)
                    result=scope.resolve(name,event,run=run)
                    self.assert_suites(result,expected)
                    self.assertEqual(result['changed_files'],len(paths))
    def test_output_explicitly_marks_each_selected_or_unrun_suite(self):
        for expected in (FULL,RESEARCH,PRESENTATION):
            with self.subTest(expected=expected),tempfile.TemporaryDirectory() as directory:
                p=Path(directory);event=p/'event.json';event.write_text(json.dumps({'before':A}))
                output=p/'out';summary=p/'summary'
                with patch.object(scope,'resolve',return_value={**expected,'reason':'scope fixture'}),patch('builtins.print'):
                    self.assertEqual(scope.main(['--event',str(event),'--event-name','push','--output',str(output),'--summary',str(summary)]),0)
                self.assertEqual(output.read_text(),''.join(k+'='+str(v).lower()+'\n' for k,v in expected.items()))
                labels=('Native/model/packaging/game/release-safe checks','Funded-production research reference',
                        'Curated career pilot and full 1100-career diagnostics')
                for selected,label in zip(expected.values(),labels):
                    line=next(line for line in summary.read_text().splitlines() if line.startswith('- '+label+':'))
                    self.assertIn('selected (results follow' if selected else 'NOT RUN (scope exclusion; not reported as passed)',line)
    def test_cli_unreadable_and_malformed_event_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            event=Path(directory)/'event.json'
            for contents in (None,'{invalid','null','[]'):
                if contents is not None:event.write_text(contents)
                with patch('builtins.print') as printed:
                    self.assertEqual(scope.main(['--event',str(event),'--event-name','push']),0)
                self.assert_suites(json.loads(printed.call_args.args[0]),FULL)
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
            'Import and test playable Godot game':'7ca224c0a097a595db53114033a908a1e31b5e2e0a9ffaf42ba3b08c74ad2d30',
            'Curated career method and pilot qualification':'09cc2b2a362ad6a93884fab71e6cd89664c2f569744e0f90f0644aeb9a9930d8',
            'Current-source 1100-career diagnostic':'681d7bf6f3b217470ba9a3d5778c5d41ed69a16db645f646ee30d7ecbcddbb60',
        }
        for name in names:
            block=workflow.split('      - name: '+name+'\n',1)[1].split('      - ',1)[0]
            lines=block.splitlines()
            suite='curated' if name in names[-2:] else 'native'
            self.assertEqual(lines[0],"        if: steps.scope.outputs."+suite+" != 'false'",name)
            i=next(j for j,l in enumerate(lines) if l.startswith('        run:'))
            body='\n'.join(lines[i+1:]) if lines[i]=='        run: |' else lines[i][len('        run: '):]
            self.assertEqual(hashlib.sha256(body.encode()).hexdigest(),hashes[name],name)
        for marker in ['python3 -B -m unittest discover -s scripts/research/funded_production/tests -v',
                       'PASS: 210 release-safe checks','PASS: bundled guidance continuation and comparison',
                       'PASS: bundled mandate assessment and realized feedback','scripts/test-curated-careers.sh pilot',
                       'scripts/test-curated-careers.sh full']:
            self.assertIn(marker,workflow)
        research=workflow.split('      - name: Funded-production research reference\n',1)[1].split('      - ',1)[0]
        self.assertEqual(research,"        if: steps.scope.outputs.research != 'false'\n        run: python3 -B -m unittest discover -s scripts/research/funded_production/tests -v\n")
        safety=workflow.split('      - name: Verification-scope safety tests\n',1)[1].split('      - ',1)[0]
        self.assertEqual(safety,'        run: python3 -B scripts/tests/test-ci-scope.py\n')
        self.assertLess(workflow.index('      - name: Verification-scope safety tests\n'),workflow.index('      - name: Select complete-diff verification scope\n'))
        self.assertIn('  model:\n    name: Policy Lab source verification\n    runs-on: ubuntu-latest\n    timeout-minutes: 30\n',workflow)
        self.assertTrue(workflow.startswith('name: Verify Godot Policy Lab\n\non:\n  push:\n    branches: [main]\n  pull_request:\n'))
        self.assertEqual(workflow.count('        if:'),7)
        for forbidden in ('continue-on-error:','permissions:','always()'):
            self.assertNotIn(forbidden,workflow)
        selection=workflow.split('      - name: Select complete-diff verification scope\n',1)[1].split('      - ',1)[0]
        self.assertEqual(selection,'        id: scope\n        run: python3 -B scripts/ci-scope.py --event "$GITHUB_EVENT_PATH" --event-name "$GITHUB_EVENT_NAME" --output "$GITHUB_OUTPUT" --summary "$GITHUB_STEP_SUMMARY" --allow-fetch\n')
    def test_nonshipping_exemption_has_no_literal_native_consumer(self):
        # A limited guard, not proof against every possible dynamic dependency.
        # Filesystem-only scan: the regression suite never launches Git.
        for path in (ROOT/'game').rglob('*'):
            if (path.is_file() and path.suffix in ('.gd','.tscn','.godot')
                    and '.godot' not in path.relative_to(ROOT/'game').parts):
                text=path.read_text()
                self.assertNotIn('funded_production',text,str(path))
                self.assertNotIn('scripts/research',text,str(path))
class LiveGitScopeTests(unittest.TestCase):
    def test_real_git_rename_preserves_deleted_native_path(self):
        # Retain the original live-Git negative control, not just mocked output.
        for destination in ('scripts/research/old.gd', PRESENTATION_PATHS[0]):
            with self.subTest(destination=destination), tempfile.TemporaryDirectory() as directory:
                p=Path(directory)
                def git(*args):
                    return subprocess.run(['git','-C',directory,*args],check=True,
                                          stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout
                git('init','-q');(p/'game').mkdir();(p/'game/old.gd').write_text('content\n')
                git('add','.')
                git('-c','user.name=ihearttokyo','-c','user.email=ihearttokyo@users.noreply.github.com','commit','-qm','fixture one')
                base=git('rev-parse','HEAD').decode().strip()
                target=p/destination;target.parent.mkdir(parents=True,exist_ok=True)
                (p/'game/old.gd').rename(target);git('add','-A')
                git('-c','user.name=ihearttokyo','-c','user.email=ihearttokyo@users.noreply.github.com','commit','-qm','fixture two')
                for name,event in [('push',{'before':base}),('pull_request',{'pull_request':{'base':{'sha':base}}})]:
                    result=scope.resolve(name,event,run=git)
                    self.assertEqual({key:result[key] for key in FULL},FULL)
                    self.assertEqual(result['changed_files'],2)

    def test_real_presentation_edit_selects_native_not_unrelated_sweeps(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)
            def git(*args):
                return subprocess.run(['git','-C',directory,*args],check=True,
                                      stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout
            git('init','-q');target=p/PRESENTATION_PATHS[0];target.parent.mkdir(parents=True)
            target.write_text('before\n');git('add','.')
            git('-c','user.name=ihearttokyo','-c','user.email=ihearttokyo@users.noreply.github.com','commit','-qm','fixture one')
            base=git('rev-parse','HEAD').decode().strip();target.write_text('after\n');git('add','.')
            git('-c','user.name=ihearttokyo','-c','user.email=ihearttokyo@users.noreply.github.com','commit','-qm','fixture two')
            for name,event in [('push',{'before':base}),('pull_request',{'pull_request':{'base':{'sha':base}}})]:
                result=scope.resolve(name,event,run=git)
                self.assertEqual({key:result[key] for key in FULL},PRESENTATION)
                self.assertEqual(result['changed_files'],1)

if __name__=='__main__':unittest.main()
