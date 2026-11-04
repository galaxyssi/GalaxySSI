package com.galaxyssi.chat

import android.content.Context
import android.os.CancellationSignal
import com.galaxyssi.chat.HealthBackupCodec.toHex
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.nio.file.Files
import java.security.DigestOutputStream
import java.security.MessageDigest
import java.util.UUID

internal data class HealthBackupPreview(
    val manifest: HealthBackupManifest, val photos: Int, val estimate: Long, val examples: List<HealthBackupOriginal>,
    val originalStamp: String, val versions: Map<HealthMetric, String>
)

internal data class HealthBackupArtifact(val id: String, val size: Long, val hash: String, val missing: Int)

internal class HealthBackupRepository(private val context: Context, private val databases: HealthOverviewDatabases = HealthOverviewDatabases()) {
    private val directory = File(context.cacheDir, if (databases.fixture == null) "health-backups" else "health-backup-test-${databases.fixture}")
    private val metrics = HealthMetric.entries.toSet()

    fun preview(owner: String, signal: CancellationSignal): HealthBackupPreview = records { records, originals ->
        val versions = records.metricVersions(metrics)
        val sources = backupSources(records, originals, signal)
        val examples = ArrayList<HealthBackupOriginal>()
        var photos = 0
        var missing = 0
        var originalBytes = 0L
        sources.items.forEach { item ->
            if (examples.size < 30) examples += item
            if (item.source == "camera") photos++
            if (item.present) originalBytes = Math.addExact(originalBytes, item.bytes) else missing++
        }
        var count = 0L
        var linked = 0L
        var first = Long.MAX_VALUE
        var last = 0L
        var recordBytes = 0L
        records(records, signal).map(sources::project).forEach { record ->
            if (record.draft.evidence != null) linked++
            val encoded = record.json().toString().toByteArray(Charsets.UTF_8)
            try { recordBytes = Math.addExact(recordBytes, encoded.size.toLong() + 4L) } finally { encoded.fill(0) }
            first = minOf(first, record.draft.measuredAt)
            last = maxOf(last, record.draft.measuredAt)
            count++
        }
        val originalStamp = sources.stamp
        val manifest = HealthBackupManifest(UUID.randomUUID().toString(), System.currentTimeMillis(), owner,
            count, sources.items.size, missing, linked, originalBytes, if (count == 0L) 0L else first, last)
        val estimate = Math.addExact(originalBytes, recordBytes) + sources.items.size * 1200L + 4096L +
            (originalBytes + recordBytes) / 2048L
        ensureCurrent(records, originals, versions, originalStamp, signal)
        HealthBackupPreview(manifest, photos, estimate, examples, originalStamp, versions)
    }

    fun generate(preview: HealthBackupPreview, password: CharArray, signal: CancellationSignal): HealthBackupArtifact = records { records, originals ->
        val manifest = preview.manifest
        val partial = path(manifest.id, partial = true)
        val destination = path(manifest.id)
        require(!destination.exists() && !partial.exists())
        check(directory.isDirectory || directory.mkdirs())
        val sources = ensureCurrent(records, originals, preview.versions, preview.originalStamp, signal)
        val digest = MessageDigest.getInstance("SHA-256")
        try {
            FileOutputStream(partial).use { raw ->
                DigestOutputStream(raw, digest).let { output ->
                    HealthBackupCodec.write(output, password, manifest,
                        sources.items.asSequence(),
                        { item, sink ->
                            val original = originals.original(item.id) ?: changed()
                            if (original.reviewOnly || manifestItem(original, originals) != item) changed()
                            originals.copyVerified(original, sink, signal::throwIfCanceled)
                        }, records(records, signal).map(sources::project), signal::throwIfCanceled)
                }
                raw.fd.sync()
            }
            ensureCurrent(records, originals, preview.versions, preview.originalStamp, signal)
            val bytes = partial.length()
            check(bytes > 0)
            Files.move(partial.toPath(), destination.toPath())
            HealthBackupArtifact(manifest.id, bytes, digest.digest().toHex(), manifest.missing)
        } finally { partial.delete() }
    }

    fun file(artifact: HealthBackupArtifact): File = path(artifact.id).also {
        check(it.isFile && it.length() == artifact.size && artifact.size > 0)
    }

    fun save(artifact: HealthBackupArtifact, output: OutputStream, signal: CancellationSignal): Long =
        HealthPrivateExportFile.copyVerified(file(artifact).inputStream(), output,
            HealthExportDigest(artifact.size, artifact.hash), signal::throwIfCanceled)

