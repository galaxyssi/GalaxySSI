package com.galaxyssi.chat

import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit public-URL diagnostic only; never runs on private messages or in production. */
@RunWith(AndroidJUnit4::class)
class AttentionArticleTranslationDiagnosticsTest {
    @Test fun inspectPublicTranslationValidation() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val url = InstrumentationRegistry.getArguments().getString("attention_translation_diagnostic_url")
        assumeTrue(!url.isNullOrBlank())
        fun report(text: String) = instrumentation.sendStatus(0, Bundle().apply { putString("stream", text + "\n") })
        val fetcher = AgentBoundedWebIntelligenceFetcher(AgentBoundedWebService(AgentPinnedOkHttpWebTransport(),
            policy = AgentWebPolicy(maxTimeoutMillis = 20_000)))
        val page = fetcher.fetch(url!!, 10 * 1024 * 1024, 20_000, AgentNativeToolCancellationToken.NONE, {})
        val article = try { AttentionArticlePolicy.extract(page) } finally { page.body.fill(0) }
        val client = Translation.getClient(TranslatorOptions.Builder().setSourceLanguage(TranslateLanguage.ENGLISH)
            .setTargetLanguage(TranslateLanguage.CHINESE).build())
        try {
            val digits = Regex("\\d+(?:[.,]\\d+)*")
            for ((index, part) in (listOf(article.title) + AttentionArticlePolicy.translationChunks(article.content)).withIndex()) {
                val translated = client.translate(part).await()
                val failure = runCatching { AttentionArticlePolicy.validateTranslation(part, translated) }.exceptionOrNull() ?: continue
                report("segment=$index reason=${failure.message} source_numbers=${digits.findAll(part).map { it.value }.toList()} " +
                    "translated_numbers=${digits.findAll(translated).map { it.value }.toList()}")
                val tokens = mutableListOf<String>()
                val protected = digits.replace(part) { match -> tokens += match.value; "ZXQNUM${tokens.lastIndex}QXZ" }
                val raw = client.translate(protected).await()
                var restored = raw
                for ((i, value) in tokens.withIndex()) restored = restored.replace("ZXQNUM${i}QXZ", value)
                report("protected_retry=$index valid=${runCatching { AttentionArticlePolicy.validateTranslation(part, restored) }.isSuccess} " +
                    "tokens_remaining=${restored.contains("ZXQNUM")} source_excerpt=${part.take(120)} result_excerpt=${translated.take(120)}")
            }
        } finally { client.close() }
    }
}
