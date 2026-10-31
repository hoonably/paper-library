#!/usr/bin/env python3
"""Request centrally signed builds, stage verified artifacts, then publish safely.

No private signing keys leave GitHub Actions. GitHub authentication uses GH_TOKEN
or the user's existing Git credential helper in memory, never a tracked file.
"""
from pathlib import Path
from urllib.request import Request,build_opener,HTTPRedirectHandler
from urllib.error import HTTPError
from urllib.parse import quote,urlsplit
import argparse,base64,datetime,hashlib,json,os,subprocess,tempfile,time,zipfile
ROOT=Path(__file__).resolve().parents[1]
CFG=json.loads((ROOT/'release.json').read_text())
SOURCE=CFG['source_repository'];PUBLIC=CFG['repository'];DIST=ROOT/'dist';DIST.mkdir(exist_ok=True)
class SafeRedirect(HTTPRedirectHandler):
 def redirect_request(self,req,fp,code,msg,headers,newurl):
  result=super().redirect_request(req,fp,code,msg,headers,newurl)
  if result is not None and urlsplit(newurl).hostname not in ['api.github.com','uploads.github.com']:result.remove_header('Authorization')
  return result
class GitHub:
 def __init__(self):
  self.token=os.environ.get('GH_TOKEN')
  if not self.token:
   r=subprocess.run(['git','credential','fill'],input='protocol=https\nhost=github.com\n\n',cwd=ROOT,text=True,capture_output=True,check=True,env={**os.environ,'GIT_TERMINAL_PROMPT':'0'})
   self.token=dict(line.split('=',1) for line in r.stdout.splitlines() if '=' in line)['password']
  self.opener=build_opener(SafeRedirect())
 def request(self,path,method='GET',body=None,binary=False,allow404=False,raw=False):
  url=path if path.startswith('https://') else 'https://api.github.com'+path
  assert urlsplit(url).hostname in ['api.github.com','uploads.github.com'],'Unexpected authenticated destination'
  data=body if binary else json.dumps(body).encode() if body is not None else None
  req=Request(url,data=data,headers={'Authorization':'Bearer '+self.token,'Accept':'application/vnd.github+json','Content-Type':'application/octet-stream' if binary else 'application/json','X-GitHub-Api-Version':'2022-11-28'},method=method)
  try:
   with self.opener.open(req,timeout=120) as response:
    value=response.read()
    return value if raw else json.loads(value) if value else None
  except HTTPError as e:
   if allow404 and e.code==404:return None
   try:message=json.load(e).get('message','GitHub request failed')
   except Exception:message='GitHub request failed'
   raise RuntimeError(f'{e.code}: {message}') from None
 def repo(self,path,**kw):return self.request('/repos/'+PUBLIC+path,**kw)
