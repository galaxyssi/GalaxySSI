package com.galaxyssi.chat

import android.content.Context
import android.os.CancellationSignal

internal data class HealthRecentFile(
    val id: String, val name: String, val added: Long, val size: Long,
    val source: HealthDataFileSource, val image: Boolean, val available: Boolean, val linked: Boolean,
)

internal enum class HealthDataFileSource {
    CAMERA, UPLOAD, CROP, OTHER;

    companion object {
        fun from(value: String) = when {
            value == "camera" -> CAMERA
            value == "file" -> UPLOAD
            value.startsWith("crop:") -> CROP
            else -> OTHER
        }
    }
}

internal data class HealthDataFileCounts(val camera: Long, val uploads: Long)

internal class HealthDataFilesRepository(context: Context, private val names: HealthOverviewDatabases) {
    private val context = context.applicationContext

    fun load(signal: CancellationSignal, recent: (Result<Pair<Long, List<HealthRecentFile>>>) -> Unit): HealthDataFileCounts {
        var delivered = false
        try {
            signal.throwIfCanceled()
            HealthRecordStore(context, names.records).use { records ->
                HealthOriginalStore(context, names.originals, names.originalRoot(context),
                    sharedRecords = records.takeIf { names.fixture == null }).use { originals ->
                    val count = records.count()
                    val latest = originals.originals(limit = RECENT_LIMIT, signal = signal).map { original ->
                        signal.throwIfCanceled()
                        HealthRecentFile(original.id, original.name, original.importedAt, original.size,
                            HealthDataFileSource.from(original.source), HealthOriginalKind.of(original) == HealthOriginalKind.IMAGE,
                            originals.present(original), records.hasSelfOriginalLink(original.id))
                    }
                    delivered = true
                    recent(Result.success(count to latest))
                    return countOriginals(originals, signal)
                }
            }
        } catch (failure: Exception) {
            if (!delivered) recent(Result.failure(failure))
            throw failure
        }
    }

    private fun countOriginals(originals: HealthOriginalStore, signal: CancellationSignal): HealthDataFileCounts {
        var camera = 0L
        var uploads = 0L
        var before: Pair<Long, String>? = null
        // The source is encrypted metadata. Read it in bounded pages without opening file contents.
        do {
            signal.throwIfCanceled()
            val page = originals.originals(before, signal = signal)
            for (file in page) when (HealthDataFileSource.from(file.source)) {
                HealthDataFileSource.CAMERA -> camera++
                HealthDataFileSource.UPLOAD -> uploads++
                else -> Unit
            }
            before = page.takeIf { it.size == 30 }?.last()?.let { it.importedAt to it.id }
        } while (before != null)
        return HealthDataFileCounts(camera, uploads)
    }

    companion object {
        const val RECENT_LIMIT = 4
    }
}
