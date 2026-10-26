package com.galaxyssi.chat

import android.content.Context
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.languageid.LanguageIdentification
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

internal class AttentionArticleTranslator(private val context: Context) : AutoCloseable {
    private val identifier = LanguageIdentification.getClient()
    private val clients = mutableMapOf<String, Translator>()

    suspend fun translate(title: String, body: String): AttentionChineseArticle = withTimeout(90_000L) {
        translation(body).run(title, body)
    }

    suspend fun translate(title: String, source: AttentionArticleSource): AttentionChineseArticle = withTimeout(90_000L) {
        translation(source.article.content).run(title, source.document)
    }

    private suspend fun translation(body: String): AttentionArticleTranslation {
        val bodyLanguage = TranslateLanguage.fromLanguageTag(identifier.identifyLanguage(body.take(4000)).await())
        return AttentionArticleTranslation { text ->
            withTimeout(15_000L) piece@{
                // A short author/model name cannot reliably identify its language. Keep the article context.
                val language = (if (text.length < 160) bodyLanguage else
                    TranslateLanguage.fromLanguageTag(identifier.identifyLanguage(text).await()) ?: bodyLanguage)
                    ?: error("article_language_unknown")
                if (language == TranslateLanguage.CHINESE) return@piece text
                val client = clients[language] ?: run {
                    for (code in setOf(language, TranslateLanguage.CHINESE) - TranslateLanguage.ENGLISH) {
                        if (!RemoteModelManager.getInstance().isModelDownloaded(TranslateRemoteModel.Builder(code).build()).await()) {
                            AttentionMlKitTranslator.requestDownload(context, language)
                            error("article_translation_model_pending")
                        }
                    }
                    Translation.getClient(TranslatorOptions.Builder().setSourceLanguage(language)
                        .setTargetLanguage(TranslateLanguage.CHINESE).build()).also { clients[language] = it }
                }
                client.translate(text).await()
            }
        }
    }

    override fun close() {
        clients.values.forEach(Translator::close)
        clients.clear()
        identifier.close()
    }
}
