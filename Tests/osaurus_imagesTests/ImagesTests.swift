import XCTest

@testable import osaurus_images

final class ImagesTests: XCTestCase {

  private func parsedManifest() throws -> [String: Any] {
    let data = try XCTUnwrap(imagesManifestJSON.data(using: .utf8))
    let obj = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(obj as? [String: Any])
  }

  func testManifestTopLevelFields() throws {
    let manifest = try parsedManifest()
    XCTAssertEqual(manifest["plugin_id"] as? String, "osaurus.images")
    XCTAssertEqual(manifest["name"] as? String, "Images")
  }

  func testManifestToolsHaveIdAndDescription() throws {
    let manifest = try parsedManifest()
    let capabilities = try XCTUnwrap(manifest["capabilities"] as? [String: Any])
    let tools = try XCTUnwrap(capabilities["tools"] as? [[String: Any]])

    let expected: Set<String> = [
      "convert_image", "optimize_image", "rotate_image", "flip_image", "crop_image",
      "resize_image", "get_image_info", "strip_metadata", "adjust_colors", "apply_filter",
      "extract_colors", "add_watermark", "composite_images", "add_border", "round_corners",
    ]
    XCTAssertEqual(tools.count, expected.count)

    var seen = Set<String>()
    for tool in tools {
      let id = try XCTUnwrap(tool["id"] as? String)
      let description = try XCTUnwrap(tool["description"] as? String)
      XCTAssertFalse(id.trimmingCharacters(in: .whitespaces).isEmpty, "empty id")
      XCTAssertFalse(
        description.trimmingCharacters(in: .whitespaces).isEmpty, "empty description for \(id)")
      seen.insert(id)
    }
    XCTAssertEqual(seen, expected)
  }

  func testEnvelopeFailureRoundTrip() throws {
    let cases: [(Envelope.Kind, String, Bool)] = [
      (.invalidArgs, "bad params", true),
      (.executionError, "boom", true),
      (.notFound, "missing file", false),
      (.unavailable, "offline", true),
    ]
    for (kind, message, expectedRetryable) in cases {
      let json = Envelope.failure(kind, message)
      let data = try XCTUnwrap(json.data(using: .utf8))
      let obj = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: data) as? [String: Any])
      XCTAssertEqual(obj["ok"] as? Bool, false)
      XCTAssertEqual(obj["kind"] as? String, kind.rawValue)
      XCTAssertEqual(obj["message"] as? String, message)
      XCTAssertEqual(obj["retryable"] as? Bool, expectedRetryable)
    }
  }

  func testEnvelopeFailureExplicitRetryableOverride() throws {
    let json = Envelope.failure(.notFound, "missing", retryable: true)
    let data = try XCTUnwrap(json.data(using: .utf8))
    let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(obj["retryable"] as? Bool, true)
  }

  func testEnvelopeFailureEscapesSpecialCharacters() throws {
    let json = Envelope.failure(.executionError, "line\nbreak \"quote\" \\slash")
    let data = try XCTUnwrap(json.data(using: .utf8))
    let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(obj["message"] as? String, "line\nbreak \"quote\" \\slash")
  }
}
