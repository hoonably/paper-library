#!/usr/bin/env swift
import CryptoKit
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

final class EnclosureReader: NSObject, XMLParserDelegate {
    let filename: String
    var candidates: [(signature: String, length: Int)] = []
    init(filename: String) { self.filename = filename }
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if element == "enclosure", let url = attributes["url"], URL(string: url)?.lastPathComponent == filename {
            if let signature = attributes["sparkle:edSignature"],
               let length = attributes["length"].flatMap(Int.init) {
                candidates.append((signature, length))
            }
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
guard parser.parse(), !reader.candidates.isEmpty else { fatalError("Missing archive signature") }
let archive = try Data(contentsOf: archiveURL)
// Different releases can deliberately keep the same archive basename. Select
// the enclosure by its actual signed bytes, independently of feed item order.
guard reader.candidates.contains(where: { candidate in
    guard archive.count == candidate.length, let signature = Data(base64Encoded: candidate.signature) else { return false }
    return key.isValidSignature(signature, for: archive)
}) else {
    fputs("Invalid update archive signature\n", stderr); exit(1)
}
print("Verified feed and archive with the embedded public key")
