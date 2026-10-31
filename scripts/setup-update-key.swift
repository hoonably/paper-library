#!/usr/bin/env swift
import CryptoKit
import Foundation
import Security

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let config = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("release.json"))) as! [String: Any]
let service = config["key_service"] as! String
let publicURL = root.appendingPathComponent(config["public_key_file"] as! String)
let defaultURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/\(config["key_directory"] as! String)/sparkle-private-key")
let keyURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment[config["key_env"] as! String] ?? defaultURL.path)
let checkOnly = CommandLine.arguments.contains("--check-only")
let initialize = CommandLine.arguments.contains("--initialize")
let pinned = (try? String(contentsOf: publicURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
func decoded(_ data: Data) -> Data {
    guard let text = String(data: data, encoding: .utf8), let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), raw.count == 32 else { fail("Invalid update-key encoding; no key values are logged") }
    return raw
}
var login: SecKeychain?
func loginKeychain() -> SecKeychain {
    if let login { return login }
    let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Keychains/login.keychain-db").path
    guard SecKeychainOpen(path, &login) == errSecSuccess, let login else { fail("Unlock the login Keychain before restoring the existing update key") }
    return login
}
func restore(_ publicKey: String) -> Data? {
    let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:publicKey, kSecMatchSearchList as String:[loginKeychain()], kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else { fail("Could not restore the existing update key (Keychain status \(status))") }
    return data
}
let key: Curve25519.Signing.PrivateKey
if FileManager.default.fileExists(atPath:keyURL.path) {
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: decoded(Data(contentsOf:keyURL)))
} else if !checkOnly, let pinned, let restored = restore(pinned) {
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: restored)
} else if initialize && pinned == nil {
    key = Curve25519.Signing.PrivateKey()
} else {
    fail("Restore this app's existing update key or use the signed release workflow; automatic key rotation is forbidden")
}
let derived = key.publicKey.rawRepresentation.base64EncodedString()
if let pinned {
    guard derived == pinned else { fail("Update key differs from the pinned public key; release stopped") }
} else {
    guard initialize else { fail("Public key is missing; release stopped") }
    try FileManager.default.createDirectory(at:publicURL.deletingLastPathComponent(),withIntermediateDirectories:true)
    try (derived+"\n").write(to:publicURL,atomically:true,encoding:.utf8)
}
if !checkOnly {
    try FileManager.default.createDirectory(at:keyURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    guard FileManager.default.createFile(atPath:keyURL.path,contents:Data(key.rawRepresentation.base64EncodedString().utf8),attributes:[.posixPermissions:0o600]) else { fail("Could not store the update key") }
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:keyURL.path)
    let existing = restore(derived)
    if let existing { guard existing == key.rawRepresentation else { fail("Existing Keychain backup differs; release stopped") } }
    else {
        let item: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:derived,kSecValueData as String:key.rawRepresentation,kSecUseKeychain as String:loginKeychain()]
        guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { fail("Could not back up the release key in login Keychain") }
    }
}
print("Verified pinned update key; no private key values logged")
