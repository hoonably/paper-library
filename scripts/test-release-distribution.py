#!/usr/bin/env python3
"""Check original private Releases and the public file-before-feed boundary."""
from pathlib import Path
from urllib.parse import urlsplit,parse_qs
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
ns={'__file__':str(ROOT/'scripts/release.py')}
exec((ROOT/'scripts/release.py').read_text().split('parser=argparse.ArgumentParser',1)[0],ns)
with tempfile.TemporaryDirectory(prefix='release-distribution-test-') as tmp:
 root=Path(tmp);dist=root/'dist';out=dist/'verified-release';out.mkdir(parents=True)
 for name,data in [('App.dmg',b'installer'),('App.zip',b'update'),('appcast.xml',b'signed feed'),('RELEASE_NOTES.md','제품 설명 한 문장.\n'.encode())]:(out/name).write_bytes(data)
 cfg={'version':'1.0.0','app_name':'App','public_key_file':'public.txt','public_site_url':'https://app.pages.dev','feed_url':'https://app.pages.dev/updates/appcast.xml','download_url_prefix':'https://app.pages.dev/downloads/v{version}/','release_notes_url':'https://app.pages.dev/updates/v{version}.html','installer_url':'https://app.pages.dev/downloads/latest.dmg'}
 report={'installer':'App.dmg','archive':'App.zip','sha256':hashlib.sha256(b'update').hexdigest(),'installer_sha256':hashlib.sha256(b'installer').hexdigest()}
 state={'source_commit':'verified-source','run_id':7};events=[];uploads=[]
 class Client:
  private=True
  def repo(self,path,method='GET',body=None,**_kw):
   if path=='':return {'private':self.private}
   if path=='/releases?per_page=100':return []
   assert path=='/releases' and method=='POST'
   assert body['target_commitish']=='verified-source' and body['body']=='제품 설명 한 문장.\n'
   return {'id':8,'draft':True,'assets':[],'upload_url':'https://uploads.github.com/release/assets{?name}'}
  def request(self,url,method,blob,binary=False):
   name=parse_qs(urlsplit(url).query)['name'][0];uploads.append(name)
   return {'size':len(blob),'digest':'sha256:'+hashlib.sha256(blob).hexdigest()}
 def commit(changes,message):
  phase='feed' if 'website/updates/appcast.xml' in changes else 'assets';events.append(('commit',phase))
  if phase=='feed':assert any(e[0]=='verify' and e[1].endswith('/downloads/latest.dmg') for e in events)
  for relative,content in changes.items():
   path=root/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(content)
  return phase+'-commit'
 def wait(url,digest,destination,timeout=240):
  events.append(('verify',url))
  name='appcast.xml' if url.endswith('/appcast.xml') else 'App.dmg' if url.endswith('/latest.dmg') else urlsplit(url).path.rsplit('/',1)[1]
  content=(out/name).read_bytes();assert hashlib.sha256(content).hexdigest()==digest;destination.write_bytes(content)
 class Runner:
  @staticmethod
  def run(args,**_kw):
   assert args[0]=='swift';events.append(('signature',str(args[-1])));return subprocess.CompletedProcess(args,0)
 ns.update(ROOT=root,DIST=dist,CFG=cfg,SOURCE='owner/private-app',REPOSITORY='owner/private-app',saved=lambda:dict(state),validate=lambda *_args:report,commit_site_files=commit,wait_for_public_file=wait,subprocess=Runner)
 client=Client();ns['stage'](client)
 assert set(uploads)=={'App.dmg','App.zip'},uploads
 print('PASS: original private Releases stage only installer/update binaries')
 ns['publish_cloudflare'](client,out,report,{},dict(state))
 assert (root/'appcast.xml').read_bytes()==(root/'website/updates/appcast.xml').read_bytes()
 record=json.loads((root/'website/updates/releases.json').read_text())[0]
 assert all(a['state']=='uploaded' and a['browser_download_url'].startswith('https://app.pages.dev/downloads/v1.0.0/') for a in record['assets'])
 public={str(p.relative_to(root/'website')) for p in (root/'website').rglob('*') if p.is_file()}
 assert public=={'downloads/v1.0.0/App.dmg','downloads/v1.0.0/App.zip','updates/v1.0.0.html','updates/appcast.xml','updates/releases.json','_headers','_redirects'},public
 assert '/downloads/latest.dmg /downloads/v1.0.0/App.dmg 302' in (root/'website/_redirects').read_text()
 print('PASS: exact public allowlist, latest download redirect and native JSON schema')
 assert events.index(('commit','assets'))<events.index(('commit','feed'))
 events.clear()
 def unavailable(*_args,**_kw):raise RuntimeError('asset deployment unavailable')
 ns['wait_for_public_file']=unavailable
 try:ns['publish_cloudflare'](client,out,report,{},dict(state))
 except RuntimeError:pass
 else:raise AssertionError('Unavailable asset deployment accepted')
 assert ('commit','feed') not in events
 print('PASS: failed public installer verification prevents publishing the feed')
 events.clear();client.private=False
 try:ns['publish_cloudflare'](client,out,report,{},dict(state))
 except AssertionError:pass
 else:raise AssertionError('Public source unexpectedly accepted')
 assert not events
 print('PASS: private-source mode refuses a publicly visible repository')
