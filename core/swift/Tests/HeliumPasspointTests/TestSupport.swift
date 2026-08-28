import Foundation
import Security
import XCTest

@testable import HeliumPasspoint

/// Locates `core/testdata/`, the fixture directory shared with the Kotlin and
/// TypeScript suites. Derived from `#filePath` so it does not depend on the
/// working directory the tests happen to be launched from.
enum Fixtures {
  static let directory: URL = {
    // …/core/swift/Tests/HeliumPasspointTests/TestSupport.swift
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // …/Tests/HeliumPasspointTests
      .deletingLastPathComponent()  // …/Tests
      .deletingLastPathComponent()  // …/swift
      .deletingLastPathComponent()  // …/core
      .appendingPathComponent("testdata")
  }()

  static func url(_ name: String) -> URL {
    directory.appendingPathComponent(name)
  }

  static func string(_ name: String) throws -> String {
    try String(contentsOf: url(name), encoding: .utf8)
  }

  static func data(_ name: String) throws -> Data {
    try Data(contentsOf: url(name))
  }

  /// `core/contract/contract.json`, the cross-SDK source of truth.
  static func contract() throws -> [String: Any] {
    let url =
      directory
      .deletingLastPathComponent()  // core
      .appendingPathComponent("contract/contract.json")
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw TestError("contract.json is not a JSON object")
    }
    return object
  }
}

struct TestError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

/// An in-memory RSA keypair. `kSecAttrIsPermanent: false` keeps it out of the
/// developer's keychain, so the suite leaves no trace on the machine.
enum TestKeys {
  static func ephemeralRSAKeyPair(bits: Int = 2048) throws -> SecKeyPair {
    let params: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecAttrKeySizeInBits as String: bits,
      kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: false],
    ]
    var error: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey(params as CFDictionary, &error) else {
      throw TestError(
        "key generation failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
    }
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      throw TestError("could not derive public key")
    }
    return SecKeyPair(privateKey: privateKey, publicKey: publicKey)
  }
}

/// Canned ``HTTPTransport`` for exercising ``ProfileAPIClient`` without a network.
final class StubTransport: HTTPTransport {
  enum Outcome {
    case response(status: Int, body: Data)
    case failure(Error)
  }

  private(set) var requests: [URLRequest] = []
  private var outcomes: [Outcome]

  init(_ outcomes: [Outcome]) {
    self.outcomes = outcomes
  }

  convenience init(status: Int, body: String) {
    self.init([.response(status: status, body: Data(body.utf8))])
  }

  convenience init(failure: Error) {
    self.init([.failure(failure)])
  }

  var lastRequest: URLRequest? { requests.last }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    guard !outcomes.isEmpty else { throw TestError("StubTransport ran out of outcomes") }
    switch outcomes.removeFirst() {
    case .failure(let error):
      throw error
    case .response(let status, let body):
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
      return (body, response)
    }
  }
}

extension XCTestCase {
  /// Assert that `expression` throws a ``PasspointError`` carrying `code`.
  func assertThrowsPasspointError<T>(
    _ code: PasspointErrorCode,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: () async throws -> T
  ) async {
    do {
      _ = try await expression()
      XCTFail("expected PasspointError.\(code.rawValue), but nothing was thrown", file: file, line: line)
    } catch let error as PasspointError {
      XCTAssertEqual(error.code, code, "wrong error code", file: file, line: line)
    } catch {
      XCTFail("expected PasspointError, got \(error)", file: file, line: line)
    }
  }
}
