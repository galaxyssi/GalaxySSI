import unittest

from desktop_public_articles import dynamic_article_headers, parse_public_article
from web_intelligence import MAX_FETCH_BYTES


class DesktopPublicArticleTests(unittest.TestCase):
    def test_wechat_article_extracts_body_and_original_images(self):
        article = parse_public_article(
            "https://mp.weixin.qq.com/s/example",
            """
            <html><head><meta property="og:title" content="Fallback title"></head><body>
              <h1 id="activity-name">Desktop article</h1>
              <span id="js_name">GalaxySSI Lab</span>
              <em id="publish_time">2026-08-11</em>
              <div id="js_content">
                <p>First paragraph.</p><p>Second paragraph.</p>
                <img data-src="https://mmbiz.qpic.cn/test/image.png" alt="Diagram">
                <a href="/s/related">Related</a>
              </div>
            </body></html>
            """,
        )

        self.assertIsNotNone(article)
        self.assertEqual("Desktop article", article["title"])
        self.assertEqual("GalaxySSI Lab", article["author"])
        self.assertIn("First paragraph.", article["content"])
        self.assertEqual("https://mmbiz.qpic.cn/test/image.png", article["images"][0]["url"])
        self.assertEqual("https://mp.weixin.qq.com/s/related", article["links"][0])

    def test_mobile_compatibility_headers_are_scoped_to_wechat(self):
        headers = dynamic_article_headers("https://mp.weixin.qq.com/s/example")

        self.assertIn("MicroMessenger", headers["User-Agent"])
        self.assertEqual("https://mp.weixin.qq.com/", headers["Referer"])
        self.assertEqual({}, dynamic_article_headers("https://example.com/"))
        self.assertEqual(10 * 1024 * 1024, MAX_FETCH_BYTES)


if __name__ == "__main__":
    unittest.main()
