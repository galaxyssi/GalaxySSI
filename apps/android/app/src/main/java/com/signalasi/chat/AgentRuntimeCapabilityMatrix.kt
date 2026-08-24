package com.signalasi.chat

import java.util.Locale

enum class AgentRuntimeCapabilitySource {
    NATIVE_TOOL,
    SYSTEM_TOOL,
    CONNECTOR
}

enum class AgentRuntimeCapabilityState {
    AVAILABLE,
    REQUIRES_SETUP,
    UNAVAILABLE,
    BLOCKED
}

data class AgentRuntimeCapabilityEntry(
    val id: String,
    val title: String,
    val source: AgentRuntimeCapabilitySource,
    val state: AgentRuntimeCapabilityState,
    val capabilities: Set<String>,
    val location: String,
    val risk: String,
    val reason: String = "",
    val requiredPermissions: Set<String> = emptySet(),
    val requiredConsents: Set<String> = emptySet()
) {
    val executable: Boolean
        get() = state == AgentRuntimeCapabilityState.AVAILABLE
}

data class AgentRuntimeCapabilitySnapshot(
    val entries: List<AgentRuntimeCapabilityEntry>
) {
    private data class Index(
        val entriesBySource: Map<AgentRuntimeCapabilitySource, Map<String, AgentRuntimeCapabilityEntry>>,
        val availableEntries: List<AgentRuntimeCapabilityEntry>,
        val availableNativeToolIds: Set<String>,
        val setupRequiredEntries: List<AgentRuntimeCapabilityEntry>,
        val unavailableEntries: List<AgentRuntimeCapabilityEntry>
    )

    private val index: Index by lazy(LazyThreadSafetyMode.PUBLICATION, ::buildIndex)

    val availableEntries: List<AgentRuntimeCapabilityEntry>
        get() = index.availableEntries

    val availableNativeToolIds: Set<String>
        get() = index.availableNativeToolIds

    val setupRequiredEntries: List<AgentRuntimeCapabilityEntry>
        get() = index.setupRequiredEntries

    val unavailableEntries: List<AgentRuntimeCapabilityEntry>
        get() = index.unavailableEntries

    fun entry(source: AgentRuntimeCapabilitySource, id: String): AgentRuntimeCapabilityEntry? =
        index.entriesBySource[source]?.get(id)

    fun isNativeToolExecutable(id: String): Boolean =
        entry(AgentRuntimeCapabilitySource.NATIVE_TOOL, id)?.executable == true

    private fun buildIndex(): Index {
        val entriesBySource = mutableMapOf<
            AgentRuntimeCapabilitySource,
            MutableMap<String, AgentRuntimeCapabilityEntry>
        >()
        val availableEntries = mutableListOf<AgentRuntimeCapabilityEntry>()
        val availableNativeToolIds = linkedSetOf<String>()
        val setupRequiredEntries = mutableListOf<AgentRuntimeCapabilityEntry>()
        val unavailableEntries = mutableListOf<AgentRuntimeCapabilityEntry>()
        entries.forEach { entry ->
            entriesBySource.getOrPut(entry.source) { linkedMapOf() }.putIfAbsent(entry.id, entry)
            if (entry.executable) {
                availableEntries += entry
                if (entry.source == AgentRuntimeCapabilitySource.NATIVE_TOOL) {
                    availableNativeToolIds += entry.id
                }
            }
            when (entry.state) {
                AgentRuntimeCapabilityState.REQUIRES_SETUP -> setupRequiredEntries += entry
                AgentRuntimeCapabilityState.UNAVAILABLE,
                AgentRuntimeCapabilityState.BLOCKED -> unavailableEntries += entry
                AgentRuntimeCapabilityState.AVAILABLE -> Unit
            }
        }
        return Index(
            entriesBySource = entriesBySource.mapValues { (_, indexedEntries) -> indexedEntries.toMap() },
            availableEntries = availableEntries.toList(),
            availableNativeToolIds = availableNativeToolIds.toSet(),
            setupRequiredEntries = setupRequiredEntries.toList(),
            unavailableEntries = unavailableEntries.toList()
        )
    }

    companion object {
        val EMPTY = AgentRuntimeCapabilitySnapshot(emptyList())
    }
}

/**
 * One host-owned view of what is installed, configured, permitted, and executable now.
 * Unavailable entries stay visible for diagnostics but never become planning candidates.
 */
object AgentRuntimeCapabilityMatrix {
    fun build(
        nativeTools: List<AgentNativeToolDescriptor>,
        systemTools: List<AgentSystemTool>,
        targets: List<AgentCallableTarget>
    ): AgentRuntimeCapabilitySnapshot {
        val nativeById = nativeTools.associateBy(AgentNativeToolDescriptor::id)
        val entries = buildList {
            addAll(nativeTools.map(::nativeEntry))
            addAll(systemTools.map { systemEntry(it, nativeById) })
            addAll(targets.map(::connectorEntry))
        }.distinctBy { "${it.source.name}:${it.id}" }
            .sortedWith(compareBy<AgentRuntimeCapabilityEntry> { it.source.ordinal }.thenBy { it.id })
        return AgentRuntimeCapabilitySnapshot(entries)
    }

