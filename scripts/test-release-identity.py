#!/usr/bin/env python3
"""Missing or mismatched local keys must never create or rotate a release key."""
from pathlib import Path
import base64,hashlib,json,os,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
cfg=json.loads((root/'release.json').read_text())
public=root/cfg['public_key_file'];before=public.read_bytes()
with tempfile.TemporaryDirectory(prefix='release-key-guards-') as tmp:
 key=Path(tmp)/'wrong-key';key.write_bytes(base64.b64encode(bytes(32)));key.chmod(0o600)
 for path,args in [(Path(tmp)/'missing',['--check-only']),(key,['--check-only']),(key,['--initialize'])]:
  env={**os.environ,cfg['key_env']:str(path)}
  result=subprocess.run(['swift',str(root/'scripts/setup-update-key.swift'),str(root),*args],env=env,capture_output=True,text=True)
  assert result.returncode!=0,'Missing or wrong signing key unexpectedly accepted'
  assert public.read_bytes()==before,'Pinned public key changed'
  assert not (Path(tmp)/'missing').exists(),'Missing key was silently recreated'
print('PASS: missing/wrong key rejected; pinned identity cannot rotate automatically')
