#!/usr/bin/env python3
"""Build signed release files using only the pinned CI signing identity."""
from pathlib import Path
import json,os,subprocess,sys,shutil
root=Path(__file__).resolve().parents[1];os.chdir(root)
cfg=json.loads((root/'release.json').read_text())
import xml.etree.ElementTree as ET
baseline=os.environ.get('RELEASE_BASELINE')=='true'
if baseline:assert cfg['version']=='1.0.0','Baseline mode is restricted to the explicitly approved first release'
elif (root/'appcast.xml').exists():
 previous=ET.parse(root/'appcast.xml').getroot().findall('channel/item/{http://www.andymatuschak.org/xml-namespaces/sparkle}version')
 assert all(cfg['build']>int(item.text) for item in previous),'Increase release.json build before preparing another update'

secret=os.environ.pop('SPARKLE_PRIVATE_KEY','').strip()
assert secret,'SPARKLE_PRIVATE_KEY repository secret is required; release stopped'
key=Path(os.environ['RUNNER_TEMP'])/'sparkle-private-key'
fd=os.open(key,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as f:f.write(secret+'\n')
del secret
os.environ[cfg['key_env']]=str(key)
os.environ['RELEASE_RESET_HISTORY']='1' if os.environ.get('RELEASE_BASELINE')=='true' else '0'
def run(args,**kw):subprocess.run(args,check=True,**kw)
try:
 run(['swift','scripts/setup-update-key.swift',str(root),'--check-only'])
 run(['python3','scripts/test-release-identity.py'])
 name=cfg['app_name']
 if name=='cosMOSS':
  run(['uv','sync','--frozen'])
  run(['.venv/bin/python','-m','unittest','discover','-s','tests'])
  run(['node','--check','static/app.js'])
  os.environ['COSMOSS_RELEASE_CODESIGN_IDENTITY']='-'
  run(['./scripts/build-mac-release.sh'])
 elif name=='Pickly':
  run(['./scripts/test.sh'])
  os.environ['PICKLY_VERSION']=cfg['version'];os.environ['PICKLY_BUILD_NUMBER']=str(cfg['build'])
  os.environ['PICKLY_SIGN_IDENTITY']='-'
  run(['./scripts/package-release.sh'])
 elif name=='Paper Library':
  run(['scripts/run-core-checks.sh'])
  run(['scripts/build-local-app.sh'])
 elif name=='Talk Zero':
  run(['./scripts/test.sh']);os.environ['TALK_ZERO_CODESIGN_IDENTITY']='-'
  run(['./scripts/build-app.sh']);run(['./scripts/build-dmg.sh'])
 run(['python3','scripts/generate-appcast.py'])
 run(['python3','scripts/verify-release-chain.py'])
 out=root/'dist/verified-release';out.mkdir(parents=True,exist_ok=True)
 files=[root/'appcast.xml',root/'docs/RELEASE_NOTES.md']
 files.extend([root/'dist'/cfg['installer'].format(version=cfg['version']),root/'dist'/cfg['update_archive'].format(version=cfg['version'])])
 for p in files:shutil.copy2(p,out/p.name)
 shutil.copy2(root/'dist/release-verification.json',out/'release-verification.json')
 import hashlib
 payloads=sorted({cfg['installer'].format(version=cfg['version']),cfg['update_archive'].format(version=cfg['version'])})
 (out/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256((out/name).read_bytes()).hexdigest()+'  '+name+'\n' for name in payloads))
 (out/'release-source.json').write_text(json.dumps({'commit':os.environ['GITHUB_SHA'],'version':cfg['version'],'build':cfg['build'],'repository':cfg['repository']},indent=2)+'\n')
finally:key.unlink(missing_ok=True)
