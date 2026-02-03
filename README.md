# Osaurus Images

A powerful image manipulation plugin for [Osaurus](https://osaurus.dev). Provides 15 tools for image conversion, manipulation, optimization, filtering, and composition.

## Features

- **Format Conversion** - Convert between PNG, JPEG, GIF, TIFF, BMP, HEIC, and WebP
- **Image Manipulation** - Rotate, flip, crop, and resize images
- **Optimization** - Reduce file size while maintaining quality
- **Metadata** - Extract image info and strip EXIF data for privacy
- **Filters** - Apply grayscale, sepia, blur, sharpen, and invert effects
- **Color Analysis** - Extract dominant colors from images
- **Composition** - Add watermarks, borders, rounded corners, and overlay images

## Tools

### Conversion Tools

#### `convert_image`

Convert an image to a different format.

| Parameter       | Type   | Required | Description                                                        |
| --------------- | ------ | -------- | ------------------------------------------------------------------ |
| `input_path`    | string | Yes      | Path to the input image                                            |
| `output_format` | string | Yes      | Target format: `png`, `jpeg`, `gif`, `tiff`, `bmp`, `heic`, `webp` |

**Example:** Convert PNG to JPEG

```json
{ "input_path": "/path/to/image.png", "output_format": "jpeg" }
```

#### `optimize_image`

Reduce image file size by re-encoding with compression.

| Parameter    | Type   | Required | Description                          |
| ------------ | ------ | -------- | ------------------------------------ |
| `input_path` | string | Yes      | Path to the input image              |
| `quality`    | number | No       | Quality level 0.0-1.0 (default: 0.8) |

**Example:** Optimize with 70% quality

```json
{ "input_path": "/path/to/image.png", "quality": 0.7 }
```

---

### Manipulation Tools

#### `rotate_image`

Rotate an image by a specified angle.

| Parameter    | Type   | Required | Description                                   |
| ------------ | ------ | -------- | --------------------------------------------- |
| `input_path` | string | Yes      | Path to the input image                       |
| `degrees`    | number | Yes      | Rotation angle (positive = counter-clockwise) |

**Example:** Rotate 90 degrees

```json
{ "input_path": "/path/to/image.png", "degrees": 90 }
```

#### `flip_image`

Flip an image horizontally or vertically.

| Parameter    | Type   | Required | Description                |
| ------------ | ------ | -------- | -------------------------- |
| `input_path` | string | Yes      | Path to the input image    |
| `direction`  | string | Yes      | `horizontal` or `vertical` |

**Example:** Mirror horizontally

```json
{ "input_path": "/path/to/image.png", "direction": "horizontal" }
```

#### `crop_image`

Crop an image to a specified region.

| Parameter    | Type    | Required | Description                     |
| ------------ | ------- | -------- | ------------------------------- |
| `input_path` | string  | Yes      | Path to the input image         |
| `x`          | integer | Yes      | X coordinate of top-left corner |
| `y`          | integer | Yes      | Y coordinate of top-left corner |
| `width`      | integer | Yes      | Width of crop region            |
| `height`     | integer | Yes      | Height of crop region           |

**Example:** Crop 100x100 region from (50, 50)

```json
{
  "input_path": "/path/to/image.png",
  "x": 50,
  "y": 50,
  "width": 100,
  "height": 100
}
```

#### `resize_image`

Resize an image to new dimensions or scale.

| Parameter    | Type    | Required | Description                             |
| ------------ | ------- | -------- | --------------------------------------- |
| `input_path` | string  | Yes      | Path to the input image                 |
| `width`      | integer | No       | New width in pixels                     |
| `height`     | integer | No       | New height in pixels                    |
| `scale`      | number  | No       | Scale percentage (e.g., 50 = half size) |

**Examples:**

```json
// Resize to specific width (height auto-calculated)
{"input_path": "/path/to/image.png", "width": 800}

// Resize to exact dimensions
{"input_path": "/path/to/image.png", "width": 800, "height": 600}

// Scale to 50%
{"input_path": "/path/to/image.png", "scale": 50}
```

---

### Metadata Tools

#### `get_image_info`

Get metadata and information about an image.

| Parameter    | Type   | Required | Description             |
| ------------ | ------ | -------- | ----------------------- |
| `input_path` | string | Yes      | Path to the input image |

**Response includes:** width, height, format, file_size, color_model, bit_depth, dpi, has_alpha, exif data

**Example:**

```json
{ "input_path": "/path/to/image.png" }
```

#### `strip_metadata`

Remove EXIF and other metadata from an image for privacy.

| Parameter    | Type   | Required | Description             |
| ------------ | ------ | -------- | ----------------------- |
| `input_path` | string | Yes      | Path to the input image |

**Example:**

```json
{ "input_path": "/path/to/photo.jpg" }
```

---

### Filter & Color Tools

#### `adjust_colors`

Adjust brightness, contrast, and saturation.

| Parameter    | Type   | Required | Description              |
| ------------ | ------ | -------- | ------------------------ |
| `input_path` | string | Yes      | Path to the input image  |
| `brightness` | number | No       | -1.0 to 1.0 (default: 0) |
| `contrast`   | number | No       | 0.0 to 2.0 (default: 1)  |
| `saturation` | number | No       | 0.0 to 2.0 (default: 1)  |

**Example:** Increase brightness and saturation

```json
{ "input_path": "/path/to/image.png", "brightness": 0.2, "saturation": 1.5 }
```

#### `apply_filter`

Apply a visual filter effect.

| Parameter    | Type   | Required | Description                                       |
| ------------ | ------ | -------- | ------------------------------------------------- |
| `input_path` | string | Yes      | Path to the input image                           |
| `filter`     | string | Yes      | `grayscale`, `sepia`, `blur`, `sharpen`, `invert` |
| `intensity`  | number | No       | Filter intensity 0.0-1.0 (default: 1.0)           |

**Examples:**

```json
// Convert to grayscale
{"input_path": "/path/to/image.png", "filter": "grayscale"}

// Apply sepia with 80% intensity
{"input_path": "/path/to/image.png", "filter": "sepia", "intensity": 0.8}

// Apply blur
{"input_path": "/path/to/image.png", "filter": "blur", "intensity": 0.5}
```

#### `extract_colors`

Extract dominant colors from an image.

| Parameter    | Type    | Required | Description                              |
| ------------ | ------- | -------- | ---------------------------------------- |
| `input_path` | string  | Yes      | Path to the input image                  |
| `count`      | integer | No       | Number of colors to extract (default: 5) |

**Example:**

```json
{ "input_path": "/path/to/image.png", "count": 5 }
```

**Response:**

```json
{ "colors": ["#FF5500", "#003366", "#FFFFFF", "#000000", "#808080"] }
```

---

### Composition Tools

#### `add_watermark`

Add a text or image watermark.

| Parameter    | Type   | Required | Description                                                                                |
| ------------ | ------ | -------- | ------------------------------------------------------------------------------------------ |
| `input_path` | string | Yes      | Path to the input image                                                                    |
| `text`       | string | No\*     | Text to use as watermark                                                                   |
| `image_path` | string | No\*     | Path to watermark image                                                                    |
| `position`   | string | No       | `top-left`, `top-right`, `bottom-left`, `bottom-right`, `center` (default: `bottom-right`) |
| `opacity`    | number | No       | Opacity 0.0-1.0 (default: 0.5)                                                             |

\*Either `text` or `image_path` must be provided.

**Examples:**

```json
// Text watermark
{"input_path": "/path/to/image.png", "text": "© 2024", "position": "bottom-right", "opacity": 0.7}

// Image watermark (logo)
{"input_path": "/path/to/image.png", "image_path": "/path/to/logo.png", "position": "top-left"}
```

#### `composite_images`

Overlay one image on top of another.

| Parameter      | Type    | Required | Description                            |
| -------------- | ------- | -------- | -------------------------------------- |
| `base_path`    | string  | Yes      | Path to the base image                 |
| `overlay_path` | string  | Yes      | Path to the overlay image              |
| `x`            | integer | Yes      | X position for overlay                 |
| `y`            | integer | Yes      | Y position for overlay                 |
| `opacity`      | number  | No       | Overlay opacity 0.0-1.0 (default: 1.0) |

**Example:**

```json
{
  "base_path": "/path/to/background.png",
  "overlay_path": "/path/to/foreground.png",
  "x": 100,
  "y": 50,
  "opacity": 0.8
}
```

#### `add_border`

Add a solid color border around an image.

| Parameter    | Type    | Required | Description                                  |
| ------------ | ------- | -------- | -------------------------------------------- |
| `input_path` | string  | Yes      | Path to the input image                      |
| `width`      | integer | Yes      | Border width in pixels                       |
| `color`      | string  | Yes      | Border color in hex format (e.g., `#FF0000`) |

**Example:**

```json
{ "input_path": "/path/to/image.png", "width": 10, "color": "#FF5500" }
```

#### `round_corners`

Round the corners of an image. Outputs PNG to preserve transparency.

| Parameter    | Type    | Required | Description             |
| ------------ | ------- | -------- | ----------------------- |
| `input_path` | string  | Yes      | Path to the input image |
| `radius`     | integer | Yes      | Corner radius in pixels |

**Example:**

```json
{ "input_path": "/path/to/image.png", "radius": 20 }
```

---

## Supported Formats

| Format | Extensions       | Read | Write |
| ------ | ---------------- | ---- | ----- |
| PNG    | `.png`           | ✓    | ✓     |
| JPEG   | `.jpg`, `.jpeg`  | ✓    | ✓     |
| GIF    | `.gif`           | ✓    | ✓     |
| TIFF   | `.tiff`, `.tif`  | ✓    | ✓     |
| BMP    | `.bmp`           | ✓    | ✓     |
| HEIC   | `.heic`, `.heif` | ✓    | ✓     |
| WebP   | `.webp`          | ✓    | ✓     |

---

## Development

### Build

```bash
swift build -c release
```

### Test

```bash
swift test_plugin.swift
```

### Extract Manifest

```bash
osaurus manifest extract .build/release/libosaurus-images.dylib
```

### Package for Distribution

```bash
osaurus tools package dev.osaurus.images 0.1.0
```

Creates `dev.osaurus.images-0.1.0.zip`.

### Install Locally

```bash
osaurus tools install ./dev.osaurus.images-0.1.0.zip
```

---

## Publishing

This project includes a GitHub Actions workflow that automatically builds and releases when you push a version tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

---

## Requirements

- macOS 15.0+
- Osaurus 0.5.0+

## License

MIT
