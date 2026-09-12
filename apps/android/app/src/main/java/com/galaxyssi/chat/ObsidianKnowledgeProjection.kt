package com.galaxyssi.chat

internal object ObsidianKnowledgeProjection {
    fun run(store: SQLiteAgentKnowledgeStore, state: ObsidianAndroidStateStore, namespace: String, maximumWrites: Int,
        legacy: (ObsidianProjectionSpec) -> ObsidianProjectionIndexEntry?,
        write: (ObsidianProjectionSpec, String) -> Unit): ObsidianProjectionBatchResult = ObsidianProjectionCursor.run(
        namespace, state.projectionCheckpoint(), maximumWrites, { store.sourcePage(it, 50) }, store::sourceRevision,
        { group, budget -> ObsidianProjectionBatch.run(sequenceOf(spec(store, group)), budget, state::index, legacy, write) },
        state::saveProjectionCheckpoint)

    fun runStreaming(store: SQLiteAgentKnowledgeStore, state: ObsidianAndroidStateStore, namespace: String, maximumWrites: Int,
        legacy: (ObsidianProjectionSpec) -> ObsidianProjectionIndexEntry?,
        write: (ObsidianProjectionSpec, ObsidianPreparedContent) -> Unit): ObsidianProjectionBatchResult = ObsidianProjectionCursor.run(
        namespace, state.projectionCheckpoint(), maximumWrites, { store.sourcePage(it, 50) }, store::sourceRevision,
        { group, budget -> ObsidianProjectionBatch.runStreaming(sequenceOf(spec(store, group)), budget, state::index, legacy, write) },
        state::saveProjectionCheckpoint)

    fun specs(store: SQLiteAgentKnowledgeStore): Sequence<ObsidianProjectionSpec> = sequence {
        var cursor: AgentKnowledgeSourceCursor? = null
        do {
            val page = store.sourcePage(cursor)
            for (group in page.groups) yield(spec(store, group))
            cursor = page.next
        } while (cursor != null)
    }

    private fun spec(store: SQLiteAgentKnowledgeStore, group: AgentKnowledgeSourceGroup): ObsidianProjectionSpec {
        val reference = requireNotNull(group.reference)
        val source = reference.source.ifBlank { reference.localItemId }
        val snapshot = store.sourceExport(reference)
        val type = if (source.startsWith("http://") || source.startsWith("https://")) "reading" else "knowledge"
        val folder = if (type == "reading") "60 Reading" else "10 Knowledge"
        val sourceKey = ObsidianKnowledgeIdentity.sourceKey(reference)
        val prepare = { ObsidianStreamingKnowledge.prepare(snapshot, sourceKey, type, source) }
        return ObsidianProjectionSpec(sourceKey,
            "$folder/${ObsidianAndroidBridge.fileName(group.title, sourceKey)}", snapshot.revision, reference,
            prepareContent = prepare) { prepare().use(ObsidianProjectionBatch::readSmallContent) }
    }
}

internal data class ObsidianProjectionBatchResult(val written: Int, val unchanged: Int, val remaining: Int)

/** A write budget bounds work per run, not the total number of exportable sources. */
internal object ObsidianProjectionBatch {
    fun run(specs: Sequence<ObsidianProjectionSpec>, maximumWrites: Int,
        indexed: (String) -> ObsidianProjectionIndexEntry?,
        legacy: (ObsidianProjectionSpec) -> ObsidianProjectionIndexEntry? = { null },
        write: (ObsidianProjectionSpec, String) -> Unit): ObsidianProjectionBatchResult =
        runStreaming(specs, maximumWrites, indexed, legacy) { spec, prepared -> write(spec, readSmallContent(prepared)) }

    // Compatibility for small String-based callers and tests, not the production knowledge path.
    internal fun readSmallContent(content: ObsidianPreparedContent): String = java.io.ByteArrayOutputStream().use {
        content.writeTo(it)
        it.toString("UTF-8")
    }

    fun runStreaming(specs: Sequence<ObsidianProjectionSpec>, maximumWrites: Int,
        indexed: (String) -> ObsidianProjectionIndexEntry?,
        legacy: (ObsidianProjectionSpec) -> ObsidianProjectionIndexEntry? = { null },
        write: (ObsidianProjectionSpec, ObsidianPreparedContent) -> Unit): ObsidianProjectionBatchResult {
        var written = 0
        var unchanged = 0
        var remaining = 0
        for (spec in specs) {
            val previous = indexed(spec.sourceKey) ?: legacy(spec)
            if (previous?.userModified == true || previous?.sourceRevision == spec.sourceRevision) {
                unchanged++
                continue
            }
            if (written >= maximumWrites.coerceIn(0, 32)) {
                remaining++
                continue
            }
            spec.prepare().use { content ->
                if (content.isBlank) unchanged++ else {
                    // Keep an existing note's path when its display title or grouping preview changes.
                    write(spec.copy(relativePath = previous?.relativePath?.takeIf(String::isNotBlank) ?: spec.relativePath,
                        retiredSourceKey = previous?.sourceKey?.takeIf { it != spec.sourceKey }.orEmpty()), content)
                    written++
                }
            }
        }
        return ObsidianProjectionBatchResult(written, unchanged, remaining)
    }
}
