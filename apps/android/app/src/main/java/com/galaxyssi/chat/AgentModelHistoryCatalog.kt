package com.galaxyssi.chat

import org.json.JSONObject

/** New runs opt in atomically; upgrading the App never changes a saved run's tool contract. */
internal object AgentModelHistoryCatalog {
    internal const val OPERATION = "model-history-catalog:v1"

    suspend fun prepare(journal: AgentModelLoopJournal, scope: AgentModelLoopScope,
        registry: AgentNativeToolRegistry): AgentNativeToolRegistry = journal.withLease(scope) { records ->
        require(AgentModelHistoryTools.ID !in registry.ids())
        val binding = AgentNativeJsonCodec.stringify(mapOf("version" to 1, "scope" to scope.value(),
            "base_manifest" to registry.registeredContractCatalog().manifest.sha256))
        val saved = records.read(OPERATION)
        if (saved == null && listOf("initial", AgentPlannerToolCatalogBinding.OPERATION,
                LocalModelLoopContinuationStore.OPERATION).any { records.read(it) != null }) return@withLease registry
        if (saved != null) {
            val matches = runCatching {
                val value = JSONObject(saved)
                val owner = value.getJSONObject("scope")
                value.keys().asSequence().toSet() == setOf("version", "scope", "base_manifest") &&
                    value.getInt("version") == 1 &&
                    value.getString("base_manifest") == registry.registeredContractCatalog().manifest.sha256 &&
                    owner.keys().asSequence().toSet() == scope.value().keys &&
                    scope.value().all { (key, expected) -> owner.getString(key) == expected }
            }.getOrDefault(false)
            if (!matches) throw AgentModelLoopRecoveryException("model_history_catalog_binding_changed")
        } else records.write(OPERATION, binding)
        registry.subset { true }.register(AgentModelHistoryTools.definition())
    }
}
