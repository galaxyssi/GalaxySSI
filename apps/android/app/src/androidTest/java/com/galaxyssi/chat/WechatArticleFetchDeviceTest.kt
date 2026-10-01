package com.galaxyssi.chat

import android.content.ClipboardManager
import android.os.Bundle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.jsoup.Jsoup
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Opt-in diagnostic for the article explicitly copied by the user; never part of routine tests. */
@RunWith(AndroidJUnit4::class)
class WechatArticleFetchDeviceTest {
    @Test fun inspectExplicitlyCopiedArticle() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_article") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        var url: String? = null
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            Thread.sleep(1000)
            scenario.onActivity { activity ->
                url = activity.getSystemService(ClipboardManager::class.java).primaryClip?.getItemAt(0)?.text
                    ?.toString()?.let(WechatArticleDocuments::articleUrl)
            }
            val source = AgentBoundedWebService(AgentPinnedOkHttpWebTransport(),
                policy = AgentWebPolicy(maxFetchBytes = 8L * 1024 * 1024)).fetch(requireNotNull(url))
            val document = Jsoup.parse(source.body.toString(Charsets.UTF_8))
            File(context.cacheDir, "wechat-live-source.html").writeBytes(source.body)
            val diagnostic = "bytes=${source.body.size} status=${source.statusCode} " +
                "article_url=${WechatArticleDocuments.articleUrl(source.finalUrl) != null} " +
                "body=${document.selectFirst("#js_content") != null} " +
                "title=${document.selectFirst("#activity-name") != null} " +
                "extract=${runCatching { WechatArticleDocuments.extract(source.finalUrl, source.body) }.exceptionOrNull()?.message ?: "ok"}"
            instrumentation.sendStatus(0, Bundle().apply { putString("stream", diagnostic) })
        }
    }
}
