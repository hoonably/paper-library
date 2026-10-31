#!/usr/bin/env swift
import CryptoKit
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

final class EnclosureReader: NSObject, XMLParserDelegate {
    let filename: String
    var signature: String?
    var length: Int?
    init(filename: String) { self.filename = filename }
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if element == "enclosure", let url = attributes["url"], URL(string: url)?.lastPathComponent == filename {
            signature = attributes["sparkle:edSignature"]
            length = attributes["length"].flatMap(Int.init)
        }
    }
}

let publicText = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let publicData = Data(base64Encoded: publicText) else { fatalError("Invalid public key") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
let feed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let text = String(decoding: feed, as: UTF8.self)
let regex = try NSRegularExpression(pattern: "<!-- sparkle-signatures:\\s*edSignature: ([A-Za-z0-9+/=]+)\\s*length: ([0-9]+)\\s*-->")
guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let signatureRange = Range(match.range(at: 1), in: text),
      let lengthRange = Range(match.range(at: 2), in: text),
      let signature = Data(base64Encoded: String(text[signatureRange])),
      let length = Int(text[lengthRange]), length > 0, length < feed.count,
      key.isValidSignature(signature, for: feed.prefix(length)) else {
    fputs("Invalid update feed signature\n", stderr); exit(1)
}
let archiveURL = URL(fileURLWithPath: CommandLine.arguments[3])
let reader = EnclosureReader(filename: archiveURL.lastPathComponent)
let parser = XMLParser(data: feed)
parser.delegate = reader
guard parser.parse(), let encoded = reader.signature,
      let archiveSignature = Data(base64Encoded: encoded) else { fatalError("Missing archive signature") }
let archive = try Data(contentsOf: archiveURL)
guard archive.count == reader.length, key.isValidSignature(archiveSignature, for: archive) else {
    fputs("Invalid update archive signature\n", stderr); exit(1)
}
print("Verified feed and archive with the embedded public key")
