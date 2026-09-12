import unittest

from artifact_reference_text import strip_internal_artifact_links
from rich_output import build_rich_output


class ArtifactReferenceTextTests(unittest.TestCase):
    def test_internal_image_and_file_links_are_hidden(self):
        for label in ("![Image]", "[Download]"):
            for target in ("galaxyssi-artifact://task/outputs/result.png",
                           "<GALAXYSSI-ARTIFACT://task/outputs/image_(1).png> \"Image\""):
                with self.subTest(label=label, target=target):
                    self.assertEqual("Before  after", strip_internal_artifact_links(
                        f"Before {label}({target}) after"))

    def test_multiline_lists_quotes_and_multiple_references(self):
        target = "galaxyssi-artifact://task/outputs/image.png"
        source = f"Before\n\n> ![Image](\n<{target}>\n)\n\n- [File]({target})\n\nAfter"
        clean = strip_internal_artifact_links(source)
        self.assertNotIn(target, clean)
        self.assertIn("Before", clean)
        self.assertIn("After", clean)

    def test_web_links_images_and_code_examples_are_unchanged(self):
        internal = "![Image](galaxyssi-artifact://task/outputs/image.png)"
        for source in ("![Image](https://example.com/image.png)",
                       "[Source](https://example.com/page)",
                       "```markdown\n" + internal + "\n```",
                       "~~~markdown\n" + internal + "\n~~~",
                       "`" + internal + "`", "\\[File](galaxyssi-artifact://task/file)"):
            self.assertEqual(source, strip_internal_artifact_links(source))

    def test_rich_text_does_not_reintroduce_reference(self):
        source = '```galaxyssi-rich\n{"blocks":[{"type":"text","text":"Done. ![Image](galaxyssi-artifact://task/outputs/image.png)"}]}\n```'
        fallback, document = build_rich_output(source)
        self.assertEqual("Done.", fallback)
        self.assertEqual("Done.", document["blocks"][0]["text"])

    def test_reference_only_cannot_fall_back_to_raw_path(self):
        fallback, document = build_rich_output("![Image](galaxyssi-artifact://task/outputs/image.png)")
        self.assertEqual("The generated file is unavailable. Please try again.", fallback)
        self.assertIsNone(document)
