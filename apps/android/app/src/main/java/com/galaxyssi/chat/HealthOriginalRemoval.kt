package com.galaxyssi.chat

internal data class HealthOriginalRemovalPreview(
    val original: HealthOriginal,
    val linkedMeasurements: Long,
    val versions: Map<HealthMetric, String>,
)

internal class HealthOriginalRemovalChanged : IllegalStateException("Health original or linked records changed after preview")

internal object HealthOriginalRemoval {
    fun preview(originals: HealthOriginalStore, records: HealthRecordStore, original: HealthOriginal): HealthOriginalRemovalPreview {
        val versions = records.metricVersions(HealthMetric.entries.toSet())
        var count = 0L
        var after: HealthPageCursor? = null
        do {
            val page = records.originalPage(original.id, after)
            count += page.records.count { it.profileId == "self" }
            after = page.next
        } while (after != null)
        if (records.metricVersions(versions.keys) != versions || originals.original(original.id) != original || !originals.present(original))
            throw HealthOriginalRemovalChanged()
        return HealthOriginalRemovalPreview(original, count, versions)
    }

    fun confirm(originals: HealthOriginalStore, records: HealthRecordStore, preview: HealthOriginalRemovalPreview) {
        originals.removeReviewedOriginal(preview.original) {
            if (records.metricVersions(preview.versions.keys) != preview.versions) throw HealthOriginalRemovalChanged()
        }
    }
}
