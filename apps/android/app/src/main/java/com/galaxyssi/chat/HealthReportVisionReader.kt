package com.galaxyssi.chat

import android.content.Context
import java.time.ZoneId
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

internal class HealthReportVisionChanged : IllegalStateException()

internal data class HealthReportVisionInput(val job: HealthImportJob, val source: HealthOriginal, val privacy: HealthPrivacyPolicy)
internal enum class HealthReportImportStage { COMPRESSING, SENDING, SAVING }

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

    suspend fun read(input: HealthReportVisionInput, target: HealthReportVisionTarget, holdForBatch: Boolean = false,
        progress: (HealthReportImportStage, Int) -> Unit = { _, _ -> }): HealthReportImportOutcome {
        val task = currentCoroutineContext()
        return HealthPrivacyStore(context, names.privacy).use { privacy ->
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
                    progress(HealthReportImportStage.COMPRESSING, 0)
                    val jpeg = HealthReportVisionProvider.jpeg(store, input.source, task::ensureActive)
                    try {
                        checkCurrent()
                        progress(HealthReportImportStage.SENDING, jpeg.size)
                        val response = gateway.read(context, target, jpeg, ::checkCurrent)
                        checkCurrent()
                        HealthReportVisionResult.parse(response) to jpeg.size
                    } finally { jpeg.fill(0) }
                }
            }
            privacy.withCurrentPolicy(input.privacy) {
                task.ensureActive()
                val (report, bytes) = result
                progress(HealthReportImportStage.SAVING, bytes)
                HealthRecordStore(context, names.records).use { records ->
                    HealthOriginalStore(context, names.originals, names.originalRoot(context),
                        records.takeIf { names.fixture == null }).use { store ->
                        val outcome = checkNotNull(store.saveReportVision(input.job, input.source, report) {
                            saveOrStage(records, input.job, input.source, report, bytes, holdForBatch, task::ensureActive)
                        })
                        records.publishCommittedChanges()
                        releaseIfComplete(store, input.job.id, outcome)
                        outcome
                    }
                }
            }
        }
    }

    suspend fun complete(ids: List<String>, supplement: HealthReportSupplement): List<HealthReportImportOutcome> {
        currentCoroutineContext().ensureActive()
        // Once the user confirms, finish the local transaction even if the Activity leaves the foreground.
        return withContext(NonCancellable) {
            val zone = ZoneId.systemDefault()
            val now = System.currentTimeMillis()
            HealthRecordStore(context, names.records).use { records ->
                HealthOriginalStore(context, names.originals, names.originalRoot(context), records.takeIf { names.fixture == null }).use { store ->
                    val outcomes = store.completeReportVision(ids) { pages ->
                        val prepared = pages.map { (job, source, page) ->
                            val report = requireNotNull(page.vision)
                            val scope = report.supplementScope(job, source, page.visionImport, zone, now)
                            val drafts = report.drafts(job, source, zone, now, supplement)
                            if (scope.needsTime && drafts.any { it.measuredAt == 0L })
                                throw HealthReportTimeInvalid()
                            drafts to (page.visionImport to report.partial)
                        }
                        prepared.map { (drafts, info) ->
                            val (receipt, partial) = info
                            if (receipt != null && (receipt.contextConfirmed || !receipt.pendingConfirmation && receipt.skipped == 0)) receipt
                            else records.saveVisionReport(drafts, partial, receipt?.imageBytes ?: 0, replaceNearby = true) {}.let { saved ->
                                if (receipt == null || receipt.pendingConfirmation) saved.copy(contextConfirmed = true)
                                else if (saved.saved == 0) receipt.copy(contextConfirmed = true)
                                else saved.copy(saved = saved.saved + receipt.saved,
                                    duplicates = (saved.duplicates - receipt.saved).coerceAtLeast(0), contextConfirmed = true)
                            }
                        }
                    }
                    records.publishCommittedChanges()
                    ids.distinct().zip(outcomes).forEach { (id, result) -> releaseIfComplete(store, id, result) }
                    outcomes
                }
            }
        }
    }

    suspend fun finishLegacy(id: String): HealthReportImportOutcome {
        val task = currentCoroutineContext()
        return HealthRecordStore(context, names.records).use { records ->
            HealthOriginalStore(context, names.originals, names.originalRoot(context),
                records.takeIf { names.fixture == null }).use { store ->
                val outcome = store.finishLegacyReportVision(id) { job, source, report ->
                    saveOrStage(records, job, source, report, 0, false, task::ensureActive)
                }
                records.publishCommittedChanges()
                releaseIfComplete(store, id, outcome)
                outcome
            }
        }
    }

    private fun saveOrStage(records: HealthRecordStore, job: HealthImportJob, source: HealthOriginal,
        report: HealthReportVisionResult, bytes: Int, holdForBatch: Boolean, checkActive: () -> Unit): HealthReportImportOutcome {
        val zone = ZoneId.systemDefault()
        val now = System.currentTimeMillis()
        checkActive()
        return if (holdForBatch || report.supplementScope(job, source, null, zone, now).needed)
            HealthReportImportOutcome(0, 0, 0, report.partial, bytes, emptyList(), pendingConfirmation = true)
        else records.saveVisionReport(report.drafts(job, source, zone, now),
            report.partial, bytes, replaceNearby = true, checkActive = checkActive)
    }

    private fun releaseIfComplete(store: HealthOriginalStore, id: String, outcome: HealthReportImportOutcome) {
        if (!outcome.pendingConfirmation && outcome.skipped == 0 && !outcome.partial) runCatching { store.releaseReviewOriginal(id) }
    }

    companion object {
        fun eligible(job: HealthImportJob) = !job.originalOnly && !job.modelRecognized && job.originalId.isNotBlank() && job.mime.startsWith("image/") &&
            job.mode == "report" && job.state in setOf(HealthImportState.REVIEW, HealthImportState.FAILED)
    }
}
