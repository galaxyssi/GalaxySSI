package com.galaxyssi.chat

import org.json.JSONObject

/** Setup changes readiness, not the original task's registered tool contracts. */
internal object AgentPlannerToolCatalogBinding {
    const val OPERATION = "planner-tool-catalog:v1"

    suspend fun prepare(journal: AgentModelLoopJournal, request: AgentModelToolLoopRequest,
        registry: AgentNativeToolRegistry): AgentPlannerToolCatalogSession {
        val scope = AgentModelLoopScope.from(request)
        val contracts = registry.registeredContractCatalog()
        val available = registry.availableCatalog()
        return journal.withLease(scope) { records ->
            val saved = records.read(OPERATION)
            if (saved != null) {
                val value = decode(saved, scope)
                if (value.getString("manifest") != contracts.manifest.sha256)
                    throw AgentModelLoopRecoveryException("planner_tool_contracts_changed")
            } else {
                val initial = records.read("initial")
                if (initial != null) {
                    val fingerprint = try { JSONObject(initial).getJSONObject("binding").getString("manifest") }
                    catch (error: Exception) { throw AgentModelLoopRecoveryException("planner_legacy_catalog_invalid", error) }
                    if (fingerprint != available.manifest.sha256)
                        throw AgentModelLoopRecoveryException("planner_legacy_catalog_changed")
                    // A legacy available-only checkpoint cannot prove its original unavailable contracts.
                    return@withLease AgentPlannerToolCatalogSession(scope, registry, available, available, false)
                }
                records.write(OPERATION, JSONObject().put("version", 1).put("kind", "registered_contracts_v1")
                    .put("scope", JSONObject(scope.value())).put("manifest", contracts.manifest.sha256).toString())
            }
            AgentPlannerToolCatalogSession(scope, registry, contracts, available, true)
        }
    }

    private fun decode(encoded: String, scope: AgentModelLoopScope): JSONObject = try {
        JSONObject(encoded).also { value ->
            check(value.getInt("version") == 1 && value.getString("kind") == "registered_contracts_v1")
            val owner = value.getJSONObject("scope")
            check(owner.keys().asSequence().toSet() == scope.value().keys)
            check(scope.value().all { (key, expected) -> owner.getString(key) == expected })
            check(value.getString("manifest").matches(Regex("[a-f0-9]{64}")))
        }
    } catch (error: Exception) { throw AgentModelLoopRecoveryException("planner_tool_catalog_binding_invalid", error) }
}

internal class AgentPlannerToolCatalogSession(
    private val scope: AgentModelLoopScope,
    private val registry: AgentNativeToolRegistry,
    val binding: AgentNativeToolCatalogView,
    val initialAvailable: AgentNativeToolCatalogView,
    private val refreshReadiness: Boolean
) {
    private val contracts = binding.descriptors.associateBy { it.id }
    private var lastObservation: List<String?>? = null

    @Synchronized
    fun providerCatalog(request: AgentModelRequest): AgentNativeToolCatalogView {
        if (request.toolManifestSha256 != binding.manifest.sha256 ||
            listOf(request.sessionId, request.conversationId, request.turnId, request.taskId, request.workspaceId) !=
            listOf(scope.session, scope.conversation, scope.turn, scope.task, scope.workspace))
            throw AgentModelLoopRecoveryException("planner_provider_catalog_owner_changed")
        if (!refreshReadiness) return initialAvailable
        if (registry.ids() != contracts.keys)
            throw AgentModelLoopRecoveryException("planner_tool_contracts_changed")
        val observed = request.messages.asReversed().asSequence().mapNotNull { it.toolResult }
            .takeWhile { observationKey(it) != lastObservation }.toList()
        val refresh = observed.any { result ->
            result.toolId in AgentToolInspectionTools.toolIds || mayChangeReadiness(contracts[result.toolId])
        }
        observed.firstOrNull()?.let { lastObservation = observationKey(it) }
        val current = registry.availableCatalog(refresh = refresh)
        if (current.descriptors.any { descriptor ->
                val original = contracts[descriptor.id]
                original == null || descriptor.copy(availability = original.availability) != original
            }) throw AgentModelLoopRecoveryException("planner_tool_contracts_changed")
        return current
    }

    private fun observationKey(result: AgentModelToolResultContent) =
        listOf(result.invocationId, result.callId, result.toolId, result.status)

    private fun mayChangeReadiness(descriptor: AgentNativeToolDescriptor?): Boolean = descriptor == null ||
        !(descriptor.effect == AgentNativeToolEffect.READ_ONLY || descriptor.effect == null &&
            descriptor.concurrency == AgentNativeToolConcurrency.PARALLEL_READ_ONLY)
}
