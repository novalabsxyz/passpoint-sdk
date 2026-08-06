import Foundation
import Security
import XCTest

@testable import HeliumPasspoint

final class CSRGeneratorTests: XCTestCase {
  private var keyPair: SecKeyPair!

  override func setUpWithError() throws {
    try super.setUpWithError()
    keyPair = try TestKeys.ephemeralRSAKeyPair()
  }

  // MARK: - Shape

  func testProducesPEMArmouredRequest() throws {
    let pem = try CSRGenerator().generate(subscriberID: "subscriber-42", keyPair: keyPair)

    XCTAssertTrue(pem.hasPrefix("-----BEGIN CERTIFICATE REQUEST-----\n"))
    XCTAssertTrue(pem.hasSuffix("\n-----END CERTIFICATE REQUEST-----"))
    XCTAssertNotNil(Self.der(fromPEM: pem), "body must be valid base64")
  }

  func testCommonNameCarriesTheDomainSentinel() {
    XCTAssertEqual(
      CSRGenerator.commonName(subscriberID: "subscriber-42"),
      "anonymous@subscriber-42.DOMAIN")
  }

  func testEncodedSubjectContainsTheCommonName() throws {
    let pem = try CSRGenerator().generate(subscriberID: "sub-abc", keyPair: keyPair)
    let der = try XCTUnwrap(Self.der(fromPEM: pem))

    let expected = Data("anonymous@sub-abc.DOMAIN".utf8)
    XCTAssertTrue(
      Self.contains(der, expected),
      "the UTF8String CN should appear verbatim in the DER")
  }

  // MARK: - Signature

  /// The strongest self-contained check: re-verify the PKCS#10 signature over
  /// the exact `certificationRequestInfo` bytes. This only passes if every
  /// length header we emitted is correct, because an off-by-one anywhere shifts
  /// the signed range.
  func testSignatureVerifiesOverCertificationRequestInfo() throws {
    let pem = try CSRGenerator().generate(subscriberID: "subscriber-42", keyPair: keyPair)
    let der = try XCTUnwrap(Self.der(fromPEM: pem))

    let outer = try XCTUnwrap(Self.tlv(in: der, at: 0), "outer SEQUENCE")
    XCTAssertEqual(outer.tag, 0x30)
    XCTAssertEqual(outer.end, der.count, "no trailing bytes after the CSR")

    let requestInfo = try XCTUnwrap(Self.tlv(in: der, at: outer.contentStart), "requestInfo")
    let signatureAlgorithm = try XCTUnwrap(Self.tlv(in: der, at: requestInfo.end), "sigAlg")
    let signatureBits = try XCTUnwrap(Self.tlv(in: der, at: signatureAlgorithm.end), "signature")

    XCTAssertEqual(signatureBits.tag, 0x03, "signature must be a BIT STRING")
    XCTAssertEqual(signatureBits.end, outer.end, "signature is the final element")
    XCTAssertEqual(
      der[signatureBits.contentStart], 0x00, "BIT STRING must declare zero unused bits")

    let signedBytes = der[outer.contentStart..<requestInfo.end]
    let signature = der[(signatureBits.contentStart + 1)..<signatureBits.end]

    var error: Unmanaged<CFError>?
    let ok = SecKeyVerifySignature(
      keyPair.publicKey,
      .rsaSignatureMessagePKCS1v15SHA256,
      Data(signedBytes) as CFData,
      Data(signature) as CFData,
      &error)
    XCTAssertTrue(
      ok, "signature did not verify: \(error?.takeRetainedValue().localizedDescription ?? "-")")
  }

  func testEmbeddedPublicKeyMatchesTheSigningKey() throws {
    let pem = try CSRGenerator().generate(subscriberID: "subscriber-42", keyPair: keyPair)
    let der = try XCTUnwrap(Self.der(fromPEM: pem))
    let exported = try XCTUnwrap(
      SecKeyCopyExternalRepresentation(keyPair.publicKey, nil) as Data?)

    XCTAssertTrue(
      Self.contains(der, exported),
      "the PKCS#1 RSAPublicKey should be embedded in the SubjectPublicKeyInfo")
  }

  /// A CSR that only our own parser accepts is not a CSR. Cross-check with a
  /// completely independent implementation when one is on the machine.
  ///
  /// The exit status is not enough: macOS's `/usr/bin/openssl` is LibreSSL,
  /// which prints `verify failure` and still exits 0. Assert on the output.
  func testOpenSSLAcceptsTheRequest() throws {
    guard let openssl = Self.opensslPath() else { throw XCTSkip("openssl not available") }

    let pem = try CSRGenerator().generate(subscriberID: "subscriber-42", keyPair: keyPair)
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("helium-csr-\(UUID().uuidString).pem")
    try pem.write(to: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: path) }

    let (status, output) = try Self.run(
      openssl, ["req", "-in", path.path, "-verify", "-noout", "-subject"])

