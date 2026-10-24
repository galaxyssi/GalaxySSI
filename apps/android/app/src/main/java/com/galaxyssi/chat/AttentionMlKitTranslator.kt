package com.galaxyssi.chat

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

internal class AttentionMlKitTranslator : AttentionTitleTranslator {
    private var client: Translator? = null

    override suspend fun isReady(): Boolean = RemoteModelManager.getInstance().isModelDownloaded(model()).await()

    override suspend fun translate(title: String): String {
        val translator = client ?: Translation.getClient(TranslatorOptions.Builder()
            .setSourceLanguage(TranslateLanguage.ENGLISH).setTargetLanguage(TranslateLanguage.CHINESE).build())
            .also { client = it }
        return translator.translate(title).await()
    }

    override fun close() { client?.close(); client = null }

    companion object {
        const val PROVIDER = "google-mlkit-on-device"
        fun model(): TranslateRemoteModel = TranslateRemoteModel.Builder(TranslateLanguage.CHINESE).build()

        fun requestDownload(context: Context, source: String = TranslateLanguage.ENGLISH) {
            val request = OneTimeWorkRequestBuilder<AttentionTranslationModelWorker>()
                .setInputData(workDataOf("source_language" to source))
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.UNMETERED).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniqueWork("attention-translation-model-$source-zh-v1", ExistingWorkPolicy.KEEP, request)
        }
    }
}

/** Model downloads are independent of headline processing, so an unreachable download cannot block fallback. */
class AttentionTranslationModelWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val preferences = ProactiveAttentionStore(applicationContext).preferences()
        if (!preferences.configured || !preferences.enabled) return Result.success()
        return try {
            val source = inputData.getString("source_language") ?: TranslateLanguage.ENGLISH
            for (code in setOf(source, TranslateLanguage.CHINESE) - TranslateLanguage.ENGLISH) {
                RemoteModelManager.getInstance().download(TranslateRemoteModel.Builder(code).build(),
                    DownloadConditions.Builder().requireWifi().build()).await()
            }
            android.util.Log.i("GalaxySSIAttention", "title_translation_model_ready provider=mlkit")
            // The timer survives an inference worker that is still finishing its current batch.
            ProactiveAttentionTitleScheduler.request(applicationContext, 1_000L)
            AttentionArticleScheduler.request(applicationContext, 1_000L)
            Result.success()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            android.util.Log.w("GalaxySSIAttention", "title_translation_model_retry type=${failure.javaClass.simpleName}")
            Result.retry()
        }
    }
}
