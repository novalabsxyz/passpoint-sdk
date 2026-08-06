import Foundation
import Security
import XCTest

@testable import HeliumPasspoint

final class CertificateStoreTests: XCTestCase {

  // MARK: - PEM

  func testParsesAPEMCertificate() throws {
    let certificate = try XCTUnwrap(CertificateStore.parsePEM(Fixtures.string("testLeaf.crt")))
    let subject = try XCTUnwrap(CertificateStore.subjectSummary(of: certificate))
    XCTAssertEqual(subject, "anonymous@subscriber-42.helium.example")
  }

  func testParsesPEMWithCRLFLineEndings() throws {
    let crlf = try Fixtures.string("testLeaf.crt").replacingOccurrences(of: "\n", with: "\r\n")
    XCTAssertNotNil(CertificateStore.parsePEM(crlf))
  }

  func testParsesPEMWithoutATrailingNewline() throws {
    let trimmed = try Fixtures.string("testLeaf.crt").trimmingCharacters(
      in: .whitespacesAndNewlines)
    XCTAssertNotNil(CertificateStore.parsePEM(trimmed))
  }

  func testRejectsGarbage() {
    XCTAssertNil(CertificateStore.parsePEM(""))
    XCTAssertNil(
      CertificateStore.parsePEM("-----BEGIN CERTIFICATE-----\nnot base64 !!!\n-----END CERTIFICATE-----"))
  }

  // MARK: - notAfter

  /// X.509 uses UTCTime for years before 2050.
  func testReadsUTCTimeExpiry() throws {
    let certificate = try XCTUnwrap(CertificateStore.parsePEM(Fixtures.string("testLeaf.crt")))
    let expiry = try XCTUnwrap(CertificateStore.expirationDate(of: certificate))
    XCTAssertEqual(ISO8601.string(from: expiry), "2035-01-01T00:00:00Z")
  }

  /// …and GeneralizedTime from 2050 onwards. Both paths are live code.
  func testReadsGeneralizedTimeExpiry() throws {
    let certificate = try XCTUnwrap(
      CertificateStore.parsePEM(Fixtures.string("testLeafGeneralized.crt")))
    let expiry = try XCTUnwrap(CertificateStore.expirationDate(of: certificate))
    XCTAssertEqual(ISO8601.string(from: expiry), "2060-01-01T00:00:00Z")
  }

  func testExpiryMatchesWhatTheSecurityFrameworkParsed() throws {
    let pem = try Fixtures.string("testLeaf.crt")
    let der = try XCTUnwrap(CertificateStore.derData(fromPEM: pem))
    let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, der as CFData))

    XCTAssertEqual(
      CertificateStore.notAfter(derEncoded: der),
      CertificateStore.expirationDate(of: certificate))
  }

  // MARK: - Robustness

  /// The DER reader runs on bytes returned by a remote service. Every
  /// truncation must return nil rather than trap on an out-of-range index.
  func testTruncatedDERNeverCrashes() throws {
    let der = try XCTUnwrap(CertificateStore.derData(fromPEM: Fixtures.string("testLeaf.crt")))
    for length in 0..<min(der.count, 200) {
      _ = CertificateStore.notAfter(derEncoded: der.prefix(length))
    }
    // A prefix short of the validity field cannot yield a date.
    XCTAssertNil(CertificateStore.notAfter(derEncoded: der.prefix(40)))
  }

  func testCorruptedLengthBytesReturnNil() throws {
    var der = [UInt8](try XCTUnwrap(CertificateStore.derData(fromPEM: Fixtures.string("testLeaf.crt"))))
    // 0xFF as a length header claims 127 length bytes, far past the buffer.
    der[1] = 0xFF
    XCTAssertNil(CertificateStore.notAfter(derEncoded: Data(der)))
  }

  func testEmptyInputReturnsNil() {
    XCTAssertNil(CertificateStore.notAfter(derEncoded: Data()))
    XCTAssertNil(CertificateStore.notAfter(derEncoded: Data([0x30])))
  }

  func testNonSequenceRootReturnsNil() {
    XCTAssertNil(CertificateStore.notAfter(derEncoded: Data([0x02, 0x01, 0x00])))
  }
}
