package com.galaxyssi.chat

import android.content.Context
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

internal class HealthReportVisionChanged : IllegalStateException()

internal data class HealthReportVisionInput(val job: HealthImportJob, val source: HealthOriginal, val privacy: HealthPrivacyPolicy)

internal class HealthReportVisionReader(private val context: Context, private val names: HealthOverviewDatabases,
    private val gateway: HealthReportVisionGateway = HealthReportVisionProvider) {
    private fun originals() = HealthOriginalStore(context, names.originals, names.originalRoot(context))

    fun prepare(id: String): HealthReportVisionInput {
        val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        if (!privacy.online || !privacy.metrics) throw HealthAccessBlocked()
        return originals().use { store ->
            val job = store.job(id)?.takeIf(::eligible) ?: throw HealthReportVisionChanged()
            val source = store.original(job.originalId)?.takeIf { it.mime.startsWith("image/") && store.present(it) }
                ?: throw HealthReportVisionChanged()
            if (store.page(id, 1)?.vision != null) throw HealthReportVisionChanged()
            HealthReportVisionInput(job, source, privacy)
        }
    }
    fun target() = gateway.target(context)

    suspend fun read(input: HealthReportVisionInput, target: HealthReportVisionTarget) {
        val task = currentCoroutineContext()
        HealthPrivacyStore(context, names.privacy).use { privacy ->
            val scope = HealthAccessScope(HealthAccessPurpose.HEALTH_REPORT_VISION, count = 1, source = HealthAccessSource.ORIGINAL,
                destination = target.destination)
            val result = privacy.trackOnlineAnalysis(scope, input.privacy.version) {
                originals().use { store ->
                    fun checkCurrent() {
                        task.ensureActive()
                        if (privacy.policy() != input.privacy || !input.privacy.online || !input.privacy.metrics)
                            throw HealthAccessBlocked()
                        if (store.job(input.job.id) != input.job || store.original(input.source.id) != input.source ||
                            !store.present(input.source) || store.page(input.job.id, 1)?.vision != null) throw HealthReportVisionChanged()
                    }
                    checkCurrent()
                    val jpeg = HealthReportVisionProvider.jpeg(store, input.source)
                    try {
                        checkCurrent()
                        val response = gateway.read(context, target, jpeg, ::checkCurrent)
                        checkCurrent()
                        HealthReportVisionResult.parse(response)
                    } finally { jpeg.fill(0) }
                }
            }
            privacy.withCurrentPolicy(input.privacy) {
                task.ensureActive()
                originals().use { it.saveReportVision(input.job, input.source, result) }
            }
        }
    }

    companion object {
        fun eligible(job: HealthImportJob) = !job.originalOnly && !job.modelRecognized && job.originalId.isNotBlank() && job.mime.startsWith("image/") &&
            job.mode == "report" && job.state in setOf(HealthImportState.REVIEW, HealthImportState.FAILED)
    }
}
