package com.galaxyssi.chat

import android.content.Context
import android.net.Uri
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.security.DigestInputStream
import java.security.MessageDigest

internal object HealthTableScheduler {
    private fun active(batch: HealthTableBatch) = batch.state in listOf(HealthTableState.VALIDATING, HealthTableState.SAVING, HealthTableState.UNDOING) ||
        batch.state == HealthTableState.READING && batch.format == "xlsx" && batch.sheetIndex >= 0
    fun enqueue(context: Context, id: String, retry: Boolean = false, names: HealthOverviewDatabases = HealthOverviewDatabases()) {
        val batch = HealthTableStore(context, names.records).use { it.batch(id) } ?: return
        if (batch.error.isNotBlank() && !retry) return
        if (!active(batch)) return
        val request = OneTimeWorkRequestBuilder<HealthTableWorker>().setInputData(workDataOf("health_table" to id,
            "phase" to batch.state.name, "mapping_revision" to batch.mappingRevision, "fixture" to names.fixture)).build()
        // The next phase may be submitted before the previous worker's success is persisted by WorkManager.
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(workName(names, id, batch.state, batch.mappingRevision),
            if (retry) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, request)
    }
    fun recover(context: Context) {
        if (!context.getDatabasePath("health_records_v1.db").exists()) return
        HealthTableStore(context).use { store ->
            var after = ""
            do {
                val ids = store.active(after); ids.forEach { runCatching { enqueue(context, it) } }
                after = ids.lastOrNull().orEmpty()
            } while (ids.size == 100)
        }
    }
    fun notify(context: Context, names: HealthOverviewDatabases = HealthOverviewDatabases()) {
        context.contentResolver.notifyChange(changes(context, names), null)
    }
    fun changes(context: Context, names: HealthOverviewDatabases = HealthOverviewDatabases()): Uri =
        Uri.parse("content://${context.packageName}.health-originals/changes/tables").let { uri ->
            names.fixture?.let { uri.buildUpon().appendPath(it).build() } ?: uri
        }
    fun workName(names: HealthOverviewDatabases, id: String, phase: HealthTableState, revision: Int) =
        (names.fixture?.let { "health-table-test:$it" } ?: "health-table") + ":$id:$phase:$revision"
    fun cancelReading(context: Context, id: String, revision: Int, names: HealthOverviewDatabases = HealthOverviewDatabases()) {
        WorkManager.getInstance(context.applicationContext).cancelUniqueWork(workName(names, id, HealthTableState.READING, revision))
    }
}

class HealthTableWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val id = inputData.getString("health_table") ?: return Result.failure()
        val phase = runCatching { HealthTableState.valueOf(inputData.getString("phase").orEmpty()) }.getOrNull() ?: return Result.failure()
        val revision = inputData.getInt("mapping_revision", -1)
        val fixture = inputData.getString("fixture")
        if (fixture != null && (!BuildConfig.DEBUG || !HealthProfilePolicy.uuid(fixture))) return Result.failure()
        val names = HealthOverviewDatabases(fixture)
        fun openOriginals() = HealthOriginalStore(applicationContext, names.originals, names.originalRoot(applicationContext))
        fun notifyProgress() = HealthTableScheduler.notify(applicationContext, names)
        return HealthTableStore(applicationContext, names.records).use { store ->
            try {
                if (phase == HealthTableState.READING) {
                    val batch = store.batch(id) ?: return@use Result.failure()
                    if (batch.state != phase || batch.mappingRevision != revision || batch.format != "xlsx" || batch.sheetIndex < 0) return@use Result.success()
                    openOriginals().use { originals ->
                        val original = originals.original(batch.originalId) ?: throw HealthImportFailure("original_missing")
                        HealthXlsxImport.stage(originals, original, batch, store, progress = ::notifyProgress) {
                            if (isStopped) throw java.util.concurrent.CancellationException()
                        }
                    }
                    notifyProgress(); return@use Result.success()
                }
                while (!isStopped) {
                    val more = store.step(id, phase, revision); notifyProgress()
                    if (!more) {
                        if (phase == HealthTableState.SAVING && store.batch(id)?.state == HealthTableState.SAVED) {
                            runCatching { openOriginals().use { it.releaseReviewOriginal(id) } }
                        }
                        if (fixture == null && phase in listOf(HealthTableState.SAVING, HealthTableState.UNDOING)) {
                            HealthOriginalStore.notifyReportReviews(applicationContext)
                            HealthReminderWork.sourceRemindersChanged(applicationContext)
                        }
                        return@use Result.success()
                    }
                }
                Result.retry()
            } catch (_: java.util.concurrent.CancellationException) { Result.retry() }
            catch (_: OutOfMemoryError) {
                runCatching { store.fail(id, "memory_pressure", phase, revision) }; notifyProgress(); Result.failure()
            } catch (failure: Exception) {
                runCatching { store.fail(id, if (failure is HealthImportFailure) failure.code else "storage", phase, revision) }; notifyProgress()
                // Do not retry storage failures in a hot loop; persisted state can be resumed explicitly.
                Result.failure()
            }
        }
    }
}

internal object HealthTableImport {
    fun stage(store: HealthOriginalStore, original: HealthOriginal, id: String, records: HealthTableStore,
              cancelled: () -> Unit = {}): HealthTableBatch {
        val format = HealthTableParser.format(original.name, original.mime) ?: throw HealthImportFailure("table_format")
        if (original.size > HealthTableParser.MAX_BYTES) throw HealthImportFailure("table_size")
        val batch = records.begin(id, original, format)
        if (batch.state != HealthTableState.READING) return batch
        if (format == "xlsx") {
            val (sheets, epoch) = HealthXlsxReader.inspect(store, original, cancelled)
            cancelled(); records.workbook(id, sheets, epoch)
            return requireNotNull(records.batch(id))
        }
        val digest = MessageDigest.getInstance("SHA-256")
        val pending = ArrayList<HealthTableRow>(30)
        val headers = DigestInputStream(store.input(original), digest).use { input ->
            HealthTableParser.read(input, format) { row ->
                cancelled()
                if (row.number > batch.rows) {
                    pending += row
                    if (pending.size == 30) { records.append(id, pending); pending.clear() }
                }
            }
        }
        cancelled()
        if (digest.digest().joinToString("") { "%02x".format(it) } != original.sha256) throw HealthImportFailure("table_integrity")
        if (pending.isNotEmpty()) records.append(id, pending)
        records.finishReading(id, headers)
        return requireNotNull(records.batch(id))
    }
}

internal object HealthXlsxImport {
    fun stage(originals: HealthOriginalStore, original: HealthOriginal, batch: HealthTableBatch, records: HealthTableStore,
              progress: () -> Unit = {}, cancelled: () -> Unit = {}) {
        check(batch.format == "xlsx" && batch.sheetIndex >= 0 && batch.state == HealthTableState.READING)
        val pending = arrayListOf<HealthTableRow>()
        val headers = HealthXlsxReader.rows(originals, original, batch, cancelled) { row ->
            cancelled()
            if (row.number > batch.rows) {
                pending += row
                if (pending.size == 30) { records.append(batch.id, pending, batch.mappingRevision); pending.clear(); progress() }
            }
        }
        cancelled()
        if (pending.isNotEmpty()) records.append(batch.id, pending, batch.mappingRevision)
        records.finishReading(batch.id, headers, batch.mappingRevision)
    }
}
