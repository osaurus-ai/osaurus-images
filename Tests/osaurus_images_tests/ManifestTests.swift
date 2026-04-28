import Foundation
import Testing

@testable import osaurus_images

@Suite("Plugin Manifest")
struct ManifestTests {

  private enum ManifestError: Error {
    case entryPointFailed
    case nilManifest
    case invalidJSON
  }

  private func loadManifest() throws -> [String: Any] {
    guard let apiPtr = osaurus_plugin_entry() else {
      throw ManifestError.entryPointFailed
    }

    let fnPtrSize = MemoryLayout<UnsafeRawPointer?>.stride
    let initPtr = apiPtr.load(
      fromByteOffset: fnPtrSize,
      as: (@convention(c) () -> UnsafeMutableRawPointer?).self)
    let ctx = initPtr()

    let getManifestPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 3,
      as: (@convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?).self)
    guard let cStr = getManifestPtr(ctx) else {
      throw ManifestError.nilManifest
    }
    let jsonString = String(cString: cStr)

    let freeStringPtr = apiPtr.load(
      fromByteOffset: 0,
      as: (@convention(c) (UnsafePointer<CChar>?) -> Void).self)
    freeStringPtr(cStr)

    let destroyPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 2,
      as: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)
    destroyPtr(ctx)

    guard let data = jsonString.data(using: .utf8),
      let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw ManifestError.invalidJSON
    }
    return manifest
  }

  private func tools(from manifest: [String: Any]) -> [[String: Any]] {
    let capabilities = manifest["capabilities"] as? [String: Any]
    return capabilities?["tools"] as? [[String: Any]] ?? []
  }

  @Test("manifest is valid JSON with correct plugin_id")
  func pluginID() throws {
    let manifest = try loadManifest()
    #expect(manifest["plugin_id"] as? String == "osaurus.images")
  }

  @Test("manifest declares the expected image tools")
  func toolIDs() throws {
    let manifest = try loadManifest()
    let ids = Set(tools(from: manifest).compactMap { $0["id"] as? String })

    let expected: Set<String> = [
      "convert_image", "optimize_image", "rotate_image", "flip_image", "crop_image",
      "resize_image", "get_image_info", "strip_metadata", "adjust_colors", "apply_filter",
      "extract_colors", "add_watermark", "composite_images", "add_border", "round_corners",
    ]

    #expect(ids == expected)
  }

  @Test("read-only inspection tools use auto permission and mutating tools require approval")
  func permissionPolicies() throws {
    let manifest = try loadManifest()
    let toolMap = Dictionary(
      uniqueKeysWithValues: tools(from: manifest).compactMap { tool -> (String, [String: Any])? in
        guard let id = tool["id"] as? String else { return nil }
        return (id, tool)
      })

    let autoTools: Set<String> = ["get_image_info", "extract_colors"]
    for id in autoTools {
      #expect(toolMap[id]?["permission_policy"] as? String == "auto")
    }

    for (id, tool) in toolMap where !autoTools.contains(id) {
      #expect(tool["permission_policy"] as? String == "ask", "Tool '\(id)' should ask")
    }
  }

  @Test("tools with file inputs declare required path parameters")
  func requiredPathParameters() throws {
    let manifest = try loadManifest()
    let toolMap = Dictionary(
      uniqueKeysWithValues: tools(from: manifest).compactMap { tool -> (String, [String: Any])? in
        guard let id = tool["id"] as? String else { return nil }
        return (id, tool)
      })

    let inputPathTools = [
      "convert_image", "optimize_image", "rotate_image", "flip_image", "crop_image",
      "resize_image", "get_image_info", "strip_metadata", "adjust_colors", "apply_filter",
      "extract_colors", "add_watermark", "add_border", "round_corners",
    ]

    for id in inputPathTools {
      let params = toolMap[id]?["parameters"] as? [String: Any]
      let required = params?["required"] as? [String] ?? []
      #expect(required.contains("input_path"), "Tool '\(id)' should require input_path")
    }

    let compositeParams = toolMap["composite_images"]?["parameters"] as? [String: Any]
    let compositeRequired = compositeParams?["required"] as? [String] ?? []
    #expect(compositeRequired.contains("base_path"))
    #expect(compositeRequired.contains("overlay_path"))
  }
}
