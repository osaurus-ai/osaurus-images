import OsaurusPluginTestSupport
import XCTest

@testable import osaurus_images

/// SDK conformance checks: manifest contract, ABI entry-point contract
/// (via the plugin's real exported entry points), and the canonical
/// failure envelope emitted by a real tool invocation.
final class SDKConformanceTests: XCTestCase {

  func testManifestConformance() throws {
    try ManifestConformance.assertConformant(imagesManifestJSON)
  }

  func testEntryV2Conformance() throws {
    try ABIConformance.assertEntryConformance(
      osaurus_plugin_entry_v2(nil), manifestJSON: imagesManifestJSON)
  }

  func testEntryV1Conformance() throws {
    try ABIConformance.assertEntryConformance(
      osaurus_plugin_entry(), manifestJSON: imagesManifestJSON)
  }

  func testToolFailureIsCanonical() throws {
    let json = try XCTUnwrap(tools["get_image_info"])("not json")
    try assertCanonicalFailure(json, kind: .invalidArgs)
  }
}