    fun availableNativeTools(
        nativeTools: List<AgentNativeToolDescriptor>,
        systemTools: List<AgentSystemTool> = emptyList(),
        targets: List<AgentCallableTarget> = emptyList()
    ): List<AgentNativeToolDescriptor> {
        val snapshot = build(nativeTools, systemTools, targets)
        return nativeTools.filter { snapshot.isNativeToolExecutable(it.id) }
    }

    private fun nativeEntry(tool: AgentNativeToolDescriptor): AgentRuntimeCapabilityEntry {
        val state = when {
            tool.availability.status == AgentNativeToolAvailabilityStatus.AVAILABLE ->
                AgentRuntimeCapabilityState.AVAILABLE
            tool.availability.status == AgentNativeToolAvailabilityStatus.REQUIRES_SETUP ->
                AgentRuntimeCapabilityState.REQUIRES_SETUP
            else -> AgentRuntimeCapabilityState.UNAVAILABLE
        }
        return AgentRuntimeCapabilityEntry(
            id = tool.id,
            title = tool.title,
            source = AgentRuntimeCapabilitySource.NATIVE_TOOL,
            state = state,
            capabilities = tool.capabilities,
            location = tool.location.wireValue,
            risk = tool.risk.wireValue,
            reason = tool.availability.reason,
            requiredPermissions = tool.requiredPermissions.filter { it.required }.mapTo(linkedSetOf()) { it.id },
            requiredConsents = tool.requiredConsents.filter { it.required }.mapTo(linkedSetOf()) { it.id }
        )
    }

    private fun systemEntry(
        tool: AgentSystemTool,
        nativeById: Map<String, AgentNativeToolDescriptor>
    ): AgentRuntimeCapabilityEntry {
        val hostOwnedWorkflow = tool.id.startsWith("workflow:") || tool.id.startsWith("template:")
        val native = nativeById[AgentNativeToolAgentActionAdapter.defaultToolId(tool.kind)]
        val state = when {
            hostOwnedWorkflow -> AgentRuntimeCapabilityState.AVAILABLE
            native == null -> AgentRuntimeCapabilityState.UNAVAILABLE
            native.availability.status == AgentNativeToolAvailabilityStatus.AVAILABLE ->
                AgentRuntimeCapabilityState.AVAILABLE
            native.availability.status == AgentNativeToolAvailabilityStatus.REQUIRES_SETUP ->
                AgentRuntimeCapabilityState.REQUIRES_SETUP
            else -> AgentRuntimeCapabilityState.UNAVAILABLE
        }
        return AgentRuntimeCapabilityEntry(
            id = tool.id,
            title = tool.title,
            source = AgentRuntimeCapabilitySource.SYSTEM_TOOL,
            state = state,
            capabilities = tool.capabilities.mapTo(linkedSetOf()) { it.name.lowercase(Locale.US) },
            location = AgentResourceLocation.PHONE.name.lowercase(Locale.US),
            risk = tool.risk.name.lowercase(Locale.US),
            reason = when {
                hostOwnedWorkflow -> "Host-owned workflow is installed"
                native == null -> "No executable native adapter is registered"
                else -> native.availability.reason
            },
            requiredPermissions = native?.requiredPermissions.orEmpty()
                .filter { it.required }.mapTo(linkedSetOf()) { it.id },
            requiredConsents = native?.requiredConsents.orEmpty()
                .filter { it.required }.mapTo(linkedSetOf()) { it.id }
        )
    }

    private fun connectorEntry(target: AgentCallableTarget): AgentRuntimeCapabilityEntry =
        AgentRuntimeCapabilityEntry(
            id = target.id,
            title = target.title,
            source = AgentRuntimeCapabilitySource.CONNECTOR,
            state = when (target.status) {
                AgentConnectorStatus.AVAILABLE -> AgentRuntimeCapabilityState.AVAILABLE
                AgentConnectorStatus.NEEDS_SETUP -> AgentRuntimeCapabilityState.REQUIRES_SETUP
                AgentConnectorStatus.DISCONNECTED -> AgentRuntimeCapabilityState.UNAVAILABLE
            },
            capabilities = target.capabilities.mapTo(linkedSetOf()) { it.name.lowercase(Locale.US) },
            location = target.failureDomain.ifBlank { "external" },
            risk = AgentNativeToolRisk.MEDIUM.wireValue,
            reason = target.status.name.lowercase(Locale.US)
        )
}
