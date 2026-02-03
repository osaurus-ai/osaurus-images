import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - JSON Helpers

private func jsonError(_ message: String) -> String {
  "{\"error\": \"\(escapeJSON(message))\"}"
}

private func jsonSuccess(_ fields: [String: Any] = [:]) -> String {
  var parts = ["\"success\": true"]
  for (key, value) in fields {
    switch value {
    case let s as String: parts.append("\"\(key)\": \"\(escapeJSON(s))\"")
    case let b as Bool: parts.append("\"\(key)\": \(b)")
    case let i as Int: parts.append("\"\(key)\": \(i)")
    case let d as Double: parts.append("\"\(key)\": \(d)")
    default: parts.append("\"\(key)\": \"\(value)\"")
    }
  }
  return "{\(parts.joined(separator: ", "))}"
}

private func escapeJSON(_ string: String) -> String {
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

// MARK: - Folder Context

private struct FolderContext: Decodable {
  let working_directory: String
}

// MARK: - Path & File Helpers

private func normalizePath(_ path: String) -> String {
  ((path as NSString).expandingTildeInPath as NSString).standardizingPath
}

private enum PathResult {
  case success(String)
  case failure(String)
}

private func resolvePath(_ path: String, context: FolderContext?) -> PathResult {
  // If no context, assume absolute path
  guard let workingDir = context?.working_directory else {
    return .success(normalizePath(path))
  }

  // Strip leading "/" if present (paths are always relative to working directory)
  let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path

  // Resolve path relative to working directory
  let resolvedPath = normalizePath("\(workingDir)/\(cleanPath)")

  // Security: ensure path stays within working directory
  let normalizedWorkingDir = normalizePath(workingDir)
  guard resolvedPath.hasPrefix(normalizedWorkingDir) else {
    return .failure("Path outside working directory")
  }

  return .success(resolvedPath)
}

private func fileExists(_ path: String) -> Bool {
  FileManager.default.fileExists(atPath: path)
}

private func fileSize(_ path: String) -> Int {
  (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
}

// MARK: - Image I/O

private enum ImageResult {
  case success(CGImage)
  case failure(String)
}

private func loadImage(_ path: String) -> ImageResult {
  let path = normalizePath(path)
  guard fileExists(path) else {
    return .failure("File not found: \(path)")
  }
  guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
    return .failure("Cannot read image file: \(path)")
  }
  guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    return .failure("Failed to decode image: \(path)")
  }
  return .success(image)
}

private func saveImage(_ image: CGImage, to path: String, format: UTType, quality: CGFloat = 1.0)
  -> Bool
{
  guard
    let dest = CGImageDestinationCreateWithURL(
      URL(fileURLWithPath: path) as CFURL, format.identifier as CFString, 1, nil
    )
  else { return false }
  CGImageDestinationAddImage(
    dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
  return CGImageDestinationFinalize(dest)
}

private func createContext(_ width: Int, _ height: Int, _ colorSpace: CGColorSpace? = nil)
  -> CGContext?
{
  CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )
}

