import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - JSON Response Helpers

private func jsonError(_ message: String) -> String {
  "{\"error\": \"\(ImageHelper.escapeJSON(message))\"}"
}

private func jsonSuccess(_ fields: [String: Any] = [:]) -> String {
  var parts = ["\"success\": true"]
  for (key, value) in fields {
    switch value {
    case let s as String: parts.append("\"\(key)\": \"\(ImageHelper.escapeJSON(s))\"")
    case let b as Bool: parts.append("\"\(key)\": \(b)")
    case let i as Int: parts.append("\"\(key)\": \(i)")
    case let d as Double: parts.append("\"\(key)\": \(d)")
    default: parts.append("\"\(key)\": \"\(value)\"")
    }
  }
  return "{\(parts.joined(separator: ", "))}"
}

// MARK: - Image Helper

private struct ImageHelper {
  static func loadImage(from path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return image
  }

  static func saveImage(_ image: CGImage, to path: String, format: UTType, quality: CGFloat = 1.0)
    -> Bool
  {
    guard
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, format.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(
      dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    return CGImageDestinationFinalize(dest)
  }

  static func createContext(width: Int, height: Int, colorSpace: CGColorSpace? = nil) -> CGContext?
  {
    CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  }

  static func getUTType(for format: String) -> UTType? {
    switch format.lowercased() {
    case "png": return .png
    case "jpeg", "jpg": return .jpeg
    case "gif": return .gif
    case "tiff", "tif": return .tiff
    case "bmp": return .bmp
    case "heic", "heif": return .heic
    case "webp": return .webP
    default: return nil
    }
  }

  static func getFormat(from path: String) -> UTType? {
    getUTType(for: (path as NSString).pathExtension)
  }

  static func escapeJSON(_ string: String) -> String {
    string.reduce(into: "") { result, char in
      switch char {
      case "\"": result += "\\\""
      case "\\": result += "\\\\"
      case "\n": result += "\\n"
      case "\r": result += "\\r"
      case "\t": result += "\\t"
      default: result.append(char)
      }
    }
  }

  static func hexToRGB(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
    let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
      of: "#", with: "")
    guard hex.count == 6 else { return nil }
    var rgb: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&rgb)
    return (
      CGFloat((rgb >> 16) & 0xFF) / 255, CGFloat((rgb >> 8) & 0xFF) / 255, CGFloat(rgb & 0xFF) / 255
    )
  }

  static func rgbToHex(_ r: Int, _ g: Int, _ b: Int) -> String {
    String(format: "#%02X%02X%02X", r, g, b)
  }

  static func fileSize(at path: String) -> Int {
    (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
  }
}

// MARK: - Tool Protocol

private protocol ImageTool {
  associatedtype Args: Decodable
  var name: String { get }
  func execute(input: Args) -> String
}

extension ImageTool {
  func run(args: String) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return jsonError("Invalid arguments")
    }
    return execute(input: input)
  }
}

// MARK: - Conversion Tools

private struct ConvertImageTool: ImageTool {
  let name = "convert_image"
  struct Args: Decodable {
    let input_path: String
    let output_format: String
  }

  func execute(input: Args) -> String {
    guard let image = ImageHelper.loadImage(from: input.input_path) else {
      return jsonError("Failed to load image: \(input.input_path)")
    }
    guard let format = ImageHelper.getUTType(for: input.output_format) else {
      return jsonError("Unsupported format: \(input.output_format)")
    }
    let outputPath = URL(fileURLWithPath: input.input_path)
      .deletingPathExtension().appendingPathExtension(input.output_format.lowercased()).path
    guard ImageHelper.saveImage(image, to: outputPath, format: format) else {
      return jsonError("Failed to save converted image")
    }
    return jsonSuccess(["output_path": outputPath])
  }
}

private struct OptimizeImageTool: ImageTool {
  let name = "optimize_image"
  struct Args: Decodable {
    let input_path: String
    let quality: Double?
  }

