package com.galaxyssi.chat

import android.content.Context
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.system.Os
import android.system.OsConstants
import java.io.Closeable
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

internal data class HealthRestoreOriginalPlan(val input: HealthBackupOriginal, val state: HealthRestoreOriginalState,
    val targetId: String, val prepared: HealthRestorePreparedOriginal?)
internal enum class HealthRestoreCommitPoint { BEFORE_COMMIT, AFTER_COMMIT }

internal class HealthRestorePlan internal constructor(
    val id: String, val manifest: HealthBackupManifest, val owner: String, val counts: HealthRestoreCounts,
    internal val versions: Map<HealthMetric, String>, internal val originals: List<HealthRestoreOriginalPlan>,
    internal val stage: HealthRestoreStage, internal val repository: HealthRestoreRepository,
    private val lease: HealthRestoreLeases.Lease
) : Closeable {
    internal var closed = false
        private set
    @Synchronized fun conflicts(after: String = ""): HealthRestoreConflictPage { check(!closed); return stage.conflicts(after) }
    @Synchronized fun commit(signal: CancellationSignal, replacements: Set<String> = emptySet(),
        checkpoint: ((HealthRestoreCommitPoint) -> Unit)? = null): HealthRestoreReceipt {
        check(!closed)
        return repository.commit(this, signal, replacements, checkpoint)
    }
    @Synchronized override fun close() {
        if (closed) return
        closed = true
        try { stage.close() } finally { repository.dispose(id, lease) }
    }
}