private func formatFromExt(_ ext: String) -> UTType? {
  switch ext.lowercased() {
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

private func imageFormat(_ path: String) -> UTType? {
  formatFromExt((path as NSString).pathExtension)
}

// MARK: - Color Helpers

private func hexToRGB(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
  let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
    of: "#", with: "")
  guard hex.count == 6 else { return nil }
  var rgb: UInt64 = 0
  Scanner(string: hex).scanHexInt64(&rgb)
  return (
    CGFloat((rgb >> 16) & 0xFF) / 255, CGFloat((rgb >> 8) & 0xFF) / 255, CGFloat(rgb & 0xFF) / 255
  )
}

private func rgbToHex(_ r: Int, _ g: Int, _ b: Int) -> String {
  String(format: "#%02X%02X%02X", r, g, b)
}

// MARK: - Tool Execution Helper

private func withImage<T: Decodable>(
  _ args: String,
  as type: T.Type,
  path keyPath: KeyPath<T, String>,
  context contextPath: KeyPath<T, FolderContext?>,
  execute: (T, CGImage, String, UTType) -> String
) -> String {
  guard let data = args.data(using: .utf8),
    let input = try? JSONDecoder().decode(type, from: data)
  else {
    return jsonError("Invalid arguments")
  }
  let path: String
  switch resolvePath(input[keyPath: keyPath], context: input[keyPath: contextPath]) {
  case .failure(let error): return jsonError(error)
  case .success(let resolved): path = resolved
  }
  switch loadImage(path) {
  case .failure(let error): return jsonError(error)
  case .success(let image):
    guard let format = imageFormat(path) else {
      return jsonError("Could not determine image format")
    }
    return execute(input, image, path, format)
  }
}

// MARK: - Tools

private func convertImage(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let output_format: String
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    input, image, path, _ in
    guard let format = formatFromExt(input.output_format) else {
      return jsonError("Unsupported format: \(input.output_format)")
    }
    let output = URL(fileURLWithPath: path).deletingPathExtension()
      .appendingPathExtension(input.output_format.lowercased()).path
    guard saveImage(image, to: output, format: format) else {
      return jsonError("Failed to save: \(output)")
    }
    return jsonSuccess(["output_path": output])
  }
}

private func optimizeImage(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let quality: Double?
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    input, image, path, format in
    let originalSize = fileSize(path)
    guard saveImage(image, to: path, format: format, quality: CGFloat(input.quality ?? 0.8)) else {
      return jsonError("Failed to optimize image")
    }
    let newSize = fileSize(path)
    return jsonSuccess([
      "original_size": originalSize, "new_size": newSize, "saved_bytes": originalSize - newSize,
    ])
  }
}

private func rotateImage(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let degrees: Double
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    input, image, path, format in
    let radians = input.degrees * .pi / 180.0
    let (w, h) = (image.width, image.height)
    let norm = ((Int(input.degrees) % 360) + 360) % 360

    let (newW, newH): (Int, Int) = {
      switch norm {
      case 90, 270: return (h, w)
      case 0, 180: return (w, h)
      default:
        let (cos, sin) = (abs(Foundation.cos(radians)), abs(Foundation.sin(radians)))
        return (Int(Double(w) * cos + Double(h) * sin), Int(Double(w) * sin + Double(h) * cos))
      }
    }()

    guard let ctx = createContext(newW, newH, image.colorSpace) else {
      return jsonError("Failed to create graphics context")
    }
    ctx.translateBy(x: CGFloat(newW) / 2, y: CGFloat(newH) / 2)
    ctx.rotate(by: CGFloat(radians))
    ctx.translateBy(x: CGFloat(-w) / 2, y: CGFloat(-h) / 2)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    guard let result = ctx.makeImage(), saveImage(result, to: path, format: format) else {
      return jsonError("Failed to save rotated image")
    }
    return jsonSuccess(["degrees": input.degrees])
  }
}

private func flipImage(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let direction: String
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    input, image, path, format in
    let dir = input.direction.lowercased()
    guard dir == "horizontal" || dir == "vertical" else {
      return jsonError("Direction must be 'horizontal' or 'vertical'")
    }
    let (w, h) = (image.width, image.height)
    guard let ctx = createContext(w, h, image.colorSpace) else {
      return jsonError("Failed to create graphics context")
    }
    if dir == "horizontal" {
      ctx.translateBy(x: CGFloat(w), y: 0)
      ctx.scaleBy(x: -1, y: 1)
    } else {
      ctx.translateBy(x: 0, y: CGFloat(h))
      ctx.scaleBy(x: 1, y: -1)
    }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let result = ctx.makeImage(), saveImage(result, to: path, format: format) else {
      return jsonError("Failed to save flipped image")
    }
    return jsonSuccess(["direction": dir])
  }
}

