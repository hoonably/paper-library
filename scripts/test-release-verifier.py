#!/usr/bin/env python3
"""Exercise signed feeds whose current and old archives share one basename."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
FIXTURE=r'''
import CryptoKit
import Foundation
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let key=Curve25519.Signing.PrivateKey()
try Data(key.publicKey.rawRepresentation.base64EncodedString().utf8).write(to:root.appendingPathComponent("public.txt"))
let current=Data("current release payload".utf8), old=Data("old release payload".utf8)
try current.write(to:root.appendingPathComponent("Paper-Library.zip"))
try Data("changed release payload".utf8).write(to:root.appendingPathComponent("tampered.zip"))
func item(_ build:Int,_ bytes:Data) throws -> String {
 let signature=try key.signature(for:bytes).base64EncodedString()
 return "<item><sparkle:version>\(build)</sparkle:version><enclosure url=\"https://example.com/v\(build)/Paper-Library.zip\" length=\"\(bytes.count)\" sparkle:edSignature=\"\(signature)\"/></item>"
}
func feed(_ name:String,_ items:String) throws {
 let bytes=Data(("<?xml version=\"1.0\"?><rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel>"+items+"</channel></rss>\n").utf8)
 let signature=try key.signature(for:bytes).base64EncodedString()
 var signed=bytes
 signed.append(Data("<!-- sparkle-signatures: edSignature: \(signature) length: \(bytes.count) -->".utf8))
 try signed.write(to:root.appendingPathComponent(name))
}
let newest=try item(2,current), oldest=try item(1,old)
try feed("current-first.xml",newest+oldest)
try feed("current-last.xml",oldest+newest)
try feed("old-only.xml",oldest)
'''
with tempfile.TemporaryDirectory(prefix='signed-feed-regression-') as tmp:
 stage=Path(tmp);fixture=stage/'fixture.swift';fixture.write_text(FIXTURE)
 subprocess.run(['swift',str(fixture),str(stage)],check=True)
 def verify(feed):
  return subprocess.run(['swift',str(ROOT/'scripts/verify-update.swift'),str(stage/'public.txt'),str(stage/feed),str(stage/'Paper-Library.zip')],capture_output=True,text=True)
 for name in ['current-first.xml','current-last.xml']:
  result=verify(name);assert result.returncode==0,result.stdout+result.stderr
  print('PASS: current archive accepted with repeated basenames:',name)
 result=verify('old-only.xml');assert result.returncode!=0,'An old signed enclosure accepted different bytes'
 print('PASS: unrelated signed archive rejected')
 feed=stage/'current-first.xml';feed.write_bytes(feed.read_bytes().replace(b'<channel>',b'<channel><title>tampered</title>',1))
 assert verify(feed.name).returncode!=0,'A modified feed was accepted'
 print('PASS: modified feed rejected')
 (stage/'Paper-Library.zip').write_bytes((stage/'tampered.zip').read_bytes())
 assert verify('current-last.xml').returncode!=0,'A modified archive was accepted'
 print('PASS: modified archive rejected')
