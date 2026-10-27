#!/usr/bin/env python3
"""Select verification suites from a complete Git diff; uncertainty selects all.

This optimization applies only while research is not a product dependency.
Research-only diffs retain research checks. The exact presentation/CI allowlist
retains every native check but omits research and curated-career diagnostics.
Skipped suites are NOT RUN, never validation or a passing result.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

RESEARCH_ONLY=('scripts/research/','docs/research/')
PRESENTATION_ONLY=frozenset({
    'game/play/committee_docket.gd',
    'game/tests/committee_docket_ui_test.gd',
    'game/README.md',
})
CI_INFRASTRUCTURE=frozenset({
    'scripts/ci-scope.py',
    'scripts/tests/test-ci-scope.py',
    '.github/workflows/godot.yml',
})
SHA=re.compile(r'(?:[0-9a-f]{40}|[0-9a-f]{64})\Z')

def valid_path(path):
    return (isinstance(path,str) and bool(path)
            and not any(part in ('','.','..') for part in path.split('/'))
            and '\0' not in path
            and not any(0xd800<=ord(char)<=0xdfff for char in path))

def select(paths):
    paths=tuple(paths)
    valid=bool(paths) and all(valid_path(p) for p in paths)
    research_only=valid and all(p.startswith(RESEARCH_ONLY) for p in paths)
    presentation_ci_only=valid and all(
        p in PRESENTATION_ONLY or p in CI_INFRASTRUCTURE for p in paths)
    if research_only:
        # Nonshipping research has no native product dependency; keep its tests.
        suites={'native':False,'research':True,'curated':False}
        reason='research-only complete diff'
    elif presentation_ci_only:
        # Exact paths only: no exemption for other play code, tests or workflows.
        suites={'native':True,'research':False,'curated':False}
        reason='presentation/CI-infrastructure-only complete diff; all native checks retained'
    else:
        suites={'native':True,'research':True,'curated':True}
        reason='full verification: mixed, economic, empty, malformed or unknown paths'
    return {**suites,'changed_files':len(paths),'reason':reason}

def git(*args):
    return subprocess.run(['git',*args],check=True,stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE,timeout=60).stdout

def resolve(event_name,event,*,run=git,allow_fetch=False):
    """No API path truncation, rename omission, filenames in shell or retries."""
    try:
        base=(event['pull_request']['base']['sha'] if event_name=='pull_request'
              else event['before'] if event_name=='push' else None)
        if type(base) is not str or not SHA.fullmatch(base) or not base.strip('0'):
            raise ValueError('Missing/invalid comparison base')
        head=run('rev-parse','HEAD').decode('ascii').strip()
        if not SHA.fullmatch(head) or not head.strip('0'):
            raise ValueError('Invalid checked-out head')
        try:run('cat-file','-e',base+'^{commit}')
        except (subprocess.SubprocessError,OSError):
            if not allow_fetch:raise
            run('fetch','--no-tags','--depth=1','origin',base)
            run('cat-file','-e',base+'^{commit}')
        comparison=base
        if event_name=='pull_request':
            comparison=run('merge-base',base,head).decode('ascii').strip()
            if not SHA.fullmatch(comparison) or not comparison.strip('0'):
                raise ValueError('Unresolved merge base')
        raw=run('diff','--no-ext-diff','--no-textconv','--no-renames','--name-only','-z',comparison,head,'--')
        if raw and not raw.endswith(b'\0'):raise ValueError('Truncated filename stream')
        paths=tuple(x.decode('utf-8','surrogateescape') for x in raw.split(b'\0')[:-1])
        return {**select(paths),'base':comparison,'head':head}
    except (KeyError,TypeError,ValueError,UnicodeError,subprocess.SubprocessError,OSError) as error:
        return {'native':True,'research':True,'curated':True,
                'changed_files':None,'reason':'comparison unavailable: '+type(error).__name__}

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--event',required=True,type=Path)
    parser.add_argument('--event-name',required=True)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--summary',type=Path)
    parser.add_argument('--allow-fetch',action='store_true')
    args=parser.parse_args(argv)
    try:event=json.loads(args.event.read_text())
    except (OSError,ValueError):event={}
    result=resolve(args.event_name,event,allow_fetch=args.allow_fetch)
    if args.output:
        with args.output.open('a') as stream:
            for suite in ('native','research','curated'):
                stream.write(suite+'='+str(result[suite]).lower()+'\n')
    if args.summary:
        with args.summary.open('a') as stream:
            stream.write('## Verification scope\n\n')
            for suite,label in (
                ('native','Native/model/packaging/game/release-safe checks'),
                ('research','Funded-production research reference'),
                ('curated','Curated career pilot and full 1100-career diagnostics')):
                stream.write('- '+label+': '+('selected (results follow in their steps)' if result[suite]
                    else 'NOT RUN (scope exclusion; not reported as passed)')+'.\n')
            stream.write('\nComplete-diff selection: '+result['reason']+'.\n')
    print(json.dumps(result,ensure_ascii=True))
    return 0

if __name__=='__main__':raise SystemExit(main())