private func cropImage(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    input, image, path, format in
    guard input.x >= 0, input.y >= 0, input.width > 0, input.height > 0 else {
      return jsonError("Invalid crop dimensions")
    }
    guard input.x + input.width <= image.width, input.y + input.height <= image.height else {
      return jsonError("Crop region exceeds image bounds")
    }
    let rect = CGRect(
      x: input.x, y: image.height - input.y - input.height, width: input.width, height: input.height
    )
    guard let cropped = image.cropping(to: rect), saveImage(cropped, to: path, format: format)
    else {
      return jsonError("Failed to crop image")
    }
    return jsonSuccess(["width": input.width, "height": input.height])
  }
}

private func resizeImage(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let width: Int?
    let height: Int?
    let scale: Double?
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    input, image, path, format in
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
    guard let ctx = createContext(newW, newH, image.colorSpace) else {
      return jsonError("Failed to create graphics context")
    }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
    guard let result = ctx.makeImage(), saveImage(result, to: path, format: format) else {
      return jsonError("Failed to save resized image")
    }
    return jsonSuccess(["width": newW, "height": newH])
  }
}

private func getImageInfo(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let _context: FolderContext?
  }
  guard let data = args.data(using: .utf8),
    let input = try? JSONDecoder().decode(Args.self, from: data)
  else {
    return jsonError("Invalid arguments")
  }
  let path: String
  switch resolvePath(input.input_path, context: input._context) {
  case .failure(let error): return jsonError(error)
  case .success(let resolved): path = resolved
  }
  guard fileExists(path) else { return jsonError("File not found: \(path)") }

  let url = URL(fileURLWithPath: path)
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
  else {
    return jsonError("Failed to read image properties: \(path)")
  }

  let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
  let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
  let colorModel = props[kCGImagePropertyColorModel] as? String ?? "Unknown"
  let depth = props[kCGImagePropertyDepth] as? Int ?? 0
  let dpiW = props[kCGImagePropertyDPIWidth] as? Double ?? 72.0
  let dpiH = props[kCGImagePropertyDPIHeight] as? Double ?? 72.0
  let hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool ?? false
  let size = fileSize(path)
  let fmt = imageFormat(path)?.preferredFilenameExtension ?? "unknown"

  var exif = "null"
  if let exifDict = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
    var parts: [String] = []
    if let v = exifDict[kCGImagePropertyExifDateTimeOriginal] as? String {
      parts.append("\"date_time\": \"\(escapeJSON(v))\"")
    }
    if let v = exifDict[kCGImagePropertyExifExposureTime] as? Double {
      parts.append("\"exposure_time\": \(v)")
    }
    if let v = exifDict[kCGImagePropertyExifFNumber] as? Double {
      parts.append("\"f_number\": \(v)")
    }
    if let v = (exifDict[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first {
      parts.append("\"iso\": \(v)")
    }
    if let v = exifDict[kCGImagePropertyExifFocalLength] as? Double {
      parts.append("\"focal_length\": \(v)")
    }
    if !parts.isEmpty { exif = "{\(parts.joined(separator: ", "))}" }
  }

  return
    "{\"width\": \(width), \"height\": \(height), \"format\": \"\(fmt)\", \"file_size\": \(size), \"color_model\": \"\(colorModel)\", \"bit_depth\": \(depth), \"dpi_width\": \(dpiW), \"dpi_height\": \(dpiH), \"has_alpha\": \(hasAlpha), \"exif\": \(exif)}"
}

private func stripMetadata(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    _, image, path, format in
    guard
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, format.identifier as CFString, 1, nil
      )
    else {
      return jsonError("Failed to create image destination")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
      return jsonError("Failed to save image")
    }
    return jsonSuccess(["message": "Metadata stripped successfully"])
  }
}

