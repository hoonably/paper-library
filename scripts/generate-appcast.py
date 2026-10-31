#!/usr/bin/env python3
"""Generate a signed feed from the app's pinned release identity."""
from pathlib import Path
import json,os,shutil,subprocess,sys,tempfile,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
cfg=json.loads((root/'release.json').read_text())
archive=Path(sys.argv[1]) if len(sys.argv)>1 else root/'dist'/cfg['update_archive'].format(version=cfg['version'])
feed=Path(os.environ.get('APPCAST_OUTPUT',str(root/'appcast.xml')))
key=Path(os.environ.get(cfg['key_env'],str(Path.home()/'Library/Application Support'/cfg['key_directory']/'sparkle-private-key')))
assert archive.is_file(),'Missing update archive'
assert key.is_file(),'Restore the existing release key or run the signed release workflow'
subprocess.run(['swift',str(root/'scripts/setup-update-key.swift'),str(root),'--check-only'],check=True)
tools=root/'dist/.sparkle-tools/generate_appcast'
if not tools.is_file():tools=next((p for base in [root/'.build',root/'macos/.build'] if base.exists() for p in base.glob('artifacts/**/bin/generate_appcast')),None)
assert tools is not None,'Sparkle signing tools not found'
with tempfile.TemporaryDirectory(prefix='signed-appcast-') as tmp:
 stage=Path(tmp)
 shutil.copy2(archive,stage/archive.name)
 if feed.exists() and os.environ.get('RELEASE_RESET_HISTORY')!='1':shutil.copy2(feed,stage/'appcast.xml')
 prefix=f"https://github.com/{cfg['repository']}/releases/download/v{cfg['version']}/"
 subprocess.run([str(tools),'--ed-key-file',str(key),'--download-url-prefix',prefix,'--full-release-notes-url',f"https://github.com/{cfg['repository']}/releases/tag/v{cfg['version']}",'--link',f"https://github.com/{cfg['repository']}/releases",'--maximum-versions','5','--maximum-deltas','0','-o',str(stage/'appcast.xml'),str(stage)],check=True)
 ns='{http://www.andymatuschak.org/xml-namespaces/sparkle}'
 items=ET.parse(stage/'appcast.xml').getroot().findall('channel/item')
 item=next(i for i in items if i.findtext(ns+'version')==str(cfg['build']))
 assert item.findtext(ns+'shortVersionString')==cfg['version'],'Release version differs from embedded app'
 enclosure=item.find('enclosure')
 assert enclosure.get('url')==prefix+archive.name and int(enclosure.get('length'))==archive.stat().st_size
 subprocess.run(['swift',str(root/'scripts/verify-update.swift'),str(root/cfg['public_key_file']),str(stage/'appcast.xml'),str(archive)],check=True)
 feed.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(stage/'appcast.xml',feed)
 print('Verified and signed',feed.name,'for',cfg['version'],cfg['build'])
