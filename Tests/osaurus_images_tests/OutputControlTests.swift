import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import osaurus_images

@Suite("Output Controls")
struct OutputControlTests {

  private enum PluginError: Error {
    case entryPointFailed
    case invokeFailed
    case invalidJSON
  }

  private func invoke(tool: String, args: [String: Any]) throws -> [String: Any] {
    guard let apiPtr = osaurus_plugin_entry() else {
      throw PluginError.entryPointFailed
    }

    let fnPtrSize = MemoryLayout<UnsafeRawPointer?>.stride
    let initPtr = apiPtr.load(
      fromByteOffset: fnPtrSize,
      as: (@convention(c) () -> UnsafeMutableRawPointer?).self)
    let ctx = initPtr()

    let invokePtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 4,
      as: (@convention(c) (
        UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
      ) -> UnsafePointer<CChar>?).self)
    let freeStringPtr = apiPtr.load(
      fromByteOffset: 0,
      as: (@convention(c) (UnsafePointer<CChar>?) -> Void).self)
    let destroyPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 2,
      as: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)
    defer { destroyPtr(ctx) }

    let data = try JSONSerialization.data(withJSONObject: args, options: [.sortedKeys])
    let payload = String(data: data, encoding: .utf8)!
    let resultPtr = payload.withCString { payloadPtr in
      tool.withCString { toolPtr in
        "tool".withCString { typePtr in
          invokePtr(ctx, typePtr, toolPtr, payloadPtr)
        }
      }
    }
    guard let resultPtr else { throw PluginError.invokeFailed }
    let result = String(cString: resultPtr)
    freeStringPtr(resultPtr)

    guard let resultData = result.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any]
    else {
      throw PluginError.invalidJSON
    }
    return json
  }

  private func makeTempImage(name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "osaurus-images-tests-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
      data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))

    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
  }

  @Test("rotate_image can write a derived output without modifying input")
  func rotateOutputPath() throws {
    let input = try makeTempImage(name: "input.png")
    let output = input.deletingLastPathComponent().appendingPathComponent("rotated.png")

    let result = try invoke(
      tool: "rotate_image",
      args: [
        "input_path": input.path,
        "degrees": 90,
        "output_path": output.path,
      ])

    #expect(result["error"] == nil)
    #expect(result["output_path"] as? String == output.path)
    #expect(FileManager.default.fileExists(atPath: input.path))
    #expect(FileManager.default.fileExists(atPath: output.path))
  }

  @Test("explicit output path refuses overwrite unless requested")
  func refusesOverwrite() throws {
    let input = try makeTempImage(name: "input.png")
    let output = try makeTempImage(name: "existing.png")

    let result = try invoke(
      tool: "resize_image",
      args: [
        "input_path": input.path,
        "width": 4,
        "output_path": output.path,
      ])

    #expect((result["error"] as? String)?.contains("already exists") == true)
  }

  @Test("dry_run reports overwrite status without writing")
  func dryRun() throws {
    let input = try makeTempImage(name: "input.png")
    let output = input.deletingLastPathComponent().appendingPathComponent("dry-run.png")

    let result = try invoke(
      tool: "crop_image",
      args: [
        "input_path": input.path,
        "x": 0,
        "y": 0,
        "width": 4,
        "height": 4,
        "output_path": output.path,
        "dry_run": true,
      ])

    #expect(result["success"] as? Bool == true)
    #expect(result["output_path"] as? String == output.path)
    #expect(result["would_overwrite"] as? Bool == false)
    #expect(!FileManager.default.fileExists(atPath: output.path))
  }
}
