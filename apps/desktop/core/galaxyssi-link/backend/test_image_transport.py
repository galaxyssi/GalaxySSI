import unittest

from image_transport import MAX_IMAGE_TRANSPORT_BYTES, compress_pil_image


class ImageTransportTests(unittest.TestCase):
    def test_noisy_desktop_frame_is_encoded_below_shared_limit(self):
        from PIL import Image

        width, height = 1920, 1080
        pixels = bytearray(width * height * 3)
        state = 0x2468ACE1
        for index in range(0, len(pixels), 3):
            state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
            pixels[index:index + 3] = bytes((state & 0xFF, (state >> 8) & 0xFF, (state >> 16) & 0xFF))
        source = Image.frombytes("RGB", (width, height), bytes(pixels))
        try:
            encoded = compress_pil_image(source)
        finally:
            source.close()

        self.assertIsNotNone(encoded)
        self.assertLessEqual(len(encoded.data), MAX_IMAGE_TRANSPORT_BYTES)
        self.assertGreater(encoded.width, 0)
        self.assertGreater(encoded.height, 0)
        self.assertEqual("image/jpeg", encoded.mime_type)


if __name__ == "__main__":
    unittest.main()