    fun forget(artifact: HealthBackupArtifact) { path(artifact.id).delete() }

    fun cleanup(now: Long = System.currentTimeMillis()) {
        directory.listFiles().orEmpty().filter { it.isFile && (it.extension == "partial" || it.extension == HealthBackupCodec.EXTENSION) &&
            it.lastModified() < now - 7 * 86_400_000L }.forEach { it.delete() }
    }

    private fun path(id: String, partial: Boolean = false): File {
        require(HealthProfilePolicy.uuid(id))
        val root = directory.canonicalFile
        val extension = if (partial) "partial" else HealthBackupCodec.EXTENSION
        return File(root, "GalaxySSI-Health-$id.$extension").canonicalFile.also { check(it.parentFile == root) }
    }

    private fun <T> records(block: (HealthRecordStore, HealthOriginalStore) -> T): T =
        HealthRecordStore(context, databases.records).use { rows ->
            HealthOriginalStore(context, databases.originals, databases.originalRoot(context)).use { block(rows, it) }
        }

    private fun records(store: HealthRecordStore, signal: CancellationSignal) = sequence {
        var after = ""
        while (true) {
            signal.throwIfCanceled()
            val rows = store.backupPage(after, signal)
            if (rows.isEmpty()) break
            rows.forEach { if (it.profileId == "self") yield(it) }
            after = rows.last().id
        }
    }

    private fun originals(store: HealthOriginalStore, signal: CancellationSignal) = sequence {
        var after = ""
        while (true) {
            signal.throwIfCanceled()
            val rows = store.backupPage(after, signal)
            if (rows.isEmpty()) break
            yieldAll(rows)
            after = rows.last().id
        }
    }

    private data class Sources(val items: List<HealthBackupOriginal>, val aliases: Map<String, HealthBackupOriginal>, val stamp: String) {
        fun project(record: HealthObservation): HealthObservation {
            val ref = record.draft.evidence ?: return record
            val item = aliases[ref.originalId]?.takeIf { it.sha256 == ref.sha256 }
                ?: throw HealthBackupException(HealthBackupIssue.MISSING_MANIFEST)
            return if (item.id == ref.originalId) record else record.copy(draft = record.draft.copy(evidence = ref.copy(originalId = item.id)))
        }
    }

    private fun manifestItem(original: HealthOriginal, store: HealthOriginalStore) =
        HealthBackupOriginal.from(original, !original.reviewOnly && store.present(original))

    private fun backupSources(records: HealthRecordStore, store: HealthOriginalStore, signal: CancellationSignal): Sources {
        val hashes = linkedMapOf<String, String>()
        val canonical = HashMap<String, Pair<HealthBackupOriginal, Boolean>>()
        // Backups use one source per content digest. Prefer a retained source to review-only metadata.
        originals(store, signal).forEach { original ->
            if (original.reviewOnly && !records.hasSelfOriginalLink(original.id)) return@forEach
            if (hashes.size == HealthBackupCodec.MAX_ORIGINALS) throw HealthBackupException(HealthBackupIssue.FORMAT)
            hashes[original.id] = original.sha256
            val previous = canonical[original.sha256]
            if (previous == null || previous.second && !original.reviewOnly) {
                canonical[original.sha256] = manifestItem(original, store) to original.reviewOnly
            }
        }
        val items = canonical.values.map { it.first }.sortedBy { it.id }
        val aliases = hashes.mapValues { (_, hash) -> canonical.getValue(hash).first }
        val digest = MessageDigest.getInstance("SHA-256")
        items.forEach { stamp(digest, it) }
        aliases.forEach { (id, item) ->
            digest.update(id.toByteArray(Charsets.US_ASCII))
            digest.update(item.id.toByteArray(Charsets.US_ASCII))
        }
        return Sources(items, aliases, digest.digest().toHex())
    }

    private fun ensureCurrent(records: HealthRecordStore, originals: HealthOriginalStore, expected: Map<HealthMetric, String>,
        originalStamp: String, signal: CancellationSignal): Sources {
        val sources = backupSources(records, originals, signal)
        if (sources.stamp != originalStamp || records.metricVersions(metrics) != expected) changed()
        signal.throwIfCanceled()
        return sources
    }

    private fun stamp(digest: MessageDigest, value: HealthBackupOriginal) {
        val bytes = value.json().toString().toByteArray(Charsets.UTF_8)
        try { digest.update(bytes); digest.update(0.toByte()) } finally { bytes.fill(0) }
    }

    private fun changed(): Nothing = throw HealthBackupException(HealthBackupIssue.SOURCE_CHANGED)

}