def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT,text=True).strip()
def saved():return json.loads((DIST/'release-run.json').read_text())
def prepare(client,baseline):
 head=git('rev-parse','HEAD')
 assert git('rev-parse','origin/main')==head,'Push main before requesting a release'
 assert not baseline or CFG['version']=='1.0.0','Baseline reset must be an explicitly approved v1.0.0'
 started=datetime.datetime.now(datetime.timezone.utc)
 client.request('/repos/'+SOURCE+'/actions/workflows/signed-release.yml/dispatches','POST',{'ref':'main','inputs':{'baseline':'true' if baseline else 'false'}})
 for _ in range(12):
  runs=client.request('/repos/'+SOURCE+'/actions/workflows/signed-release.yml/runs?event=workflow_dispatch&per_page=20')['workflow_runs']
  matches=[r for r in runs if r['head_sha']==head and datetime.datetime.fromisoformat(r['created_at'].replace('Z','+00:00'))>=started-datetime.timedelta(seconds=5)]
  if matches:
   run=matches[0];record={'run_id':run['id'],'source_commit':head,'url':run['html_url'],'version':CFG['version'],'build':CFG['build'],'baseline':bool(baseline)}
   (DIST/'release-run.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record));return
  time.sleep(2)
 raise RuntimeError('Dispatch accepted but run not visible yet; inspect Actions before retrying')
def inspect(client,download):
 state=saved();run=client.request('/repos/'+SOURCE+'/actions/runs/'+str(state['run_id']))
 print(json.dumps({'run_id':run['id'],'status':run['status'],'conclusion':run['conclusion'],'url':run['html_url']}))
 if not download or run['status']!='completed':return
 assert run['conclusion']=='success','Release build did not pass all verification'
 items=client.request('/repos/'+SOURCE+'/actions/runs/'+str(state['run_id'])+'/artifacts')['artifacts']
 artifact=next(a for a in items if a['name']=='verified-macOS-release' and not a['expired'])
 data=client.request('/repos/'+SOURCE+'/actions/artifacts/'+str(artifact['id'])+'/zip',raw=True)
 archive=DIST/'verified-release-artifact.zip';archive.write_bytes(data)
 out=DIST/'verified-release';out.mkdir(exist_ok=True)
 with zipfile.ZipFile(archive) as z:
  for name in z.namelist():
   assert not Path(name).is_absolute() and '..' not in Path(name).parts,'Unsafe artifact path'
  z.extractall(out)
 validate(out,state)
 print('Downloaded and verified centrally signed artifact')
def validate(out,state):
 report=json.loads((out/'release-verification.json').read_text());source=json.loads((out/'release-source.json').read_text())
 assert source['commit']==state['source_commit']
 assert source['version']==CFG['version'] and source['build']==CFG['build'] and source['repository']==PUBLIC
 assert report['version']==CFG['version'] and report['build']==CFG['build']
 assert report['archive']==CFG['update_archive'].format(version=CFG['version']) and report['installer']==CFG['installer'].format(version=CFG['version']),'Artifact filenames differ from release.json'
 assert report['future_build']==CFG['build']+1,'Next-build installation was not verified'
 assert 'identical DMG and updater app, signature and metadata' in report['verified'],'Installer/update parity was not verified'
 assert report['public_key']==(ROOT/CFG['public_key_file']).read_text().strip()
 assert 'signed next-version discovery, download, validation and actual disposable app replacement' in report['verified']
 for filename,digest in [(report['archive'],report['sha256']),(report['installer'],report['installer_sha256'])]:
  assert hashlib.sha256((out/filename).read_bytes()).hexdigest()==digest,'Artifact digest mismatch'
 subprocess.run(['swift',str(ROOT/'scripts/verify-update.swift'),str(ROOT/CFG['public_key_file']),str(out/'appcast.xml'),str(out/report['archive'])],check=True)
 return report
def stage(client):
 state=saved();out=DIST/'verified-release';report=validate(out,state)
 tag=f"v{CFG['version']}-stage-{state['run_id']}"
 releases=client.repo('/releases?per_page=100')
 found=next((r for r in releases if r['tag_name']==tag),None)
 target=state['source_commit'] if PUBLIC==SOURCE else client.repo('/git/ref/heads/main')['object']['sha']
 if found is None:found=client.repo('/releases',method='POST',body={'tag_name':tag,'target_commitish':target,'name':f"{CFG['app_name']} v{CFG['version']}",'body':(out/'RELEASE_NOTES.md').read_text(),'draft':True,'prerelease':False})
 assert found['draft'],'Staging release is already public; inspect it before continuing'
 files={report['installer'],report['archive']}
 checks=''.join(hashlib.sha256((out/name).read_bytes()).hexdigest()+'  '+name+'\n' for name in sorted(files))
 (out/'SHA256SUMS.txt').write_text(checks);files.add('SHA256SUMS.txt')
 for name in sorted(files):
  blob=(out/name).read_bytes();existing=next((a for a in found['assets'] if a['name']==name),None)
  if existing is not None:
   assert existing['size']==len(blob) and existing.get('digest') in [None,'sha256:'+hashlib.sha256(blob).hexdigest()],'Existing draft asset differs'
   continue
  upload=found['upload_url'].split('{')[0]+'?name='+quote(name)
  result=client.request(upload,'POST',blob,binary=True)
  assert result['size']==len(blob) and result.get('digest') in [None,'sha256:'+hashlib.sha256(blob).hexdigest()]
 state.update({'release_id':found['id'],'stage_tag':tag,'release_target':target})
 (DIST/'release-run.json').write_text(json.dumps(state,indent=2)+'\n')
 print('Draft staged with authenticated artifacts; existing releases unchanged')
def publish(client,reset):
 state=saved();out=DIST/'verified-release';report=validate(out,state)
 assert state.get('release_id'),'Stage the verified artifact first'
 tag='v'+CFG['version'];old=client.repo('/releases?per_page=100')
 prior=next((r for r in old if r['tag_name']==tag and r['id']!=state['release_id']),None)
 assert not prior or reset,'Published versions are immutable; choose a new version'
 assert not reset or CFG['version']=='1.0.0','History reset is restricted to the explicitly approved baseline'
 if prior:client.repo('/releases/'+str(prior['id']),method='DELETE')
 ref=client.repo('/git/ref/tags/'+tag,allow404=True)
 if ref and ref['object']['sha']!=state['release_target']:
  assert reset,'Existing tag differs; refusing to overwrite it'
  client.repo('/git/refs/tags/'+tag,method='DELETE');ref=None
 if ref is None:client.repo('/git/refs',method='POST',body={'ref':'refs/tags/'+tag,'sha':state['release_target']})
 release=client.repo('/releases/'+str(state['release_id']),method='PATCH',body={'tag_name':tag,'target_commitish':state['release_target'],'draft':False,'prerelease':False,'make_latest':'true','name':f"{CFG['app_name']} {tag}",'body':(out/'RELEASE_NOTES.md').read_text()})
 # The public installer and update payload must be anonymously downloadable
 # and byte-identical before the appcast is published.
 with tempfile.TemporaryDirectory(prefix='public-release-verify-') as tmp:
  for name,digest in {(report['archive'],report['sha256']),(report['installer'],report['installer_sha256'])}:
   downloaded=Path(tmp)/name
   url=f'https://github.com/{PUBLIC}/releases/download/{tag}/'+quote(name)
   subprocess.run(['curl','--fail','--location','--silent','--show-error','--retry','3','--max-time','120',url,'--output',str(downloaded)],check=True)
   assert hashlib.sha256(downloaded.read_bytes()).hexdigest()==digest,'Public download differs'
   if name==report['archive']:subprocess.run(['swift',str(ROOT/'scripts/verify-update.swift'),str(ROOT/CFG['public_key_file']),str(out/'appcast.xml'),str(downloaded)],check=True)
 feed=out/'appcast.xml';previous=client.repo('/contents/appcast.xml',allow404=True)
 body={'message':f"Publish signed {tag} update feed",'content':base64.b64encode(feed.read_bytes()).decode(),'branch':'main'}
 if previous:body['sha']=previous['sha']
 feed_result=client.repo('/contents/appcast.xml',method='PUT',body=body)
 if reset:
  for old_release in old:
   if old_release['id'] not in {release['id'],prior['id'] if prior else None}:client.repo('/releases/'+str(old_release['id']),method='DELETE',allow404=True)
  if SOURCE!=PUBLIC:
   for old_release in client.request('/repos/'+SOURCE+'/releases?per_page=100'):
    client.request('/repos/'+SOURCE+'/releases/'+str(old_release['id']),'DELETE')
 state.update({'published_url':release['html_url'],'feed_commit':feed_result['commit']['sha'],'published':True})
 (DIST/'release-run.json').write_text(json.dumps(state,indent=2)+'\n')
 # A draft may never create its temporary tag. Check before cleanup; GitHub
 # returns 422 for deleting a nonexistent ref rather than 404.
 if client.repo('/git/ref/tags/'+state['stage_tag'],allow404=True):
  client.repo('/git/refs/tags/'+state['stage_tag'],method='DELETE',allow404=True)
 print('Published',release['html_url'],'and the verified signed feed')
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('action',choices=['prepare','status','download','stage','publish'])
parser.add_argument('--baseline',action='store_true');parser.add_argument('--reset-history',action='store_true')
args=parser.parse_args();client=GitHub()
if args.action=='prepare':prepare(client,args.baseline)
elif args.action in ['status','download']:inspect(client,args.action=='download')
elif args.action=='stage':stage(client)
elif args.action=='publish':publish(client,args.reset_history)
