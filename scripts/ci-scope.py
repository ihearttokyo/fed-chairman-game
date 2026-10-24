#!/usr/bin/env python3
"""Select native checks from a complete Git diff; uncertainty selects full CI.

This optimization applies only while research is not a product dependency.
Research tests always run. A skipped native suite is not native validation.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

RESEARCH_ONLY=('scripts/research/','docs/research/')
SHA=re.compile(r'(?:[0-9a-f]{40}|[0-9a-f]{64})\Z')

def select(paths):
    paths=tuple(paths)
    safe=bool(paths) and all(
        isinstance(p,str) and p.startswith(RESEARCH_ONLY)
        and '..' not in p.split('/') and not p.endswith('/')
        for p in paths)
    return {'native':not safe,'changed_files':len(paths),
            'reason':'research-only complete diff' if safe else 'native, mixed, empty or unknown paths'}

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
        if not SHA.fullmatch(head):raise ValueError('Invalid checked-out head')
        try:run('cat-file','-e',base+'^{commit}')
        except (subprocess.SubprocessError,OSError):
            if not allow_fetch:raise
            run('fetch','--no-tags','--depth=1','origin',base)
            run('cat-file','-e',base+'^{commit}')
        comparison=base
        if event_name=='pull_request':
            comparison=run('merge-base',base,head).decode('ascii').strip()
            if not SHA.fullmatch(comparison):raise ValueError('Unresolved merge base')
        raw=run('diff','--no-ext-diff','--no-textconv','--no-renames','--name-only','-z',comparison,head,'--')
        if raw and not raw.endswith(b'\0'):raise ValueError('Truncated filename stream')
        paths=tuple(x.decode('utf-8','surrogateescape') for x in raw.split(b'\0')[:-1])
        return {**select(paths),'base':comparison,'head':head}
    except (KeyError,TypeError,ValueError,UnicodeError,subprocess.SubprocessError,OSError) as error:
        return {'native':True,'changed_files':None,'reason':'comparison unavailable: '+type(error).__name__}

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
    native='true' if result['native'] else 'false'
    if args.output:
        with args.output.open('a') as stream:stream.write('native='+native+'\n')
    if args.summary:
        with args.summary.open('a') as stream:
            stream.write('## Verification scope\n\n'+
                ('Full Godot checks selected.' if result['native'] else
                 'Only nonshipping research changed. Research checks run; native checks are NOT RUN, not reported as passed.')+
                '\n\nComplete-diff selection: '+result['reason']+'.\n')
    print(json.dumps(result,ensure_ascii=True))
    return 0

if __name__=='__main__':raise SystemExit(main())