  func execute(input: Args) -> String {
    guard let image = ImageHelper.loadImage(from: input.input_path) else {
      return jsonError("Failed to load image: \(input.input_path)")
    }
    guard let format = ImageHelper.getFormat(from: input.input_path) else {
      return jsonError("Could not determine image format")
    }
    let originalSize = ImageHelper.fileSize(at: input.input_path)
    guard
      ImageHelper.saveImage(
        image, to: input.input_path, format: format, quality: CGFloat(input.quality ?? 0.8))
    else {
      return jsonError("Failed to optimize image")
    }
    let newSize = ImageHelper.fileSize(at: input.input_path)
    return jsonSuccess([
      "original_size": originalSize, "new_size": newSize, "saved_bytes": originalSize - newSize,
    ])
  }
}

// MARK: - Manipulation Tools

private struct RotateImageTool: ImageTool {
  let name = "rotate_image"
  struct Args: Decodable {
    let input_path: String
    let degrees: Double
  }

  func execute(input: Args) -> String {
    guard let image = ImageHelper.loadImage(from: input.input_path) else {
      return jsonError("Failed to load image: \(input.input_path)")
    }
    guard let format = ImageHelper.getFormat(from: input.input_path) else {
      return jsonError("Could not determine image format")
    }

    let radians = input.degrees * .pi / 180.0
    let (width, height) = (image.width, image.height)
    let normalized = ((Int(input.degrees) % 360) + 360) % 360

    let (newWidth, newHeight): (Int, Int) = {
      switch normalized {
      case 90, 270: return (height, width)
      case 0, 180: return (width, height)
      default:
        let (cos, sin) = (abs(Foundation.cos(radians)), abs(Foundation.sin(radians)))
        return (
          Int(Double(width) * cos + Double(height) * sin),
          Int(Double(width) * sin + Double(height) * cos)
        )
      }
    }()

    guard
      let ctx = ImageHelper.createContext(
        width: newWidth, height: newHeight, colorSpace: image.colorSpace)
    else {
      return jsonError("Failed to create graphics context")
    }
    ctx.translateBy(x: CGFloat(newWidth) / 2, y: CGFloat(newHeight) / 2)
    ctx.rotate(by: CGFloat(radians))
    ctx.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let result = ctx.makeImage(),
      ImageHelper.saveImage(result, to: input.input_path, format: format)
    else {
      return jsonError("Failed to save rotated image")
    }
    return jsonSuccess(["degrees": input.degrees])
  }
}

private struct FlipImageTool: ImageTool {
  let name = "flip_image"
  struct Args: Decodable {
    let input_path: String
    let direction: String
  }

  func execute(input: Args) -> String {
    guard let image = ImageHelper.loadImage(from: input.input_path) else {
      return jsonError("Failed to load image: \(input.input_path)")
    }
    guard let format = ImageHelper.getFormat(from: input.input_path) else {
      return jsonError("Could not determine image format")
    }
    let direction = input.direction.lowercased()
    guard direction == "horizontal" || direction == "vertical" else {
      return jsonError("Direction must be 'horizontal' or 'vertical'")
    }

    let (width, height) = (image.width, image.height)
    guard
      let ctx = ImageHelper.createContext(
        width: width, height: height, colorSpace: image.colorSpace)
    else {
      return jsonError("Failed to create graphics context")
    }

    if direction == "horizontal" {
      ctx.translateBy(x: CGFloat(width), y: 0)
      ctx.scaleBy(x: -1, y: 1)
    } else {
      ctx.translateBy(x: 0, y: CGFloat(height))
      ctx.scaleBy(x: 1, y: -1)
    }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let result = ctx.makeImage(),
      ImageHelper.saveImage(result, to: input.input_path, format: format)
    else {
      return jsonError("Failed to save flipped image")
    }
    return jsonSuccess(["direction": direction])
  }
}

private struct CropImageTool: ImageTool {
  let name = "crop_image"
  struct Args: Decodable {
    let input_path: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
  }

  func execute(input: Args) -> String {
    guard let image = ImageHelper.loadImage(from: input.input_path) else {
      return jsonError("Failed to load image: \(input.input_path)")
    }
    guard let format = ImageHelper.getFormat(from: input.input_path) else {
      return jsonError("Could not determine image format")
    }
    guard input.x >= 0, input.y >= 0, input.width > 0, input.height > 0 else {
      return jsonError("Invalid crop dimensions")
    }
    guard input.x + input.width <= image.width, input.y + input.height <= image.height else {
      return jsonError("Crop region exceeds image bounds")
    }

    let cropRect = CGRect(
      x: input.x, y: image.height - input.y - input.height, width: input.width, height: input.height
    )
    guard let cropped = image.cropping(to: cropRect),
      ImageHelper.saveImage(cropped, to: input.input_path, format: format)
    else {
      return jsonError("Failed to crop image")
    }
    return jsonSuccess(["width": input.width, "height": input.height])
  }
}

