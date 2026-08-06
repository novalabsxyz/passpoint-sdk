import Foundation
import XCTest

@testable import HeliumPasspoint

/// The DER writer is hand-rolled, so its edge cases get direct coverage rather
/// than only being exercised through a 2048-bit CSR (which never reaches them).
final class DERTests: XCTestCase {

  // MARK: - Length

  func testShortFormLengths() {
    XCTAssertEqual(DER.length(0), Data([0x00]))
    XCTAssertEqual(DER.length(1), Data([0x01]))
    XCTAssertEqual(DER.length(127), Data([0x7F]))
  }

  func testLongFormSwitchesAt128() {
    XCTAssertEqual(DER.length(128), Data([0x81, 0x80]))
    XCTAssertEqual(DER.length(255), Data([0x81, 0xFF]))
  }

  func testLongFormTwoBytes() {
    XCTAssertEqual(DER.length(256), Data([0x82, 0x01, 0x00]))
    XCTAssertEqual(DER.length(65535), Data([0x82, 0xFF, 0xFF]))
  }

  /// The previous implementation truncated anything above 0xFFFF into two
  /// bytes, silently corrupting the encoding.
  func testLongFormThreeBytes() {
    XCTAssertEqual(DER.length(65536), Data([0x83, 0x01, 0x00, 0x00]))
    XCTAssertEqual(DER.length(0x123456), Data([0x83, 0x12, 0x34, 0x56]))
  }

  func testLengthUsesTheMinimumNumberOfBytes() {
    for length in [0, 1, 127, 128, 255, 256, 65535, 65536, 1 << 24] {
      let encoded = DER.length(length)
      guard encoded[0] & 0x80 != 0 else { continue }
      let count = Int(encoded[0] & 0x7F)
      XCTAssertEqual(encoded.count, count + 1, "length \(length)")
      XCTAssertNotEqual(encoded[1], 0x00, "leading zero byte is not minimal, length \(length)")
    }
  }

  // MARK: - Integer

  func testIntegerZeroIsASingleZeroByte() {
    XCTAssertEqual(DER.integer(0), Data([0x02, 0x01, 0x00]))
  }

  func testSmallPositiveIntegers() {
    XCTAssertEqual(DER.integer(1), Data([0x02, 0x01, 0x01]))
    XCTAssertEqual(DER.integer(127), Data([0x02, 0x01, 0x7F]))
  }

  /// Values with the top bit set need a 0x00 prefix or they read as negative.
  func testIntegerPadsWhenTheHighBitIsSet() {
    XCTAssertEqual(DER.integer(128), Data([0x02, 0x02, 0x00, 0x80]))
    XCTAssertEqual(DER.integer(255), Data([0x02, 0x02, 0x00, 0xFF]))
  }

  func testMultiByteIntegers() {
    XCTAssertEqual(DER.integer(256), Data([0x02, 0x02, 0x01, 0x00]))
    XCTAssertEqual(DER.integer(0x7FFF), Data([0x02, 0x02, 0x7F, 0xFF]))
    XCTAssertEqual(DER.integer(0x8000), Data([0x02, 0x03, 0x00, 0x80, 0x00]))
  }

  // MARK: - Containers

  func testSequenceWrapsWithTag0x30() {
    XCTAssertEqual(DER.sequence(Data([0xAA, 0xBB])), Data([0x30, 0x02, 0xAA, 0xBB]))
  }

  func testSetWrapsWithTag0x31() {
    XCTAssertEqual(DER.set(Data([0xAA])), Data([0x31, 0x01, 0xAA]))
  }

  func testBitStringPrefixesTheUnusedBitCount() {
    XCTAssertEqual(DER.bitString(Data([0xFF])), Data([0x03, 0x02, 0x00, 0xFF]))
  }

  func testUTF8StringEncodesAsTag0x0C() {
    XCTAssertEqual(DER.utf8String("hi"), Data([0x0C, 0x02, 0x68, 0x69]))
  }

  func testNullIsTwoBytes() {
    XCTAssertEqual(DER.null(), Data([0x05, 0x00]))
  }

  func testLongContentGetsALongFormHeader() {
    let content = Data(repeating: 0x41, count: 300)
    let encoded = DER.sequence(content)
    XCTAssertEqual(encoded.prefix(4), Data([0x30, 0x82, 0x01, 0x2C]))
    XCTAssertEqual(encoded.count, 4 + 300)
  }
}