private func adjustColors(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let brightness: Double?
    let contrast: Double?
    let saturation: Double?
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    input, image, path, format in
    guard let filter = CIFilter(name: "CIColorControls") else {
      return jsonError("Failed to create filter")
    }
    filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
    if let b = input.brightness { filter.setValue(b, forKey: kCIInputBrightnessKey) }
    if let c = input.contrast { filter.setValue(c, forKey: kCIInputContrastKey) }
    if let s = input.saturation { filter.setValue(s, forKey: kCIInputSaturationKey) }

    guard let output = filter.outputImage,
      let result = CIContext().createCGImage(output, from: output.extent),
      saveImage(result, to: path, format: format)
    else {
      return jsonError("Failed to apply color adjustments")
    }
    return jsonSuccess([
      "brightness": input.brightness ?? 0, "contrast": input.contrast ?? 1,
      "saturation": input.saturation ?? 1,
    ])
  }
}

private func applyFilter(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let filter: String
    let intensity: Double?
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    input, image, path, format in
    let ciImage = CIImage(cgImage: image)
    let intensity = input.intensity ?? 1.0
    let (filterName, params): (String, [String: Any]) = {
      switch input.filter.lowercased() {
      case "grayscale": return ("CIPhotoEffectMono", [kCIInputImageKey: ciImage])
      case "sepia":
        return ("CISepiaTone", [kCIInputImageKey: ciImage, kCIInputIntensityKey: intensity])
      case "blur":
        return ("CIGaussianBlur", [kCIInputImageKey: ciImage, kCIInputRadiusKey: intensity * 10])
      case "sharpen":
        return ("CISharpenLuminance", [kCIInputImageKey: ciImage, kCIInputSharpnessKey: intensity])
      case "invert": return ("CIColorInvert", [kCIInputImageKey: ciImage])
      default: return ("", [:])
      }
    }()

    guard !filterName.isEmpty else {
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
      saveImage(result, to: path, format: format)
    else {
      return jsonError("Failed to save filtered image")
    }
    return jsonSuccess(["filter": input.filter])
  }
}

private func extractColors(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let count: Int?
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    input, image, path, _ in
    guard let provider = image.dataProvider, let data = provider.data,
      let ptr = CFDataGetBytePtr(data)
    else {
      return jsonError("Failed to read image data")
    }
    let count = input.count ?? 5
    let (w, h) = (image.width, image.height)
    let bpp = image.bitsPerPixel / 8
    let bpr = image.bytesPerRow
    let (stepX, stepY) = (max(1, w / 50), max(1, h / 50))

    var colorCounts: [String: Int] = [:]
    for y in stride(from: 0, to: h, by: stepY) {
      for x in stride(from: 0, to: w, by: stepX) {
        let offset = y * bpr + x * bpp
        let hex = rgbToHex(
          (Int(ptr[offset]) / 32) * 32, (Int(ptr[offset + 1]) / 32) * 32,
          (Int(ptr[offset + 2]) / 32) * 32)
        colorCounts[hex, default: 0] += 1
      }
    }
    let colors = colorCounts.sorted { $0.value > $1.value }.prefix(count).map { "\"\($0.key)\"" }
    return "{\"colors\": [\(colors.joined(separator: ", "))]}"
  }
}