private struct ResizeImageTool: ImageTool {
  let name = "resize_image"
  struct Args: Decodable {
    let input_path: String
    let width: Int?
    let height: Int?
    let scale: Double?
  }

  func execute(input: Args) -> String {
    guard let image = ImageHelper.loadImage(from: input.input_path) else {
      return jsonError("Failed to load image: \(input.input_path)")
    }
    guard let format = ImageHelper.getFormat(from: input.input_path) else {
      return jsonError("Could not determine image format")
    }

    let (origW, origH) = (image.width, image.height)
    let (newW, newH): (Int, Int)

    if let scale = input.scale {
      newW = Int(Double(origW) * scale / 100.0)
      newH = Int(Double(origH) * scale / 100.0)
    } else if let w = input.width, let h = input.height {
      (newW, newH) = (w, h)
    } else if let w = input.width {
      newW = w
      newH = Int(Double(origH) * Double(w) / Double(origW))
    } else if let h = input.height {
      newH = h
      newW = Int(Double(origW) * Double(h) / Double(origH))
    } else {
      return jsonError("Must specify width, height, or scale")
    }

    guard newW > 0, newH > 0 else { return jsonError("Invalid dimensions") }
    guard
      let ctx = ImageHelper.createContext(width: newW, height: newH, colorSpace: image.colorSpace)
    else {
      return jsonError("Failed to create graphics context")
    }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))

    guard let result = ctx.makeImage(),
      ImageHelper.saveImage(result, to: input.input_path, format: format)
    else {
      return jsonError("Failed to save resized image")
    }
    return jsonSuccess(["width": newW, "height": newH])
  }
}

// MARK: - Metadata Tools

private struct GetImageInfoTool: ImageTool {
  let name = "get_image_info"
  struct Args: Decodable { let input_path: String }

  func execute(input: Args) -> String {
    let url = URL(fileURLWithPath: input.input_path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
      return jsonError("Failed to load image: \(input.input_path)")
    }

    let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
    let colorModel = props[kCGImagePropertyColorModel] as? String ?? "Unknown"
    let depth = props[kCGImagePropertyDepth] as? Int ?? 0
    let dpiW = props[kCGImagePropertyDPIWidth] as? Double ?? 72.0
    let dpiH = props[kCGImagePropertyDPIHeight] as? Double ?? 72.0
    let hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool ?? false
    let fileSize = ImageHelper.fileSize(at: input.input_path)
    let format =
      ImageHelper.getFormat(from: input.input_path)?.preferredFilenameExtension ?? "unknown"

    var exifJSON = "null"
    if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
      var parts: [String] = []
      if let dt = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
        parts.append("\"date_time\": \"\(ImageHelper.escapeJSON(dt))\"")
      }
      if let et = exif[kCGImagePropertyExifExposureTime] as? Double {
        parts.append("\"exposure_time\": \(et)")
      }
      if let fn = exif[kCGImagePropertyExifFNumber] as? Double {
        parts.append("\"f_number\": \(fn)")
      }
      if let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let v = iso.first {
        parts.append("\"iso\": \(v)")
      }
      if let fl = exif[kCGImagePropertyExifFocalLength] as? Double {
        parts.append("\"focal_length\": \(fl)")
      }
      if !parts.isEmpty { exifJSON = "{\(parts.joined(separator: ", "))}" }
    }

    return
      "{\"width\": \(width), \"height\": \(height), \"format\": \"\(format)\", \"file_size\": \(fileSize), \"color_model\": \"\(colorModel)\", \"bit_depth\": \(depth), \"dpi_width\": \(dpiW), \"dpi_height\": \(dpiH), \"has_alpha\": \(hasAlpha), \"exif\": \(exifJSON)}"
  }
}

private struct StripMetadataTool: ImageTool {
  let name = "strip_metadata"
  struct Args: Decodable { let input_path: String }

