package com.galaxyssi.chat

import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.view.ContextThemeWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.NetworkType
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout
import java.util.UUID
import java.util.Locale
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AttentionLocalTranslationDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun report(text: String) = instrumentation.sendStatus(0, Bundle().apply { putString("stream", "$text\n") })

    @Test fun headlineWorkerDoesNotRequireNetworkForInstalledModels() {
        assertEquals(NetworkType.NOT_REQUIRED, ProactiveAttentionTitleScheduler.buildRequest(0).workSpec.constraints.requiredNetworkType)
    }

    @Test fun acceptedTranslationAndProviderSurviveStoreRecreation() {
        val context = instrumentation.targetContext
        val id = UUID.randomUUID().toString()
        val title = "Local translation persistence $id"
        val translated = "\u672c\u5730\u7ffb\u8bd1 $id"
        val key = ProactiveAttentionTitlePolicy.key(title)
        val database = AgentEncryptedDatabase(context, "attention_titles_v1")
        try {
            assertTrue(ProactiveAttentionTitleStore(context).save(title, translated, AttentionMlKitTranslator.PROVIDER))
            val restored = ProactiveAttentionTitleStore(context)
            assertEquals(translated, restored.translation(title))
            assertEquals(AttentionMlKitTranslator.PROVIDER, JSONObject(database.readString(key, "{}")).getString("provider"))
            assertTrue(restored.save(title, "\u5176\u4ed6\u8bd1\u6587 $id"))
            assertEquals(translated, restored.translation(title))
            assertEquals(AttentionMlKitTranslator.PROVIDER, JSONObject(database.readString(key, "{}")).getString("provider"))
        } finally { database.remove(key) }
    }

    @Test fun attributionAppearsOnlyForDisplayedMlKitTranslationWithoutResizingTheRow() {
        instrumentation.runOnMainSync {
            val configuration = android.content.res.Configuration(instrumentation.targetContext.resources.configuration)
                .apply { setLocale(Locale.SIMPLIFIED_CHINESE) }
            val context = ContextThemeWrapper(instrumentation.targetContext.createConfigurationContext(configuration),
                android.R.style.Theme_Material_Light)
            val message = GlobalProactiveMessage(id = "local-title-view", sourceEventId = "local-title-view",
                sourceConversationId = "", target = GlobalProactiveTarget.GLOBAL_DIGEST, title = "New feature",
                content = "Public summary", topic = "AI", urgent = false, status = GlobalProactiveMessageStatus.DELIVERED)
            val item = GlobalProactiveInboxPolicy.project(listOf(message), emptyList()).single()
            val view = ProactiveAttentionArticleView(context, {}, {}, {}, {}, { _, callback -> callback(null) }, {})
            fun height(): Int {
                view.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                return view.measuredHeight
            }
            view.bind(AttentionReaderRow(item, false, false))
            val before = height()
            assertNotEquals(View.VISIBLE, view.findViewWithTag<View>("attention-translation-attribution:${item.key}").visibility)
            val translated = item.copy(translatedTitle = "\u65b0\u529f\u80fd", titleTranslationProvider = AttentionMlKitTranslator.PROVIDER)
            view.updateStatus(AttentionReaderRow(translated, false, false))
            assertEquals(View.VISIBLE, view.findViewWithTag<View>("attention-translation-attribution:${item.key}").visibility)
            assertEquals(before, height())
            view.updateStatus(AttentionReaderRow(translated.copy(titleTranslationProvider = ""), false, false))
            assertNotEquals(View.VISIBLE, view.findViewWithTag<View>("attention-translation-attribution:${item.key}").visibility)
        }
    }

    @Test fun translatePublicHeadlinesWithRealOnDeviceModel() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("attention_local_live") == "true")
        if (args.getString("attention_local_download") == "true") {
            val start = SystemClock.elapsedRealtime()
            withTimeout(240_000) {
                RemoteModelManager.getInstance().download(AttentionMlKitTranslator.model(),
                    DownloadConditions.Builder().requireWifi().build()).await()
            }
            report("local_translation_model_download_ms=${SystemClock.elapsedRealtime() - start}")
        }
        AttentionMlKitTranslator().use { assertTrue("On-device model is not installed", it.isReady()) }
        val titles = listOf("New battery technology improves energy efficiency", "Researchers discover a new planet",
            "Scientists develop a faster computer chip", "New camera captures clearer images at night",
            "Software update fixes security problems", "New satellite improves weather forecasts",
            "Model 2.1 released with 20% lower latency", "Eight states accuse OpenAI in lawsuit")
            .mapIndexed { index, title -> "sample-$index" to title }.toMap()
        val saved = mutableMapOf<String, String>()
        var start = SystemClock.elapsedRealtime()
        val pipeline = AttentionLocalTitleTranslation(::AttentionMlKitTranslator, { saved[it].orEmpty() }, { title, text ->
            report("local_title_ms=${SystemClock.elapsedRealtime() - start} source=$title translated=$text")
            start = SystemClock.elapsedRealtime()
            saved[title] = text
        }, { fail("An installed model must not trigger download") })
        val result = pipeline.translate(titles)
        report("local_batch_saved=${result.translated} fallback=${result.remaining.size} reason=${result.reason}")
        assertTrue("No ordinary public headline was translated locally", result.translated >= 6)
        saved.forEach { (title, text) -> assertTrue(ProactiveAttentionTitlePolicy.valid(title, text)) }
        val cached = saved.toMap()
        val cachedOnly = AttentionLocalTitleTranslation({ error("Cache must not initialize ML Kit") },
            { saved[it].orEmpty() }, { _, _ -> fail() }, { fail() })
        assertTrue(cachedOnly.translate(titles.filterValues { it in cached }).remaining.isEmpty())
        assertEquals(cached, saved)
    }
}