private func addWatermark(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let text: String?
    let image_path: String?
    let position: String?
    let opacity: Double?
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    input, image, path, format in
    guard input.text != nil || input.image_path != nil else {
      return jsonError("Must specify text or image_path")
    }
    let (w, h) = (image.width, image.height)
    let opacity = CGFloat(input.opacity ?? 0.5)
    let pos = input.position ?? "bottom-right"
    let pad: CGFloat = 20

    guard let ctx = createContext(w, h, image.colorSpace) else {
      return jsonError("Failed to create graphics context")
    }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setAlpha(opacity)

    func position(_ itemW: CGFloat, _ itemH: CGFloat) -> (CGFloat, CGFloat) {
      switch pos {
      case "top-left": return (pad, CGFloat(h) - itemH - pad)
      case "top-right": return (CGFloat(w) - itemW - pad, CGFloat(h) - itemH - pad)
      case "bottom-left": return (pad, pad)
      case "center": return ((CGFloat(w) - itemW) / 2, (CGFloat(h) - itemH) / 2)
      default: return (CGFloat(w) - itemW - pad, pad)
      }
    }

    if let text = input.text {
      let fontSize = CGFloat(max(w, h)) / 20
      let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
      let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
      ]
      let line = CTLineCreateWithAttributedString(
        CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!)
      let bounds = CTLineGetBoundsWithOptions(line, [])
      let (x, y) = position(bounds.width, bounds.height)
      ctx.textPosition = CGPoint(x: x, y: y)
      CTLineDraw(line, ctx)
    } else if let imgPath = input.image_path {
      // Resolve watermark image path using context
      let resolvedImgPath: String
      switch resolvePath(imgPath, context: input._context) {
      case .failure(let err): return jsonError("Watermark path: \(err)")
      case .success(let resolved): resolvedImgPath = resolved
      }
      switch loadImage(resolvedImgPath) {
      case .failure(let err): return jsonError("Watermark: \(err)")
      case .success(let wm):
        let (x, y) = position(CGFloat(wm.width), CGFloat(wm.height))
        ctx.draw(wm, in: CGRect(x: x, y: y, width: CGFloat(wm.width), height: CGFloat(wm.height)))
      }
    }

    guard let result = ctx.makeImage(), saveImage(result, to: path, format: format) else {
      return jsonError("Failed to save watermarked image")
    }
    return jsonSuccess(["position": pos])
  }
}

private func compositeImages(_ args: String) -> String {
  struct Args: Decodable {
    let base_path: String
    let overlay_path: String
    let x: Int
    let y: Int
    let opacity: Double?
    let _context: FolderContext?
  }
  guard let data = args.data(using: .utf8),
    let input = try? JSONDecoder().decode(Args.self, from: data)
  else {
    return jsonError("Invalid arguments")
  }

  // Resolve both paths using context
  let basePath: String
  switch resolvePath(input.base_path, context: input._context) {
  case .failure(let err): return jsonError("Base path: \(err)")
  case .success(let resolved): basePath = resolved
  }

  let overlayPath: String
  switch resolvePath(input.overlay_path, context: input._context) {
  case .failure(let err): return jsonError("Overlay path: \(err)")
  case .success(let resolved): overlayPath = resolved
  }

  let base: CGImage
  switch loadImage(basePath) {
  case .failure(let err): return jsonError("Base: \(err)")
  case .success(let img): base = img
  }

  let overlay: CGImage
  switch loadImage(overlayPath) {
  case .failure(let err): return jsonError("Overlay: \(err)")
  case .success(let img): overlay = img
  }
  guard let format = imageFormat(basePath) else {
    return jsonError("Could not determine image format")
  }

  let (w, h) = (base.width, base.height)
  guard let ctx = createContext(w, h, base.colorSpace) else {
    return jsonError("Failed to create graphics context")
  }
  ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
  ctx.setAlpha(CGFloat(input.opacity ?? 1.0))
  ctx.draw(
    overlay,
    in: CGRect(
      x: input.x, y: h - input.y - overlay.height, width: overlay.width, height: overlay.height))

  guard let result = ctx.makeImage(), saveImage(result, to: basePath, format: format) else {
    return jsonError("Failed to save composited image")
  }
  return jsonSuccess(["x": input.x, "y": input.y])
}

private func addBorder(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let width: Int
    let color: String
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    input, image, path, format in
    guard let rgb = hexToRGB(input.color) else {
      return jsonError("Invalid color format. Use hex like #FF0000")
    }
    let border = input.width
    let (imgW, imgH) = (image.width, image.height)
    let (newW, newH) = (imgW + border * 2, imgH + border * 2)

    guard let ctx = createContext(newW, newH, image.colorSpace) else {
      return jsonError("Failed to create graphics context")
    }
    ctx.setFillColor(CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: newW, height: newH))
    ctx.draw(image, in: CGRect(x: border, y: border, width: imgW, height: imgH))

    guard let result = ctx.makeImage(), saveImage(result, to: path, format: format) else {
      return jsonError("Failed to save bordered image")
    }
    return jsonSuccess(["border_width": border, "new_width": newW, "new_height": newH])
  }
}