  func execute(input: Args) -> String {
    guard let image = ImageHelper.loadImage(from: input.input_path) else {
      return jsonError("Failed to load image: \(input.input_path)")
    }
    guard let format = ImageHelper.getFormat(from: input.input_path) else {
      return jsonError("Could not determine image format")
    }
    guard
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: input.input_path) as CFURL, format.identifier as CFString, 1, nil)
    else {
      return jsonError("Failed to create image destination")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
      return jsonError("Failed to save image without metadata")
    }
    return jsonSuccess(["message": "Metadata stripped successfully"])
  }
}

// MARK: - Filter & Color Tools

private struct AdjustColorsTool: ImageTool {
  let name = "adjust_colors"
  struct Args: Decodable {
    let input_path: String
    let brightness: Double?
    let contrast: Double?
    let saturation: Double?
  }

  func execute(input: Args) -> String {
    guard let cgImage = ImageHelper.loadImage(from: input.input_path) else {
      return jsonError("Failed to load image: \(input.input_path)")
    }
    guard let format = ImageHelper.getFormat(from: input.input_path) else {
      return jsonError("Could not determine image format")
    }
    guard let filter = CIFilter(name: "CIColorControls") else {
      return jsonError("Failed to create color controls filter")
    }

    filter.setValue(CIImage(cgImage: cgImage), forKey: kCIInputImageKey)
    if let b = input.brightness { filter.setValue(b, forKey: kCIInputBrightnessKey) }
    if let c = input.contrast { filter.setValue(c, forKey: kCIInputContrastKey) }
    if let s = input.saturation { filter.setValue(s, forKey: kCIInputSaturationKey) }

    guard let output = filter.outputImage,
      let result = CIContext().createCGImage(output, from: output.extent),
      ImageHelper.saveImage(result, to: input.input_path, format: format)
    else {
      return jsonError("Failed to apply color adjustments")
    }
    return jsonSuccess([
      "brightness": input.brightness ?? 0, "contrast": input.contrast ?? 1,
      "saturation": input.saturation ?? 1,
    ])
  }
}

private struct ApplyFilterTool: ImageTool {
  let name = "apply_filter"
  struct Args: Decodable {
    let input_path: String
    let filter: String
    let intensity: Double?
  }

  func execute(input: Args) -> String {
    guard let cgImage = ImageHelper.loadImage(from: input.input_path) else {
      return jsonError("Failed to load image: \(input.input_path)")
    }
    guard let format = ImageHelper.getFormat(from: input.input_path) else {
      return jsonError("Could not determine image format")
    }

    let ciImage = CIImage(cgImage: cgImage)
    let intensity = input.intensity ?? 1.0
    let filterName: String
    var params: [String: Any] = [kCIInputImageKey: ciImage]

    switch input.filter.lowercased() {
    case "grayscale": filterName = "CIPhotoEffectMono"
    case "sepia":
      filterName = "CISepiaTone"
      params[kCIInputIntensityKey] = intensity
    case "blur":
      filterName = "CIGaussianBlur"
      params[kCIInputRadiusKey] = intensity * 10
    case "sharpen":
      filterName = "CISharpenLuminance"
      params[kCIInputSharpnessKey] = intensity
    case "invert": filterName = "CIColorInvert"
    default:
      return jsonError(
        "Unknown filter: \(input.filter). Supported: grayscale, sepia, blur, sharpen, invert")
    }

    guard let filter = CIFilter(name: filterName) else {
      return jsonError("Failed to create filter")
    }
    params.forEach { filter.setValue($0.value, forKey: $0.key) }

    guard let output = filter.outputImage else { return jsonError("Failed to apply filter") }
    let extent = input.filter.lowercased() == "blur" ? ciImage.extent : output.extent
    guard let result = CIContext().createCGImage(output, from: extent),
      ImageHelper.saveImage(result, to: input.input_path, format: format)
    else {
      return jsonError("Failed to save filtered image")
    }
    return jsonSuccess(["filter": input.filter])
  }
}

private struct ExtractColorsTool: ImageTool {
  let name = "extract_colors"
  struct Args: Decodable {
    let input_path: String
    let count: Int?
  }

