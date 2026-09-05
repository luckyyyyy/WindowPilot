import CryptoKit
import Foundation

// Public-key-only verification: publishing checks never need to read a private key.
final class EnclosureParser: NSObject, XMLParserDelegate {
    var signatures: [String] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "enclosure", let signature = attributes["sparkle:edSignature"] { signatures.append(signature) }
    }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "WindowPilot.UpdateVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

do {
    let args = CommandLine.arguments
    try require(args.count == 4, "Usage: verify-update-signatures.swift appcast.xml archive.dmg Info.plist")
    let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: args[3])), format: nil) as? [String: Any]
    guard let encodedKey = info?["SUPublicEDKey"] as? String, let rawKey = Data(base64Encoded: encodedKey) else {
        throw NSError(domain: "WindowPilot.UpdateVerification", code: 2)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    let feed = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    let marker = Data("<!-- sparkle-signatures:\n".utf8)
    guard let block = feed.range(of: marker, options: .backwards),
          let trailer = String(data: feed[block.upperBound...], encoding: .utf8) else {
        throw NSError(domain: "WindowPilot.UpdateVerification", code: 3)
    }
    let lines = trailer.split(separator: "\n")
    try require(lines.count == 3 && lines[2] == "-->", "Malformed feed signing block")
    guard lines[0].hasPrefix("edSignature: "), lines[1].hasPrefix("length: "),
          let signature = Data(base64Encoded: String(lines[0].dropFirst(13))),
          let length = Int(lines[1].dropFirst(8)) else {
        throw NSError(domain: "WindowPilot.UpdateVerification", code: 4)
    }
    let content = Data(feed[..<block.lowerBound])
    try require(content.count == length, "Feed length mismatch")
    try require(key.isValidSignature(signature, for: content), "Invalid feed signature")
    let delegate = EnclosureParser()
    let parser = XMLParser(data: content)
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    try require(parser.parse() && delegate.signatures.count == 1, "Expected exactly one signed update")
    guard let archiveSignature = Data(base64Encoded: delegate.signatures[0]) else {
        throw NSError(domain: "WindowPilot.UpdateVerification", code: 5)
    }
    let archive = try Data(contentsOf: URL(fileURLWithPath: args[2]), options: .mappedIfSafe)
    try require(key.isValidSignature(archiveSignature, for: archive), "Invalid archive signature")
    print("EdDSA verified: feed and archive match the embedded public key")
} catch {
    fputs("Update verification failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