private func roundCorners(_ args: String) -> String {
  struct Args: Decodable {
    let input_path: String
    let radius: Int
    let _context: FolderContext?
  }
  return withImage(args, as: Args.self, path: \.input_path, context: \._context) {
    input, image, path, _ in
    let (w, h) = (image.width, image.height)
    guard let ctx = createContext(w, h, image.colorSpace) else {
      return jsonError("Failed to create graphics context")
    }
    let rect = CGRect(x: 0, y: 0, width: w, height: h)
    let r = CGFloat(input.radius)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.clip()
    ctx.draw(image, in: rect)

    guard let result = ctx.makeImage() else {
      return jsonError("Failed to create rounded image")
    }
    let output =
      path.lowercased().hasSuffix(".png")
      ? path
      : URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("png").path
    guard saveImage(result, to: output, format: .png) else {
      return jsonError("Failed to save image")
    }
    return jsonSuccess(["radius": input.radius, "output_path": output])
  }
}

// MARK: - Plugin Infrastructure

nonisolated(unsafe) private let tools: [String: (String) -> String] = [
  "convert_image": convertImage,
  "optimize_image": optimizeImage,
  "rotate_image": rotateImage,
  "flip_image": flipImage,
  "crop_image": cropImage,
  "resize_image": resizeImage,
  "get_image_info": getImageInfo,
  "strip_metadata": stripMetadata,
  "adjust_colors": adjustColors,
  "apply_filter": applyFilter,
  "extract_colors": extractColors,
  "add_watermark": addWatermark,
  "composite_images": compositeImages,
  "add_border": addBorder,
  "round_corners": roundCorners,
]

private let manifest = """
  {
    "plugin_id": "osaurus.images",
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
  """

private func makeCString(_ s: String) -> UnsafePointer<CChar>? {
  guard let ptr = strdup(s) else { return nil }
  return UnsafePointer(ptr)
}

private typealias PluginCtx = UnsafeMutableRawPointer
private typealias FreeStringFn = @convention(c) (UnsafePointer<CChar>?) -> Void
private typealias InitFn = @convention(c) () -> PluginCtx?
private typealias DestroyFn = @convention(c) (PluginCtx?) -> Void
private typealias ManifestFn = @convention(c) (PluginCtx?) -> UnsafePointer<CChar>?
private typealias InvokeFn =
  @convention(c) (PluginCtx?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?)
  -> UnsafePointer<CChar>?

private struct PluginAPI {
  var free_string: FreeStringFn?
  var `init`: InitFn?
  var destroy: DestroyFn?
  var get_manifest: ManifestFn?
  var invoke: InvokeFn?
}

// Dummy context - we don't need state but API requires non-nil
private class PluginContext {}

nonisolated(unsafe) private var api: PluginAPI = {
  var api = PluginAPI()
  api.free_string = { if let p = $0 { free(UnsafeMutableRawPointer(mutating: p)) } }
  api.`init` = { Unmanaged.passRetained(PluginContext()).toOpaque() }
  api.destroy = { if let p = $0 { Unmanaged<PluginContext>.fromOpaque(p).release() } }
  api.get_manifest = { _ in makeCString(manifest) }
  api.invoke = { _, typePtr, idPtr, payloadPtr in
    guard let typePtr, let idPtr, let payloadPtr else { return nil }
    let type = String(cString: typePtr)
    let id = String(cString: idPtr)
    let payload = String(cString: payloadPtr)
    guard type == "tool" else { return makeCString(jsonError("Unknown capability type")) }
    guard let tool = tools[id] else { return makeCString(jsonError("Unknown tool: \(id)")) }
    return makeCString(tool(payload))
  }
  return api
}()

@_cdecl("osaurus_plugin_entry")
public func osaurus_plugin_entry() -> UnsafeRawPointer? {
  UnsafeRawPointer(&api)
}