  func execute(input: Args) -> String {
    guard let image = ImageHelper.loadImage(from: input.input_path),
      let provider = image.dataProvider,
      let data = provider.data,
      let ptr = CFDataGetBytePtr(data)
    else {
      return jsonError("Failed to load image: \(input.input_path)")
    }

    let count = input.count ?? 5
    let (width, height) = (image.width, image.height)
    let bpp = image.bitsPerPixel / 8
    let bpr = image.bytesPerRow
    let (stepX, stepY) = (max(1, width / 50), max(1, height / 50))

    var colorCounts: [String: Int] = [:]
    for y in stride(from: 0, to: height, by: stepY) {
      for x in stride(from: 0, to: width, by: stepX) {
        let offset = y * bpr + x * bpp
        let hex = ImageHelper.rgbToHex(
          (Int(ptr[offset]) / 32) * 32, (Int(ptr[offset + 1]) / 32) * 32,
          (Int(ptr[offset + 2]) / 32) * 32)
        colorCounts[hex, default: 0] += 1
      }
    }

    let colors = colorCounts.sorted { $0.value > $1.value }.prefix(count).map { "\"\($0.key)\"" }
    return "{\"colors\": [\(colors.joined(separator: ", "))]}"
  }
}

// MARK: - Composition Tools

private struct AddWatermarkTool: ImageTool {
  let name = "add_watermark"
  struct Args: Decodable {
    let input_path: String
    let text: String?
    let image_path: String?
    let position: String?
    let opacity: Double?
  }

  func execute(input: Args) -> String {
    guard let image = ImageHelper.loadImage(from: input.input_path) else {
      return jsonError("Failed to load image: \(input.input_path)")
    }
    guard let format = ImageHelper.getFormat(from: input.input_path) else {
      return jsonError("Could not determine image format")
    }
    guard input.text != nil || input.image_path != nil else {
      return jsonError("Must specify either text or image_path for watermark")
    }

    let (width, height) = (image.width, image.height)
    let opacity = CGFloat(input.opacity ?? 0.5)
    let position = input.position ?? "bottom-right"
    let padding: CGFloat = 20

    guard
      let ctx = ImageHelper.createContext(
        width: width, height: height, colorSpace: image.colorSpace)
    else {
      return jsonError("Failed to create graphics context")
    }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setAlpha(opacity)

    if let text = input.text {
      let fontSize = CGFloat(max(width, height)) / 20
      let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
      let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
      ]
      let line = CTLineCreateWithAttributedString(
        CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!)
      let bounds = CTLineGetBoundsWithOptions(line, [])

      let (x, y) = calculatePosition(
        position: position, containerW: width, containerH: height, itemW: bounds.width,
        itemH: bounds.height, padding: padding)
      ctx.textPosition = CGPoint(x: x, y: y)
      CTLineDraw(line, ctx)
    } else if let imagePath = input.image_path {
      guard let wm = ImageHelper.loadImage(from: imagePath) else {
        return jsonError("Failed to load watermark image")
      }
      let (x, y) = calculatePosition(
        position: position, containerW: width, containerH: height, itemW: CGFloat(wm.width),
        itemH: CGFloat(wm.height), padding: padding)
      ctx.draw(wm, in: CGRect(x: x, y: y, width: CGFloat(wm.width), height: CGFloat(wm.height)))
    }

    guard let result = ctx.makeImage(),
      ImageHelper.saveImage(result, to: input.input_path, format: format)
    else {
      return jsonError("Failed to save watermarked image")
    }
    return jsonSuccess(["position": position])
  }

  private func calculatePosition(
    position: String, containerW: Int, containerH: Int, itemW: CGFloat, itemH: CGFloat,
    padding: CGFloat
  ) -> (CGFloat, CGFloat) {
    switch position {
    case "top-left": return (padding, CGFloat(containerH) - itemH - padding)
    case "top-right":
      return (CGFloat(containerW) - itemW - padding, CGFloat(containerH) - itemH - padding)
    case "bottom-left": return (padding, padding)
    case "center": return ((CGFloat(containerW) - itemW) / 2, (CGFloat(containerH) - itemH) / 2)
    default: return (CGFloat(containerW) - itemW - padding, padding)  // bottom-right
    }
  }
}

