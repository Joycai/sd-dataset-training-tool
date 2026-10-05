"""Versioned image processing contract, independent of model/GPU imports."""
import base64
import io

from PIL import Image, ImageOps

MAX_BYTES = 100 * 1024 * 1024
MAX_PIXELS = 40_000_000


def process_foreground(data, predict):
    if not isinstance(data, dict) or data.get("version") != 1:
        raise ValueError("Expected image processing contract version 1")
    if not isinstance(data.get("model"), str) or not data["model"].strip():
        raise ValueError("An explicit editor model is required")
    encoded = data.get("image", "")
    if not isinstance(encoded, str) or len(encoded) > MAX_BYTES * 4 // 3 + 4:
        raise ValueError("Image exceeds 100 MiB")
    raw = base64.b64decode(encoded, validate=True)
    if len(raw) > MAX_BYTES:
        raise ValueError("Image exceeds 100 MiB")
    with Image.open(io.BytesIO(raw)) as original:
        if original.width * original.height > MAX_PIXELS or getattr(original, "n_frames", 1) != 1:
            raise ValueError("Use one frame up to 40 megapixels")
        source = ImageOps.exif_transpose(original).convert("RGB")
        result = predict(data["model"], source)
        if not isinstance(result, Image.Image) or result.size != source.size or "A" not in result.getbands():
            raise ValueError("Editor must return source-sized RGBA pixels")
        output = io.BytesIO()
        # The contract always preserves alpha regardless of input filename.
        result.save(output, format="PNG")
        alpha = result.getchannel("A")
        bounds = alpha.point(lambda value: 255 if value >= 128 else 0).getbbox()
        return {"version": 1, "mime_type": "image/png", "image": base64.b64encode(output.getvalue()).decode("ascii"),
                "width": result.width, "height": result.height,
                "coordinate_frame": "exif_normalized_pixels", "foreground_bounds": bounds}
