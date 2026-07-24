import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import osaurus_images

final class ImagesToolTests: XCTestCase {

  private var tempDir: URL!

  override func setUpWithError() throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("osaurus-images-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  // MARK: - Helpers

  private func invoke(_ tool: String, _ args: [String: Any]) throws -> [String: Any] {
    let fn = try XCTUnwrap(tools[tool], "unknown tool \(tool)")
    let payload = String(
      data: try JSONSerialization.data(withJSONObject: args), encoding: .utf8)!
    let result = fn(payload)
    let data = try XCTUnwrap(result.data(using: .utf8))
    return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func assertFailure(
    _ result: [String: Any], kind: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(result["ok"] as? Bool, false, "expected failure: \(result)", file: file, line: line)
    XCTAssertEqual(result["kind"] as? String, kind, "\(result)", file: file, line: line)
  }

  @discardableResult
  private func writeRGBImage(
    to url: URL, width: Int = 100, height: Int = 100,
    color: (r: CGFloat, g: CGFloat, b: CGFloat) = (0, 0, 1)
  ) throws -> URL {
    let ctx = try XCTUnwrap(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try XCTUnwrap(ctx.makeImage())
    try save(image, to: url)
    return url
  }

  /// Grayscale (8-bit, single channel, no alpha) image with 1px vertical
  /// black/white stripes.
  private func writeGrayStripeImage(to url: URL, width: Int = 100, height: Int = 20) throws {
    let ctx = try XCTUnwrap(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue))
    for x in 0..<width {
      let white = x % 2 == 1
      ctx.setFillColor(gray: white ? 1 : 0, alpha: 1)
      ctx.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }
    let image = try XCTUnwrap(ctx.makeImage())
    XCTAssertEqual(image.bitsPerPixel, 8, "fixture must stay single-channel grayscale")
    try save(image, to: url)
  }

  private func save(_ image: CGImage, to url: URL) throws {
    let dest = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
  }

  private func loadPixel(_ url: URL) throws -> CGImage {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }

  // MARK: - Path containment

  func testSiblingPrefixDirectoryEscapeRejected() throws {
    let workDir = tempDir.appendingPathComponent("project")
    let evilDir = tempDir.appendingPathComponent("project-evil")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: evilDir, withIntermediateDirectories: true)
    try writeRGBImage(to: evilDir.appendingPathComponent("img.png"))

    let result = try invoke(
      "get_image_info",
      [
        "input_path": "../project-evil/img.png",
        "_context": ["working_directory": workDir.path],
      ])
    assertFailure(result, kind: "invalid_args")
    XCTAssertEqual(result["message"] as? String, "Path outside working directory")
  }

  func testSymlinkEscapeRejected() throws {
    let workDir = tempDir.appendingPathComponent("work")
    let outsideDir = tempDir.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
    try writeRGBImage(to: outsideDir.appendingPathComponent("secret.png"))
    try FileManager.default.createSymbolicLink(
      at: workDir.appendingPathComponent("link"), withDestinationURL: outsideDir)

    let result = try invoke(
      "get_image_info",
      [
        "input_path": "link/secret.png",
        "_context": ["working_directory": workDir.path],
      ])
    assertFailure(result, kind: "invalid_args")
    XCTAssertEqual(result["message"] as? String, "Path outside working directory")
  }

  func testPathInsideWorkingDirectoryAccepted() throws {
    let workDir = tempDir.appendingPathComponent("work")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    try writeRGBImage(to: workDir.appendingPathComponent("img.png"))

    let result = try invoke(
      "get_image_info",
      [
        "input_path": "img.png",
        "_context": ["working_directory": workDir.path],
      ])
    XCTAssertEqual(result["width"] as? Int, 100, "\(result)")
  }

  // MARK: - extract_colors on grayscale input

  func testExtractColorsGrayscaleImage() throws {
    let url = tempDir.appendingPathComponent("stripes.png")
    try writeGrayStripeImage(to: url)

    let result = try invoke("extract_colors", ["input_path": url.path, "count": 5])
    let colors = try XCTUnwrap(result["colors"] as? [String], "\(result)")
    XCTAssertFalse(colors.isEmpty)
    for hex in colors {
      XCTAssertEqual(hex.count, 7)
      let r = hex.dropFirst().prefix(2)
      let g = hex.dropFirst(3).prefix(2)
      let b = hex.dropFirst(5).prefix(2)
      XCTAssertTrue(r == g && g == b, "grayscale image produced non-gray color \(hex)")
    }
  }

  // MARK: - hex color validation

  func testAddBorderRejectsNonHexColor() throws {
    let url = tempDir.appendingPathComponent("img.png")
    try writeRGBImage(to: url)

    let result = try invoke(
      "add_border", ["input_path": url.path, "width": 5, "color": "GGGGGG"])
    assertFailure(result, kind: "invalid_args")
  }

  func testAddBorderAcceptsValidHexColor() throws {
    let url = tempDir.appendingPathComponent("img.png")
    try writeRGBImage(to: url, width: 50, height: 50)

    let result = try invoke(
      "add_border", ["input_path": url.path, "width": 5, "color": "#FF0000"])
    XCTAssertEqual(result["success"] as? Bool, true, "\(result)")
    XCTAssertEqual(result["new_width"] as? Int, 60)
  }

  // MARK: - documented parameter ranges

  func testAdjustColorsRejectsOutOfRangeValues() throws {
    let url = tempDir.appendingPathComponent("img.png")
    try writeRGBImage(to: url)

    assertFailure(
      try invoke("adjust_colors", ["input_path": url.path, "brightness": 5.0]),
      kind: "invalid_args")
    assertFailure(
      try invoke("adjust_colors", ["input_path": url.path, "contrast": -1.0]),
      kind: "invalid_args")
    assertFailure(
      try invoke("adjust_colors", ["input_path": url.path, "saturation": 3.0]),
      kind: "invalid_args")
  }

  func testApplyFilterRejectsOutOfRangeIntensity() throws {
    let url = tempDir.appendingPathComponent("img.png")
    try writeRGBImage(to: url)

    assertFailure(
      try invoke("apply_filter", ["input_path": url.path, "filter": "sepia", "intensity": 2.0]),
      kind: "invalid_args")
  }

  func testAddWatermarkRejectsUnknownPosition() throws {
    let url = tempDir.appendingPathComponent("img.png")
    try writeRGBImage(to: url)

    assertFailure(
      try invoke(
        "add_watermark", ["input_path": url.path, "text": "X", "position": "diagonal"]),
      kind: "invalid_args")
  }

  func testOptimizeRejectsOutOfRangeQuality() throws {
    let url = tempDir.appendingPathComponent("img.png")
    try writeRGBImage(to: url)

    assertFailure(
      try invoke("optimize_image", ["input_path": url.path, "quality": 1.5]),
      kind: "invalid_args")
  }

  // MARK: - atomic writes

  func testRotateOverwritesInputAtomically() throws {
    let url = tempDir.appendingPathComponent("img.png")
    try writeRGBImage(to: url, width: 40, height: 20)

    let result = try invoke("rotate_image", ["input_path": url.path, "degrees": 90])
    XCTAssertEqual(result["success"] as? Bool, true, "\(result)")

    let rotated = try loadPixel(url)
    XCTAssertEqual(rotated.width, 20)
    XCTAssertEqual(rotated.height, 40)

    let leftovers = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
      .filter { $0.contains(".tmp-") }
    XCTAssertEqual(leftovers, [], "temp files must not be left behind")
  }

  func testFailedSaveLeavesDestinationIntact() throws {
    let url = tempDir.appendingPathComponent("img.gif")
    let ctx = try XCTUnwrap(
      CGContext(
        data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
    let image = try XCTUnwrap(ctx.makeImage())
    let dest = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
    let originalData = try Data(contentsOf: url)

    // Deleting write permission on the directory forces the temp-file write to
    // fail; the original file must remain untouched.
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: tempDir.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
    }

    let result = try invoke("rotate_image", ["input_path": url.path, "degrees": 90])
    assertFailure(result, kind: "execution_error")
    XCTAssertEqual(try Data(contentsOf: url), originalData)
  }

  // MARK: - basic tool coverage (replaces the old ad-hoc test_plugin.swift script)

  func testConvertResizeCropFlipRoundTrip() throws {
    let url = tempDir.appendingPathComponent("img.png")
    try writeRGBImage(to: url, width: 100, height: 80)

    var result = try invoke(
      "convert_image", ["input_path": url.path, "output_format": "jpeg"])
    let jpegPath = try XCTUnwrap(result["output_path"] as? String, "\(result)")
    XCTAssertTrue(FileManager.default.fileExists(atPath: jpegPath))

    result = try invoke("resize_image", ["input_path": url.path, "width": 50])
    XCTAssertEqual(result["width"] as? Int, 50)
    XCTAssertEqual(result["height"] as? Int, 40)

    result = try invoke(
      "crop_image", ["input_path": url.path, "x": 0, "y": 0, "width": 30, "height": 20])
    XCTAssertEqual(result["success"] as? Bool, true, "\(result)")

    result = try invoke("flip_image", ["input_path": url.path, "direction": "horizontal"])
    XCTAssertEqual(result["direction"] as? String, "horizontal")

    result = try invoke("extract_colors", ["input_path": url.path])
    XCTAssertNotNil(result["colors"] as? [String], "\(result)")
  }

  func testManifestVersionMatchesRelease() throws {
    let data = try XCTUnwrap(imagesManifestJSON.data(using: .utf8))
    let manifest = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(manifest["version"] as? String, "1.0.4")
  }
}