private struct CompositeImagesTool: ImageTool {
  let name = "composite_images"
  struct Args: Decodable {
    let base_path: String
    let overlay_path: String
    let x: Int
    let y: Int
    let opacity: Double?
  }

  func execute(input: Args) -> String {
    guard let base = ImageHelper.loadImage(from: input.base_path) else {
      return jsonError("Failed to load base image")
    }
    guard let overlay = ImageHelper.loadImage(from: input.overlay_path) else {
      return jsonError("Failed to load overlay image")
    }
    guard let format = ImageHelper.getFormat(from: input.base_path) else {
      return jsonError("Could not determine image format")
    }

    let (width, height) = (base.width, base.height)
    guard
      let ctx = ImageHelper.createContext(width: width, height: height, colorSpace: base.colorSpace)
    else {
      return jsonError("Failed to create graphics context")
    }
    ctx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setAlpha(CGFloat(input.opacity ?? 1.0))
    ctx.draw(
      overlay,
      in: CGRect(
        x: input.x, y: height - input.y - overlay.height, width: overlay.width,
        height: overlay.height))

    guard let result = ctx.makeImage(),
      ImageHelper.saveImage(result, to: input.base_path, format: format)
    else {
      return jsonError("Failed to save composited image")
    }
    return jsonSuccess(["x": input.x, "y": input.y])
  }
}

private struct AddBorderTool: ImageTool {
  let name = "add_border"
  struct Args: Decodable {
    let input_path: String
    let width: Int
    let color: String
  }

  func execute(input: Args) -> String {
    guard let image = ImageHelper.loadImage(from: input.input_path) else {
      return jsonError("Failed to load image: \(input.input_path)")
    }
    guard let format = ImageHelper.getFormat(from: input.input_path) else {
      return jsonError("Could not determine image format")
    }
    guard let rgb = ImageHelper.hexToRGB(input.color) else {
      return jsonError("Invalid color format. Use hex like #FF0000")
    }

    let border = input.width
    let (imgW, imgH) = (image.width, image.height)
    let (newW, newH) = (imgW + border * 2, imgH + border * 2)

    guard
      let ctx = ImageHelper.createContext(width: newW, height: newH, colorSpace: image.colorSpace)
    else {
      return jsonError("Failed to create graphics context")
    }
    ctx.setFillColor(CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: newW, height: newH))
    ctx.draw(image, in: CGRect(x: border, y: border, width: imgW, height: imgH))

    guard let result = ctx.makeImage(),
      ImageHelper.saveImage(result, to: input.input_path, format: format)
    else {
      return jsonError("Failed to save bordered image")
    }
    return jsonSuccess(["border_width": border, "new_width": newW, "new_height": newH])
  }
}

private struct RoundCornersTool: ImageTool {
  let name = "round_corners"
  struct Args: Decodable {
    let input_path: String
    let radius: Int
  }

  func execute(input: Args) -> String {
    guard let image = ImageHelper.loadImage(from: input.input_path) else {
      return jsonError("Failed to load image: \(input.input_path)")
    }

    let (width, height) = (image.width, image.height)
    guard
      let ctx = ImageHelper.createContext(
        width: width, height: height, colorSpace: image.colorSpace)
    else {
      return jsonError("Failed to create graphics context")
    }

    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    ctx.addPath(
      CGPath(
        roundedRect: rect, cornerWidth: CGFloat(input.radius), cornerHeight: CGFloat(input.radius),
        transform: nil))
    ctx.clip()
    ctx.draw(image, in: rect)

    guard let result = ctx.makeImage() else {
      return jsonError("Failed to create rounded corners image")
    }

    let outputPath =
      input.input_path.lowercased().hasSuffix(".png")
      ? input.input_path
      : URL(fileURLWithPath: input.input_path).deletingPathExtension().appendingPathExtension("png")
        .path

    guard ImageHelper.saveImage(result, to: outputPath, format: .png) else {
      return jsonError("Failed to save image with rounded corners")
    }
    return jsonSuccess(["radius": input.radius, "output_path": outputPath])
  }
}

// MARK: - Plugin Infrastructure

