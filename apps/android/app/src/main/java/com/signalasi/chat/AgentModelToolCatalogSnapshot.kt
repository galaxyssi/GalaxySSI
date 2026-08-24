package com.signalasi.chat

import org.json.JSONArray

/** Keeps one immutable provider catalog for every model tool-loop adapter. */
internal class AgentModelToolCatalogSnapshot(
    private val protocol: AgentModelToolProtocolAdapter,
    catalog: List<AgentNativeToolDescriptor>
) {
    val descriptors: List<AgentNativeToolDescriptor> = catalog.toList()

    val encoded: JSONArray by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        protocol.encodeToolCatalog(descriptors)
    }
}
