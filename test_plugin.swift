#!/usr/bin/env swift

import Foundation

// Load the plugin
typealias osr_free_string_t = @convention(c) (UnsafePointer<CChar>?) -> Void
typealias osr_init_t = @convention(c) () -> UnsafeMutableRawPointer?
typealias osr_destroy_t = @convention(c) (UnsafeMutableRawPointer?) -> Void
typealias osr_get_manifest_t = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
typealias osr_invoke_t = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafePointer<CChar>?

struct osr_plugin_api {
    var free_string: osr_free_string_t?
    var `init`: osr_init_t?
    var destroy: osr_destroy_t?
    var get_manifest: osr_get_manifest_t?
    var invoke: osr_invoke_t?
}

let dylibPath = ".build/release/libosaurus-images.dylib"
guard let handle = dlopen(dylibPath, RTLD_NOW) else {
    print("❌ Failed to load \(dylibPath): \(String(cString: dlerror()))")
    exit(1)
}

guard let entryPtr = dlsym(handle, "osaurus_plugin_entry") else {
    print("❌ Failed to find osaurus_plugin_entry")
    exit(1)
}

typealias EntryFunc = @convention(c) () -> UnsafeRawPointer?
let entry = unsafeBitCast(entryPtr, to: EntryFunc.self)

guard let rawApiPtr = entry() else {
    print("❌ Entry returned nil")
    exit(1)
}

let api = rawApiPtr.assumingMemoryBound(to: osr_plugin_api.self).pointee
print("✅ Plugin loaded successfully\n")

// Initialize context
guard let ctx = api.`init`?() else {
    print("❌ Failed to initialize context")
    exit(1)
}

// Helper to invoke a tool
func invoke(_ toolId: String, _ payload: String) -> String {
    guard let result = api.invoke?(ctx, "tool", toolId, payload) else {
        return "{\"error\": \"invoke returned nil\"}"
    }
    let str = String(cString: result)
    api.free_string?(result)
    return str
}

func test(_ name: String, _ toolId: String, _ payload: String) {
    print("📋 Testing: \(name)")
    print("   Tool: \(toolId)")
    print("   Input: \(payload)")
    let result = invoke(toolId, payload)
    if result.contains("\"error\"") {
        print("   ❌ Result: \(result)\n")
    } else {
        print("   ✅ Result: \(result)\n")
    }
}

let testDir = "test_images"
let testImage = "\(testDir)/test.png"
let fm = FileManager.default

// Make copies for tests that modify images
func copyForTest(_ name: String) -> String {
    let dest = "\(testDir)/\(name).png"
    try? fm.removeItem(atPath: dest)
    try? fm.copyItem(atPath: testImage, toPath: dest)
    return dest
}

print("=" * 60)
print("OSAURUS IMAGES PLUGIN TEST")
print("=" * 60 + "\n")

// 1. get_image_info (read-only)
test("Get Image Info", "get_image_info", "{\"input_path\": \"\(testImage)\"}")

// 2. extract_colors (read-only)
test("Extract Colors", "extract_colors", "{\"input_path\": \"\(testImage)\", \"count\": 5}")

// 3. convert_image
let convertTest = copyForTest("convert_test")
test("Convert to JPEG", "convert_image", "{\"input_path\": \"\(convertTest)\", \"output_format\": \"jpeg\"}")

// 4. optimize_image
let optimizeTest = copyForTest("optimize_test")
test("Optimize Image", "optimize_image", "{\"input_path\": \"\(optimizeTest)\", \"quality\": 0.7}")

// 5. rotate_image
let rotateTest = copyForTest("rotate_test")
test("Rotate 90°", "rotate_image", "{\"input_path\": \"\(rotateTest)\", \"degrees\": 90}")

// 6. flip_image
let flipTest = copyForTest("flip_test")
test("Flip Horizontal", "flip_image", "{\"input_path\": \"\(flipTest)\", \"direction\": \"horizontal\"}")

// 7. crop_image
let cropTest = copyForTest("crop_test")
test("Crop Region", "crop_image", "{\"input_path\": \"\(cropTest)\", \"x\": 10, \"y\": 10, \"width\": 100, \"height\": 80}")

// 8. resize_image
let resizeTest = copyForTest("resize_test")
test("Resize to 100px width", "resize_image", "{\"input_path\": \"\(resizeTest)\", \"width\": 100}")

// 9. resize with scale
let scaleTest = copyForTest("scale_test")
test("Scale to 50%", "resize_image", "{\"input_path\": \"\(scaleTest)\", \"scale\": 50}")

// 10. strip_metadata
let stripTest = copyForTest("strip_test")
test("Strip Metadata", "strip_metadata", "{\"input_path\": \"\(stripTest)\"}")

// 11. adjust_colors
let colorsTest = copyForTest("colors_test")
test("Adjust Colors", "adjust_colors", "{\"input_path\": \"\(colorsTest)\", \"brightness\": 0.2, \"contrast\": 1.2, \"saturation\": 1.5}")

// 12. apply_filter - grayscale
let grayTest = copyForTest("gray_test")
test("Grayscale Filter", "apply_filter", "{\"input_path\": \"\(grayTest)\", \"filter\": \"grayscale\"}")

// 13. apply_filter - sepia
let sepiaTest = copyForTest("sepia_test")
test("Sepia Filter", "apply_filter", "{\"input_path\": \"\(sepiaTest)\", \"filter\": \"sepia\", \"intensity\": 0.8}")

// 14. apply_filter - blur
let blurTest = copyForTest("blur_test")
test("Blur Filter", "apply_filter", "{\"input_path\": \"\(blurTest)\", \"filter\": \"blur\", \"intensity\": 0.5}")

// 15. add_watermark (text)
let wmTextTest = copyForTest("watermark_text_test")
test("Text Watermark", "add_watermark", "{\"input_path\": \"\(wmTextTest)\", \"text\": \"SAMPLE\", \"position\": \"bottom-right\", \"opacity\": 0.7}")

// 16. add_border
let borderTest = copyForTest("border_test")
test("Add Border", "add_border", "{\"input_path\": \"\(borderTest)\", \"width\": 10, \"color\": \"#FF5500\"}")

// 17. round_corners
let roundTest = copyForTest("round_test")
test("Round Corners", "round_corners", "{\"input_path\": \"\(roundTest)\", \"radius\": 20}")

// 18. composite_images
let baseImg = copyForTest("composite_base")
let overlayImg = copyForTest("composite_overlay")
// First resize overlay to be smaller
_ = invoke("resize_image", "{\"input_path\": \"\(overlayImg)\", \"scale\": 30}")
test("Composite Images", "composite_images", "{\"base_path\": \"\(baseImg)\", \"overlay_path\": \"\(overlayImg)\", \"x\": 50, \"y\": 50, \"opacity\": 0.8}")

// Cleanup
api.destroy?(ctx)
dlclose(handle)

print("=" * 60)
print("TEST COMPLETE")
print("=" * 60)
print("\nGenerated test files in: \(testDir)/")

// List generated files
if let files = try? fm.contentsOfDirectory(atPath: testDir) {
    print("\nFiles created:")
    for file in files.sorted() {
        if let attrs = try? fm.attributesOfItem(atPath: "\(testDir)/\(file)"),
           let size = attrs[.size] as? Int {
            print("  - \(file) (\(size) bytes)")
        }
    }
}

extension String {
    static func *(lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}