private typealias osr_plugin_ctx_t = UnsafeMutableRawPointer
private typealias osr_free_string_t = @convention(c) (UnsafePointer<CChar>?) -> Void
private typealias osr_init_t = @convention(c) () -> osr_plugin_ctx_t?
private typealias osr_destroy_t = @convention(c) (osr_plugin_ctx_t?) -> Void
private typealias osr_get_manifest_t = @convention(c) (osr_plugin_ctx_t?) -> UnsafePointer<CChar>?
private typealias osr_invoke_t =
  @convention(c) (
    osr_plugin_ctx_t?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?
  ) -> UnsafePointer<CChar>?

private struct osr_plugin_api {
  var free_string: osr_free_string_t?
  var `init`: osr_init_t?
  var destroy: osr_destroy_t?
  var get_manifest: osr_get_manifest_t?
  var invoke: osr_invoke_t?
}

private class PluginContext {
  let tools: [String: (String) -> String]

  init() {
    let convert = ConvertImageTool()
    let optimize = OptimizeImageTool()
    let rotate = RotateImageTool()
    let flip = FlipImageTool()
    let crop = CropImageTool()
    let resize = ResizeImageTool()
    let getInfo = GetImageInfoTool()
    let stripMeta = StripMetadataTool()
    let adjustColors = AdjustColorsTool()
    let applyFilter = ApplyFilterTool()
    let extractColors = ExtractColorsTool()
    let watermark = AddWatermarkTool()
    let composite = CompositeImagesTool()
    let border = AddBorderTool()
    let roundCorners = RoundCornersTool()

    tools = [
      convert.name: convert.run,
      optimize.name: optimize.run,
      rotate.name: rotate.run,
      flip.name: flip.run,
      crop.name: crop.run,
      resize.name: resize.run,
      getInfo.name: getInfo.run,
      stripMeta.name: stripMeta.run,
      adjustColors.name: adjustColors.run,
      applyFilter.name: applyFilter.run,
      extractColors.name: extractColors.run,
      watermark.name: watermark.run,
      composite.name: composite.run,
      border.name: border.run,
      roundCorners.name: roundCorners.run,
    ]
  }
}

private func makeCString(_ s: String) -> UnsafePointer<CChar>? {
  guard let ptr = strdup(s) else { return nil }
  return UnsafePointer(ptr)
}