    XCTAssertEqual(status, 0, "openssl rejected the CSR:\n\(output)")
    XCTAssertTrue(
      output.lowercased().contains("verify ok"),
      "openssl did not confirm the signature:\n\(output)")
    XCTAssertFalse(
      output.lowercased().contains("verify failure"),
      "openssl reported a signature failure:\n\(output)")
    XCTAssertTrue(
      output.contains("anonymous@subscriber-42.DOMAIN"),
      "openssl read a different subject:\n\(output)")
  }

  /// Proves the assertions above can fail: flip one byte of the signature and
  /// openssl must reject it. Without this, a change to how the cross-check is
  /// invoked could quietly stop checking anything.
  func testOpenSSLRejectsATamperedRequest() throws {
    guard let openssl = Self.opensslPath() else { throw XCTSkip("openssl not available") }

    let pem = try CSRGenerator().generate(subscriberID: "subscriber-42", keyPair: keyPair)
    var der = [UInt8](try XCTUnwrap(Self.der(fromPEM: pem)))
    der[der.count - 1] ^= 0xFF  // last byte of the signature BIT STRING
    let tampered = "-----BEGIN CERTIFICATE REQUEST-----\n"
      + Data(der).base64EncodedString(options: .lineLength64Characters)
      + "\n-----END CERTIFICATE REQUEST-----"

    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("helium-csr-bad-\(UUID().uuidString).pem")
    try tampered.write(to: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: path) }

    let (_, output) = try Self.run(openssl, ["req", "-in", path.path, "-verify", "-noout"])
    XCTAssertFalse(
      output.lowercased().contains("verify ok"),
      "a tampered signature was accepted — the cross-check proves nothing:\n\(output)")
  }

  /// Prefer a real OpenSSL if one is installed; fall back to system LibreSSL.
  private static func opensslPath() -> String? {
    let candidates = [
      "/opt/homebrew/opt/openssl@3/bin/openssl",
      "/usr/local/opt/openssl@3/bin/openssl",
      "/usr/bin/openssl",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  /// One unbroken base64 line, byte-for-byte the shape the Kotlin SDK emits —
  /// see `CsrGeneratorTest.body has no internal newlines`. `.lineLength64Characters`
  /// used to wrap this with CRLF, which made the two platforms send
  /// structurally different requests for the same input.
  ///
  /// Note: `String.contains("\r")` cannot detect this, because Swift treats
  /// CRLF as a single grapheme cluster. Count UTF-8 bytes instead.
  func testBodyIsASingleUnwrappedLine() throws {
    let pem = try CSRGenerator().generate(subscriberID: "subscriber-42", keyPair: keyPair)
    let body = pem.split(separator: "\n").dropFirst().dropLast()

    XCTAssertEqual(body.count, 1, "expected a single base64 line, got \(body.count)")
    XCTAssertFalse(Array(pem.utf8).contains(0x0D), "PEM body must contain no CR bytes")
    XCTAssertEqual(pem.utf8.filter { $0 == 0x0A }.count, 2, "only the two armour newlines")
  }

  // MARK: - Helpers

  private static func der(fromPEM pem: String) -> Data? {
    let body =
      pem
      .replacingOccurrences(of: "-----BEGIN CERTIFICATE REQUEST-----", with: "")
      .replacingOccurrences(of: "-----END CERTIFICATE REQUEST-----", with: "")
    return Data(base64Encoded: body, options: .ignoreUnknownCharacters)
  }

  private struct TLV {
    let tag: UInt8
    let contentStart: Int
    let end: Int
  }

  /// Minimal independent DER reader — deliberately *not* the one in the SDK, so
  /// a bug in `DER` cannot hide behind a matching bug in the test.
  private static func tlv(in data: Data, at offset: Int) -> TLV? {
    let bytes = [UInt8](data)
    guard offset + 1 < bytes.count else { return nil }
    let tag = bytes[offset]
    var cursor = offset + 1

    let first = bytes[cursor]
    cursor += 1
    var length = Int(first)
    if first & 0x80 != 0 {
      let count = Int(first & 0x7F)
      guard count > 0, cursor + count <= bytes.count else { return nil }
      length = 0
      for index in 0..<count { length = (length << 8) | Int(bytes[cursor + index]) }
      cursor += count
    }
    guard cursor + length <= bytes.count else { return nil }
    return TLV(tag: tag, contentStart: cursor, end: cursor + length)
  }

  private static func contains(_ haystack: Data, _ needle: Data) -> Bool {
    guard !needle.isEmpty, haystack.count >= needle.count else { return false }
    let h = [UInt8](haystack)
    let n = [UInt8](needle)
    for start in 0...(h.count - n.count) where Array(h[start..<(start + n.count)]) == n {
      return true
    }
    return false
  }

  private static func run(_ launchPath: String, _ arguments: [String]) throws -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
  }
}
