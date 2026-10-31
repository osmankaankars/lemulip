#!/usr/bin/env python3
"""One-time reviewed-asset commit, restricted to a named non-production branch."""
import ast
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.request import Request,urlopen

ROOT=Path(__file__).resolve().parent.parent
REPO='osmankaankars/lemulip'
BRANCH='review/release-020-presentation'
ALLOWED={
 'site/index.html','site/catalog.js','site/gallery.css','site/product.css',
 'site/assets/app-workspace.webp','site/assets/app-pdf-organize.webp',
 'site/assets/app-crop-video.webp','site/assets/app-trim-audio.webp',
 'site/assets/screenshots.json','site/assets/social-preview.png','site/assets/social-preview.json',
 'script/privacy_check.py','script/test_site.py','script/test_site_browser.py',
 'script/render_social_preview.py','script/social_preview.html',
 'docs/ROADMAP.md','docs/MARKETING.md','docs/QUALITY_FOLLOWUP.md',
 'docs/NATIVE_VERIFICATION.md','docs/EDITOR_REVIEW.md'}

def update_allowlist():
 p=ROOT/'script/privacy_check.py';text=p.read_text()
 match=re.search(r'PUBLIC_IMAGES = \{.*?\n\}',text,re.S)
 values=ast.literal_eval(match.group(0).split('=',1)[1].strip())
 for row in json.loads((ROOT/'site/assets/screenshots.json').read_text()):
  values['site/assets/'+row['file']]=row['sha256']
 values['site/assets/social-preview.png']=hashlib.sha256((ROOT/'site/assets/social-preview.png').read_bytes()).hexdigest()
 p.write_text(text[:match.start()]+'PUBLIC_IMAGES = '+json.dumps(values,indent=4)+text[match.end():])

if __name__=='__main__':
 import sys
 if sys.argv[1:] == ['--allowlist-only']:
  update_allowlist();raise SystemExit(0)
 if os.environ.get('GITHUB_REPOSITORY')!=REPO or os.environ.get('GITHUB_REF')!='refs/heads/'+BRANCH:
  raise SystemExit('This import can only update its isolated review branch')
 head=os.environ['GITHUB_SHA']
 token=os.environ['GH_TOKEN']
 def api(path,body=None,method=None):
  req=Request('https://api.github.com/repos/'+REPO+'/'+path,
   data=None if body is None else json.dumps(body).encode(),method=method,
   headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','Content-Type':'application/json','X-GitHub-Api-Version':'2022-11-28'})
  with urlopen(req,timeout=60) as response:return json.load(response)
 if api('git/ref/heads/'+BRANCH)['object']['sha']!=head:
  raise SystemExit('Review branch advanced; refusing a stale write')
 changed=set(subprocess.check_output(['git','diff','--name-only'],cwd=ROOT,text=True).splitlines())
 changed.update(subprocess.check_output(['git','ls-files','--others','--exclude-standard'],cwd=ROOT,text=True).splitlines())
 if not changed or not changed <= ALLOWED:
  raise SystemExit('Unexpected changed paths: '+repr(sorted(changed-ALLOWED)))
 subprocess.run(['git','add','--',*sorted(changed)],cwd=ROOT,check=True)
 subprocess.run(['python3','script/privacy_check.py','--staged'],cwd=ROOT,check=True)
 entries=[]
 for name in sorted(changed):
  path=ROOT/name
  if path.is_symlink() or not path.is_file() or path.stat().st_size>2_000_000:raise ValueError('Unexpected file')
  blob=api('git/blobs',{'encoding':'base64','content':base64.b64encode(path.read_bytes()).decode()},'POST')
  entries.append({'path':name,'mode':'100644','type':'blob','sha':blob['sha']})
 base=api('git/commits/'+head)['tree']['sha']
 tree=api('git/trees',{'base_tree':base,'tree':entries},'POST')['sha']
 commit=api('git/commits',{'message':'Prepare reviewed native 2x gallery, current product story and release tracking\n\nThe full-app source is unchanged. Imported only four pre-reviewed capture originals; no screenshot resampling or repainted controls. Local and browser review evidence is retained separately. This isolated branch commit does not deploy a site or publish a release.','tree':tree,'parents':[head]},'POST')['sha']
 if api('git/ref/heads/'+BRANCH)['object']['sha']!=head:raise SystemExit('Ref changed before update')
 api('git/refs/heads/'+BRANCH,{'sha':commit,'force':False},'PATCH')
 output=Path(os.environ['RUNNER_TEMP'])/'presentation-evidence'
 output.mkdir(exist_ok=True)
 (output/'prepared-commit.json').write_text(json.dumps({'commit':commit,'tree':tree,'parent':head,'branch':BRANCH,'paths':sorted(changed)},indent=2)+'\n')
 print('Prepared review commit',commit,'with',len(entries),'bounded file changes; no main or release write.')
