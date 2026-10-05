import base64
import io
import unittest

from PIL import Image
from AiApiServer.modules.image_processing import process_foreground


class ImageProcessingTest(unittest.TestCase):
    def request(self, fmt="JPEG"):
        buffer = io.BytesIO()
        Image.new("RGB", (20, 10), "red").save(buffer, format=fmt)
        return {"version": 1, "model": "stub", "image": base64.b64encode(buffer.getvalue()).decode()}

    def test_jpeg_input_returns_png_with_alpha(self):
        def editor(_model, image):
            output = image.convert("RGBA")
            output.putalpha(64)
            return output
        response = process_foreground(self.request(), editor)
        output = Image.open(io.BytesIO(base64.b64decode(response["image"])))
        self.assertEqual(output.format, "PNG")
        self.assertEqual(output.getpixel((0, 0))[3], 64)
        self.assertEqual(response["coordinate_frame"], "exif_normalized_pixels")

    def test_requires_matching_rgba_output(self):
        with self.assertRaises(ValueError):
            process_foreground(self.request(), lambda _m, im: im)
        with self.assertRaises(ValueError):
            process_foreground(self.request(), lambda _m, _im: Image.new("RGBA", (1, 1)))

    def test_bad_contract_rejected_before_inference(self):
        with self.assertRaises(ValueError):
            process_foreground({"version": 2}, lambda *_: self.fail("inference called"))


if __name__ == "__main__":
    unittest.main()
