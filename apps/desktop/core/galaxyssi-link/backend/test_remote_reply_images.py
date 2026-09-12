from __future__ import annotations

import io
import json
import os
import socket
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from PIL import Image

from remote_image_transport import ImageDownloadError, PublicImageTransport, public_destination
from remote_reply_images import _image_spans, _validate_image, image_link_preview, prepare_reply_images
from rich_output import build_rich_output


def image_bytes():
    output = io.BytesIO()
    Image.new("RGB", (32, 24), "green").save(output, format="PNG")
    return output.getvalue()


class FakeTransport:
    def __init__(self, data=None, error=None):
        self.data = image_bytes() if data is None else data
        self.error = error
        self.calls = []

    def fetch(self, url, **kwargs):
        self.calls.append(url)
        if self.error:
            raise ImageDownloadError(self.error)
        return self.data


class RemoteReplyImagesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.environment = patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": self.directory.name})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.scope = dict(task_id="image-task", client_route_id="phone-a", conversation_id="conversation-a",
                          turn_id="turn-a", source_message_id="42", execution_generation=1)

    def prepare(self, text, transport=None, **kwargs):
        return prepare_reply_images(self.scope["task_id"], text, scope=self.scope,
                                    transport=transport or FakeTransport(), **kwargs)

    def test_parser_ignores_code_escaped_images_and_ordinary_links(self):
        text = ('`![example](https://example.com/code.png)` ![real](https://example.com/real.png)\n\n'
                '```text\n![code](https://example.com/fence.png)\n```\n'
                '\\![escaped](https://example.com/escaped.png) [web](https://example.com/web.png)')
        spans = list(_image_spans(text))
        self.assertEqual(["https://example.com/real.png"], [item[2] for item in spans])
        self.assertEqual("![real](https://example.com/real.png)", text[spans[0][0]:spans[0][1]])

    def test_parser_handles_headings_lists_quotes_and_reference_images(self):
        text = ('# ![heading](https://example.com/a.png)\n\n'
                '- line\n  ![list](https://example.com/b.png "title")\n\n'
                '> quote\n> ![reference][r]\n\n[r]: https://example.com/c.png\n')
        spans = list(_image_spans(text))
        self.assertEqual(3, len(spans))
        for start, end, _, _ in spans:
            self.assertTrue(text[start:end].startswith("!["))

    def test_download_is_scoped_deduplicated_cached_and_delivered_as_one_local_image(self):
        text = "Fish:\n\n![Fish](https://example.com/fish.webp)\n\n![Fish](https://example.com/fish.webp)"
        transport = FakeTransport()
        result = self.prepare(text, transport)
        self.assertEqual(1, len(transport.calls))
        self.assertEqual(1, len(result.files))
        self.assertNotIn("https://example.com/fish.webp", result.content)
        self.assertEqual(result, self.prepare(text, FakeTransport(error="must_not_fetch")))
        file = result.files[0]
        self.assertEqual("image/png", file["mime_type"])
        self.assertEqual("Fish.png", file["name"])
        clean, rich = build_rich_output(result.content, result.include_files([]), "image-task", inline_artifacts=False)
        images = [block for block in rich["blocks"] if block["type"] == "image"]
        self.assertEqual(1, len(images))
        self.assertTrue(images[0]["uri"].startswith("galaxyssi-artifact://image-task/outputs/"))
        self.assertEqual("https://example.com/fish.webp", images[0]["metadata"]["source_url"])
        self.assertNotIn("![", clean)

    def test_new_generation_or_contact_cannot_reuse_old_download_record(self):
        first = self.prepare("![Fish](https://example.com/fish.png)")
        self.scope["execution_generation"] = 2
        second = self.prepare("![Fish](https://example.com/fish.png)")
        self.assertNotEqual(first.files[0]["relative_path"], second.files[0]["relative_path"])
        self.scope["client_route_id"] = "phone-b"
        third = self.prepare("![Fish](https://example.com/fish.png)")
        self.assertNotEqual(second.files[0]["relative_path"], third.files[0]["relative_path"])

    def test_failure_does_not_leave_an_automatic_external_image(self):
        result = self.prepare("\u9c7c\uff1a![Fish](https://example.com/fish.webp)", FakeTransport(error="image_http_403"))
        self.assertEqual((), result.files)
        self.assertNotIn("![", result.content)
        self.assertIn("\u56fe\u7247\u6765\u6e90\u62d2\u7edd\u8bbf\u95ee", result.content)
        self.assertIn("403", result.content)
        self.assertIn("https://example.com/fish.webp", result.content)

    def test_html_with_image_url_is_not_registered_as_an_artifact(self):
        result = self.prepare("![Fish](https://example.com/fish.png)", FakeTransport(data=b"<html>challenge</html>"))
        self.assertEqual((), result.files)
        self.assertEqual("invalid_image_data", result.failures[0]["error_code"])

    def test_tampered_cached_image_is_rejected_without_network_refresh(self):
        text = "![Fish](https://example.com/fish.png)"
        first = self.prepare(text)
        path = Path(self.directory.name) / "tasks" / "image-task" / first.files[0]["relative_path"]
        path.write_bytes(b"changed")
        transport = FakeTransport()
        second = self.prepare(text, transport)
        self.assertEqual([], transport.calls)
        self.assertEqual((), second.files)
        self.assertEqual("image_source_changed", second.failures[0]["error_code"])

    def test_explicit_rich_image_uses_same_artifact_without_duplicate(self):
        text = '```galaxyssi-rich\n{"version":1,"blocks":[{"type":"image","title":"Fish","uri":"https://example.com/fish.png"}]}\n```'
        result = self.prepare(text)
        _, rich = build_rich_output(result.content, result.include_files([]), "image-task", inline_artifacts=False)
        self.assertEqual(1, len([block for block in rich["blocks"] if block["type"] == "image"]))

    def test_fenced_rich_example_does_not_download(self):
        text = '````text\n```galaxyssi-rich\n{"blocks":[{"type":"image","uri":"https://example.com/a.png"}]}\n```\n````'
        transport = FakeTransport()
        self.assertEqual(text, self.prepare(text, transport).content)
        self.assertEqual([], transport.calls)

    def test_gallery_and_image_file_cards_use_the_download_path(self):
        document = {"blocks": [{"type": "gallery", "rows": [["https://example.com/a.png", "A"],
                               ["https://example.com/b.png", "B"]]},
                               {"type": "file", "uri": "https://example.com/c.webp"}]}
        result = self.prepare("```galaxyssi-rich\n" + json.dumps(document) + "\n```")
        self.assertFalse(result.failures)
        parsed = json.loads(result.content.split("\n", 1)[1].rsplit("```", 1)[0])
        self.assertEqual(3, len(parsed["blocks"]))
        self.assertTrue(all(block["type"] == "image" and block["uri"].startswith("galaxyssi-artifact://")
                            for block in parsed["blocks"]))

    def test_progress_contains_links_not_external_image_previews(self):
        source = "Image: ![Fish](https://example.com/a.png) and `![example](https://example.com/code.png)`"
        preview = image_link_preview(source)
        self.assertIn("Image: [Fish](https://example.com/a.png)", preview)
        self.assertIn("`![example](https://example.com/code.png)`", preview)
        self.assertEqual([], list(_image_spans(preview)))

    def test_count_bound_and_unchanged_plain_reply(self):
        text = "\n\n".join(f"![Fish](https://example.com/{index}.png)" for index in range(10))
        transport = FakeTransport()
        result = self.prepare(text, transport)
        self.assertEqual(8, len(transport.calls), result.failures)
        self.assertEqual(2, len(result.failures))
        transport = FakeTransport()
        self.assertEqual("hello", self.prepare("hello", transport).content)
        self.assertEqual([], transport.calls)

    def test_missing_scope_makes_no_network_request(self):
        self.scope.pop("conversation_id")
        transport = FakeTransport()
        result = self.prepare("![Fish](https://example.com/fish.png)", transport)
        self.assertEqual([], transport.calls)
        self.assertNotIn("![", result.content)
        self.assertEqual("missing_image_delivery_scope", result.failures[0]["error_code"])

    def test_malformed_url_does_not_break_other_images(self):
        document = {"blocks": [{"type": "image", "uri": "https://[broken/image.png"},
                                {"type": "image", "uri": "https://example.com/a.png", "title": 123}]}
        class ValidatingTransport(FakeTransport):
            def fetch(self, url, **kwargs):
                public_destination(url, lambda *a, **kw: [
                    (socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.216.34", 443))])
                return super().fetch(url, **kwargs)
        transport = ValidatingTransport()
        result = self.prepare("```galaxyssi-rich\n" + json.dumps(document) + "\n```", transport)
        self.assertEqual(["https://example.com/a.png"], transport.calls)
        self.assertEqual(1, len(result.failures))
        self.assertEqual(1, len(result.files))
        self.assertEqual("123.png", result.files[0]["name"])

    def test_explicit_image_failure_keeps_a_source_link(self):
        source = '```galaxyssi-rich\n{"blocks":[{"type":"image","uri":"https://example.com/a.png"}]}\n```'
        result = self.prepare(source, FakeTransport(error="image_http_403"))
        _, rich = build_rich_output(result.content, [], "image-task", inline_artifacts=False)
        self.assertEqual("link", rich["blocks"][0]["type"])
        self.assertEqual("https://example.com/a.png", rich["blocks"][0]["uri"])
        self.assertIn("403", rich["blocks"][0]["title"])

    def test_valid_decodable_original_bytes_are_preserved(self):
        data = image_bytes()
        self.assertEqual(("png", "image/png"), _validate_image(data))
        result = self.prepare("![Fish](https://example.com/fish.png)", FakeTransport(data=data))
        path = Path(self.directory.name) / "tasks" / "image-task" / result.files[0]["relative_path"]
        self.assertEqual(data, path.read_bytes())

    def test_small_webp_has_image_mime_even_without_os_file_associations(self):
        from artifact_delivery import _guess_mime_type, prepare_artifacts
        output = io.BytesIO()
        Image.new("RGB", (32, 24), "blue").save(output, format="WEBP")
        result = self.prepare("![Fish](https://example.com/fish.webp)", FakeTransport(data=output.getvalue()))
        with patch("artifact_delivery.mimetypes.guess_type", return_value=(None, None)):
            artifacts = prepare_artifacts(self.scope["task_id"], list(result.files))
            for suffix, mime in (("webp", "image/webp"), ("png", "image/png"), ("gif", "image/gif"),
                                 ("avif", "image/avif"), ("jpg", "image/jpeg"), ("jpeg", "image/jpeg")):
                self.assertEqual(mime, _guess_mime_type("image." + suffix))
        self.assertEqual("image/webp", artifacts[0].mime_type)
        self.assertEqual(output.getvalue(), artifacts[0].transport_bytes)


class ImageTransportTest(unittest.TestCase):
    def test_destination_rejects_unsafe_urls_private_mixed_dns_and_multicast(self):
        resolver = lambda *_args, **_kwargs: [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.216.34", 443))]
        for url in ("http://example.com/a.png", "https://u:p@example.com/a.png", "https://example.com:8000/a.png",
                    "file:///etc/passwd", "https://example.com/\n"):
            with self.subTest(url=url), self.assertRaises(ImageDownloadError):
                public_destination(url, resolver)
        for address in ("127.0.0.1", "10.0.0.1", "169.254.169.254", "::1", "fc00::1", "224.0.0.1"):
            mixed = lambda *_args, **_kwargs: resolver() + [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (address, 443))]
            with self.subTest(address=address), self.assertRaises(ImageDownloadError):
                public_destination("https://example.com/a.png", mixed)

    def test_fetch_pins_ip_preserves_tls_hostname_and_rejects_private_redirect(self):
        response = Mock(status=302)
        response.getheader.side_effect = lambda name, default=None: "https://127.0.0.1/private" if name == "Location" else default
        connection = Mock()
        connection.getresponse.return_value = response
        context = Mock()
        public = urlsplit_for_test("https://example.com/fish.png")
        with patch("remote_image_transport.public_destination", side_effect=[
                (public, ["93.184.216.34"]), ImageDownloadError("non_public_image_destination")]), \
                patch("remote_image_transport.socket.create_connection") as connect, \
                patch("remote_image_transport.ssl.create_default_context", return_value=context), \
                patch("remote_image_transport.http.client.HTTPSConnection", return_value=connection):
            with self.assertRaisesRegex(ImageDownloadError, "non_public"):
                PublicImageTransport().fetch("https://example.com/fish.png", deadline=time.monotonic() + 10)
            self.assertEqual(("93.184.216.34", 443), connect.call_args.args[0])
            self.assertEqual("example.com", context.wrap_socket.call_args.kwargs["server_hostname"])
            self.assertEqual(0, connection.auto_open)
            self.assertEqual("example.com", connection.request.call_args.kwargs["headers"]["Host"])
            response.close.assert_called_once()
            connection.close.assert_called()

    def test_chunked_body_obeys_byte_limit_and_closes_response(self):
        response = Mock(status=200)
        response.getheader.side_effect = lambda name, default=None: "image/png" if name == "Content-Type" else default
        response.read1.side_effect = [b"1234", b"5"]
        connection = Mock()
        connection.getresponse.return_value = response
        with patch("remote_image_transport.public_destination", return_value=(
                urlsplit_for_test("https://example.com/a.png"), ["93.184.216.34"])), \
                patch("remote_image_transport.socket.create_connection"), \
                patch("remote_image_transport.ssl.create_default_context"), \
                patch("remote_image_transport.http.client.HTTPSConnection", return_value=connection):
            with self.assertRaisesRegex(ImageDownloadError, "image_too_large"):
                PublicImageTransport().fetch("https://example.com/a.png", deadline=time.monotonic() + 10, max_bytes=4)
        response.close.assert_called_once()
        connection.close.assert_called_once()


def urlsplit_for_test(url):
    from urllib.parse import urlsplit
    return urlsplit(url)


if __name__ == "__main__":
    unittest.main()