nonisolated(unsafe) private var api: osr_plugin_api = {
  var api = osr_plugin_api()

  api.free_string = { ptr in if let p = ptr { free(UnsafeMutableRawPointer(mutating: p)) } }
  api.`init` = { Unmanaged.passRetained(PluginContext()).toOpaque() }
  api.destroy = { if let p = $0 { Unmanaged<PluginContext>.fromOpaque(p).release() } }

  api.get_manifest = { _ in
    makeCString(
      """
      {
        "plugin_id": "dev.osaurus.images",
        "name": "Osaurus Images",
        "version": "0.1.0",
        "description": "Image manipulation, conversion, and optimization tools",
        "license": "MIT",
        "authors": [],
        "min_macos": "15.0",
        "min_osaurus": "0.5.0",
        "capabilities": {
          "tools": [
            {"id": "convert_image", "description": "Convert image format (png, jpeg, gif, tiff, bmp, heic, webp)", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}, "output_format": {"type": "string", "description": "Target format"}}, "required": ["input_path", "output_format"]}, "requirements": [], "permission_policy": "ask"},
            {"id": "optimize_image", "description": "Optimize image file size", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}, "quality": {"type": "number", "description": "Quality 0.0-1.0 (default: 0.8)"}}, "required": ["input_path"]}, "requirements": [], "permission_policy": "ask"},
            {"id": "rotate_image", "description": "Rotate image by degrees", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}, "degrees": {"type": "number", "description": "Rotation degrees (positive = counter-clockwise)"}}, "required": ["input_path", "degrees"]}, "requirements": [], "permission_policy": "ask"},
            {"id": "flip_image", "description": "Flip image horizontally or vertically", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}, "direction": {"type": "string", "description": "horizontal or vertical"}}, "required": ["input_path", "direction"]}, "requirements": [], "permission_policy": "ask"},
            {"id": "crop_image", "description": "Crop image to region", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}, "x": {"type": "integer", "description": "X of top-left"}, "y": {"type": "integer", "description": "Y of top-left"}, "width": {"type": "integer", "description": "Crop width"}, "height": {"type": "integer", "description": "Crop height"}}, "required": ["input_path", "x", "y", "width", "height"]}, "requirements": [], "permission_policy": "ask"},
            {"id": "resize_image", "description": "Resize image", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}, "width": {"type": "integer", "description": "New width"}, "height": {"type": "integer", "description": "New height"}, "scale": {"type": "number", "description": "Scale percentage"}}, "required": ["input_path"]}, "requirements": [], "permission_policy": "ask"},
            {"id": "get_image_info", "description": "Get image metadata", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}}, "required": ["input_path"]}, "requirements": [], "permission_policy": "auto"},
            {"id": "strip_metadata", "description": "Remove EXIF metadata", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}}, "required": ["input_path"]}, "requirements": [], "permission_policy": "ask"},
            {"id": "adjust_colors", "description": "Adjust brightness/contrast/saturation", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}, "brightness": {"type": "number", "description": "-1.0 to 1.0"}, "contrast": {"type": "number", "description": "0.0 to 2.0"}, "saturation": {"type": "number", "description": "0.0 to 2.0"}}, "required": ["input_path"]}, "requirements": [], "permission_policy": "ask"},
            {"id": "apply_filter", "description": "Apply filter (grayscale, sepia, blur, sharpen, invert)", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}, "filter": {"type": "string", "description": "Filter name"}, "intensity": {"type": "number", "description": "0.0 to 1.0"}}, "required": ["input_path", "filter"]}, "requirements": [], "permission_policy": "ask"},
            {"id": "extract_colors", "description": "Extract dominant colors", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}, "count": {"type": "integer", "description": "Number of colors (default: 5)"}}, "required": ["input_path"]}, "requirements": [], "permission_policy": "auto"},
            {"id": "add_watermark", "description": "Add text or image watermark", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}, "text": {"type": "string", "description": "Watermark text"}, "image_path": {"type": "string", "description": "Watermark image path"}, "position": {"type": "string", "description": "top-left, top-right, bottom-left, bottom-right, center"}, "opacity": {"type": "number", "description": "0.0 to 1.0"}}, "required": ["input_path"]}, "requirements": [], "permission_policy": "ask"},
            {"id": "composite_images", "description": "Overlay image on another", "parameters": {"type": "object", "properties": {"base_path": {"type": "string", "description": "Base image path"}, "overlay_path": {"type": "string", "description": "Overlay image path"}, "x": {"type": "integer", "description": "X position"}, "y": {"type": "integer", "description": "Y position"}, "opacity": {"type": "number", "description": "0.0 to 1.0"}}, "required": ["base_path", "overlay_path", "x", "y"]}, "requirements": [], "permission_policy": "ask"},
            {"id": "add_border", "description": "Add colored border", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}, "width": {"type": "integer", "description": "Border width"}, "color": {"type": "string", "description": "Hex color (#FF0000)"}}, "required": ["input_path", "width", "color"]}, "requirements": [], "permission_policy": "ask"},
            {"id": "round_corners", "description": "Round image corners (outputs PNG)", "parameters": {"type": "object", "properties": {"input_path": {"type": "string", "description": "Path to input image"}, "radius": {"type": "integer", "description": "Corner radius"}}, "required": ["input_path", "radius"]}, "requirements": [], "permission_policy": "ask"}
          ]
        }
      }
      """)
  }

  api.invoke = { ctxPtr, typePtr, idPtr, payloadPtr in
    guard let ctxPtr, let typePtr, let idPtr, let payloadPtr else { return nil }
    let ctx = Unmanaged<PluginContext>.fromOpaque(ctxPtr).takeUnretainedValue()
    let type = String(cString: typePtr)
    let id = String(cString: idPtr)
    let payload = String(cString: payloadPtr)

    guard type == "tool" else { return makeCString(jsonError("Unknown capability type")) }
    guard let tool = ctx.tools[id] else { return makeCString(jsonError("Unknown tool: \(id)")) }
    return makeCString(tool(payload))
  }

  return api
}()

@_cdecl("osaurus_plugin_entry")
public func osaurus_plugin_entry() -> UnsafeRawPointer? {
  UnsafeRawPointer(&api)
}