internal class HealthRestoreRepository(private val context: Context, private val names: HealthOverviewDatabases = HealthOverviewDatabases(),
    private val profileName: () -> String = {
        HealthProfileStore(context).use { it.snapshot().cells[HealthProfileField.NAME]?.value?.text.orEmpty() }
    }) {
    private val metrics = HealthMetric.entries.toSet()
    private val stageRoot = File(context.cacheDir, if (names.fixture == null) "health-restore-stage" else "health-restore-stage-${names.fixture}")
    private val originalRoot = File(names.originalRoot(context), "restore")
    private val leases = HealthRestoreLeases(File(names.originalRoot(context), "restore-pending"))

    private fun owner() = profileName().trim()

    fun prepare(open: () -> InputStream, password: CharArray, signal: CancellationSignal): HealthRestorePlan {
        val id = UUID.randomUUID().toString()
        val stageFolder = child(stageRoot, id)
        val originalFolder = child(originalRoot, id)
        val lease = checkNotNull(leases.tryAcquire(id))
        var stage: HealthRestoreStage? = null
        try {
            check(stageFolder.mkdirs() && originalFolder.mkdirs())
            val spool = HealthRestoreStage(File(stageFolder, "items.db"), id).also { stage = it }
            return storage { records, originals ->
                val targetOwner = owner()
                val expected = records.metricVersions(metrics)
                val originalPlans = linkedMapOf<String, HealthRestoreOriginalPlan>()
                val digests = hashSetOf<String>()
                val targetIds = hashSetOf<String>()
                var added = 0L; var duplicates = 0L; var conflicts = 0L
                var originalsAdded = 0; var originalsReused = 0; var repaired = 0; var missing = 0
                var sourcesAdded = 0L; var sourcesReused = 0L; var sourcesSkipped = 0L
                fun prepareOriginal(item: HealthBackupOriginal): OutputStream? {
                    if (!digests.add(item.sha256)) throw HealthBackupException(HealthBackupIssue.DAMAGED)
                    val match = originals.restorationState(item)
                    val target = match.duplicate?.id ?: if (match.sameId == null && item.id !in targetIds) item.id
                        else generateSequence { UUID.randomUUID().toString() }.first { it !in targetIds && originals.original(it) == null }
                    check(targetIds.add(target))
                    if (match.available) {
                        try { originals.copyVerified(requireNotNull(match.duplicate), discardBytes, signal::throwIfCanceled) }
                        catch (failure: OperationCanceledException) { throw failure }
                        catch (_: Exception) { throw HealthRestoreOriginalUnavailable() }
                    }
                    val (prepared, sink) = if (match.duplicate == null || (item.present && !match.available))
                        originals.prepareRestoredOriginal(id, item, target, match.duplicate) else null to null
                    if (match.duplicate == null) originalsAdded++ else if (prepared != null) repaired++ else originalsReused++
                    if (!item.present && !match.available) missing++
                    originalPlans[item.id] = HealthRestoreOriginalPlan(item, match, target, prepared)
                    return sink
                }
                val manifest = spool.fill {
                    var sourceTarget: HealthObservation? = null
                    var sourceConflictId: String? = null
                    val verified = open().use { stream ->
                        HealthBackupCodec.verify(stream, password, signal::throwIfCanceled,
                            onManifest = {
                                if (it.owner.isNotBlank() && targetOwner.isNotBlank() && !it.owner.trim().equals(targetOwner, ignoreCase = true))
                                    throw HealthRestoreOwnerMismatch()
                            }, onOriginal = ::prepareOriginal, onMissingOriginal = { check(prepareOriginal(it) == null) },
                            onRecord = { incoming ->
                                val evidence = incoming.draft.evidence?.let { ref ->
                                    ref.copy(originalId = requireNotNull(originalPlans[ref.originalId]).targetId)
                                }
                                val row = incoming.copy(draft = incoming.draft.copy(evidence = evidence))
                                val dedupe = if (row.source in setOf("bluetooth", "health_connect")) null else records.restoreDedupeKey(row)
                                val evidenceKey = records.restoreEvidenceKey(row)
                                val stored = records.restoreMatch(row)
                                val match = if (stored.kind == HealthRestoreKind.NEW) {
                                    spool.colliding(dedupe, evidenceKey)?.let {
                                        HealthRestoreMatch(if (it.draft == row.draft && it.source == row.source)
                                            HealthRestoreKind.DUPLICATE else HealthRestoreKind.CONFLICT, it)
                                    } ?: stored
                                } else stored
                                when (match.kind) {
                                    HealthRestoreKind.NEW -> added++
                                    HealthRestoreKind.DUPLICATE -> duplicates++
                                    HealthRestoreKind.CONFLICT -> conflicts++
                                }
                                val replaceable = match.kind == HealthRestoreKind.CONFLICT && !match.deleted &&
                                    match.existing?.let { records.canReplaceRestored(row, it) } == true
                                spool.add(row, match, dedupe, evidenceKey, replaceable)
                                sourceConflictId = row.id.takeIf { replaceable }
                                sourceTarget = when (match.kind) {
                                    HealthRestoreKind.NEW -> row
                                    HealthRestoreKind.DUPLICATE -> requireNotNull(match.existing)
                                    HealthRestoreKind.CONFLICT -> if (replaceable) row.copy(revision = requireNotNull(match.existing).revision + 1) else null
                                }
                            }, onSourceLink = { _, evidence ->
                                val target = sourceTarget
                                if (target == null || sourceConflictId != null) sourcesSkipped++
                                if (target != null) spool.stageSource(HealthRestoreSourceLink(target.id, target.revision, target.draft.metric,
                                    evidence.copy(originalId = requireNotNull(originalPlans[evidence.originalId]).targetId)), sourceConflictId)
                            })
                    }
                    for ((seq, link) in spool.sourceLinks()) {
                        signal.throwIfCanceled()
                        val primary = spool.colliding(null, records.restorePrimarySourceKey(link))
                        val match = if (primary != null) {
                            if (primary.id == link.recordId && primary.revision == link.revision) HealthRestoreKind.DUPLICATE
                            else HealthRestoreKind.CONFLICT
                        } else records.restoreSourceMatch(link)
                        when (if (match == HealthRestoreKind.NEW) spool.planSource(seq, records.restoreSourceSlot(link), link) else match) {
                            HealthRestoreKind.NEW -> sourcesAdded++
                            HealthRestoreKind.DUPLICATE -> sourcesReused++
                            HealthRestoreKind.CONFLICT -> sourcesSkipped++
                        }
                    }
                    verified
                }
                signal.throwIfCanceled()
                if (records.metricVersions(metrics) != expected || owner() != targetOwner) throw HealthRestoreChanged()
                val counts = HealthRestoreCounts(added, duplicates, conflicts, originalsAdded, originalsReused, repaired, missing,
                    sourcesAdded, sourcesReused, sourcesSkipped)
                check(added + duplicates + conflicts == manifest.records)
                check(sourcesAdded + sourcesReused + sourcesSkipped == manifest.secondary)
                HealthRestorePlan(id, manifest, targetOwner, counts, expected, originalPlans.values.toList(), spool, this, lease)
            }
        } catch (failure: Throwable) {
            runCatching { stage?.close() }.exceptionOrNull()?.let(failure::addSuppressed)
            runCatching { dispose(id, lease) }.exceptionOrNull()?.let(failure::addSuppressed)
            throw failure
        }
    }

    internal fun commit(plan: HealthRestorePlan, signal: CancellationSignal, replacements: Set<String>,
        checkpoint: ((HealthRestoreCommitPoint) -> Unit)?): HealthRestoreReceipt = storage { records, originals ->
        signal.throwIfCanceled()
        if (owner() != plan.owner) throw HealthRestoreChanged()
        val directory = child(originalRoot, plan.id)
        syncDirectory(directory)
        syncDirectory(originalRoot)
        syncDirectory(requireNotNull(originalRoot.parentFile))
        syncDirectory(requireNotNull(originalRoot.parentFile?.parentFile))
        val db = records.tableDatabase
        db.beginTransactionNonExclusive()
        val receipt: HealthRestoreReceipt
        try {
            check(!HealthRestoreReceipts.committed(db, plan.id))
            if (records.metricVersions(metrics) != plan.versions) throw HealthRestoreChanged()
            val selected = replacements.sorted()
            if (selected.size.toLong() > plan.counts.conflicts) throw HealthRestoreChanged()
            for (id in selected) {
                signal.throwIfCanceled()
                val row = plan.stage.conflict(id)?.takeIf { it.replaceable } ?: throw HealthRestoreChanged()
                records.replaceRestored(row)
            }
            for (file in plan.originals) {
                signal.throwIfCanceled()
                if (originals.restorationState(file.input) != file.state ||
                    (file.state.duplicate == null && originals.original(file.targetId) != null))
                    throw HealthRestoreChanged()
            }
            for (file in plan.originals) {
                signal.throwIfCanceled()
                file.prepared?.let { originals.publishRestoredOriginal(it, file.state.duplicate) }
            }
            var inserted = 0L
            for (row in plan.stage.newRecords()) {
                signal.throwIfCanceled()
                records.insertRestored(row)
                inserted++
            }
            check(inserted == plan.counts.added)
            var linked = 0L
            for ((_, link) in plan.stage.sourceLinks(planned = true)) {
                signal.throwIfCanceled()
                records.insertRestoredSource(link)
                linked++
            }
            check(linked == plan.counts.sourcesAdded)
            var reused = plan.counts.sourcesReused
            var skipped = plan.counts.sourcesSkipped
            for (id in selected) {
                for ((_, link) in plan.stage.sourceLinks(conflictId = id)) {
                    signal.throwIfCanceled()
                    when (records.restoreSourceMatch(link)) {
                        HealthRestoreKind.NEW -> { records.insertRestoredSource(link); linked++; skipped-- }
                        HealthRestoreKind.DUPLICATE -> { reused++; skipped-- }
                        HealthRestoreKind.CONFLICT -> Unit
                    }
                }
            }
            check(skipped >= 0 && linked + reused + skipped == plan.manifest.secondary)
            if (owner() != plan.owner) throw HealthRestoreChanged()
            signal.throwIfCanceled()
            receipt = HealthRestoreReceipt(plan.id, plan.manifest.id, System.currentTimeMillis(),
                plan.counts.copy(conflicts = plan.counts.conflicts - selected.size, replaced = selected.size.toLong(),
                    sourcesAdded = linked, sourcesReused = reused, sourcesSkipped = skipped), plan.manifest.first, plan.manifest.last)
            HealthRestoreReceipts.insert(db, receipt)
            checkpoint?.invoke(HealthRestoreCommitPoint.BEFORE_COMMIT)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
            records.publishCommittedChanges()
        }
        checkpoint?.invoke(HealthRestoreCommitPoint.AFTER_COMMIT)
        originals.notifyRestored()
        receipt
    }

    fun recent() = HealthRecordStore(context, names.records).use { HealthRestoreReceipts.recent(it.tableDatabase) }

    fun recoverAbandoned() {
        fun recover(id: String) { runCatching { leases.tryAcquire(id)?.let { dispose(id, it) } } }
        val pending = (stageRoot.list().orEmpty().filter(HealthProfilePolicy::uuid) + leases.pending()).toSet()
        pending.forEach(::recover)
        val legacy = originalRoot.list().orEmpty().filter { it !in pending && HealthProfilePolicy.uuid(it) }
        if (legacy.isEmpty()) return
        // Older builds did not leave markers. Do not create a lease for every retained batch.
        HealthRecordStore(context, names.records).use { records ->
            for (id in legacy) runCatching {
                val files = child(originalRoot, id).list()
                if (!HealthRestoreReceipts.committed(records.tableDatabase, id) || files?.isEmpty() == true) recover(id)
            }
        }
    }

    internal fun dispose(id: String, lease: HealthRestoreLeases.Lease) {
        var clean = false
        try { clean = removeStaging(id) } finally { leases.release(lease, clean) }
    }

    private fun removeStaging(id: String): Boolean {
        val stageCleared = runCatching { child(stageRoot, id).deleteRecursively() }.getOrDefault(false)
        val folder = child(originalRoot, id)
        if (!folder.exists()) return stageCleared
        val committed = runCatching { HealthRecordStore(context, names.records).use { HealthRestoreReceipts.committed(it.tableDatabase, id) } }
        val originalSettled = when (committed.getOrNull()) {
            false -> runCatching { folder.deleteRecursively() }.getOrDefault(false)
            true -> folder.list()?.let { it.isNotEmpty() || folder.delete() } == true
            null -> false
        }
        return stageCleared && originalSettled
    }

    private fun <T> storage(block: (HealthRecordStore, HealthOriginalStore) -> T): T =
        HealthRecordStore(context, names.records).use { records ->
            HealthOriginalStore(context, names.originals, names.originalRoot(context), records).use { originals ->
                check(originals.libraryDatabase === records.tableDatabase)
                block(records, originals)
            }
        }

    private fun child(parent: File, id: String): File {
        require(HealthProfilePolicy.uuid(id))
        return File(parent, id).canonicalFile.also { check(it.parentFile == parent.canonicalFile) }
    }

    private fun syncDirectory(file: File) {
        check(file.isDirectory)
        val handle = Os.open(file.path, OsConstants.O_RDONLY, 0)
        try { Os.fsync(handle) } finally { Os.close(handle) }
    }

    companion object {
        private val discardBytes = object : OutputStream() {
            override fun write(value: Int) = Unit
            override fun write(bytes: ByteArray, offset: Int, length: Int) = Unit
        }
    }
}
