package com.signalasi.chat

import org.json.JSONArray
import java.util.WeakHashMap

/** Keeps one immutable provider catalog for every model tool-loop adapter. */
internal class AgentModelToolCatalogSnapshot(
    private val protocol: AgentModelToolProtocolAdapter,
    catalog: List<AgentNativeToolDescriptor>,
    private val fingerprint: String = ""
) {
    val descriptors: List<AgentNativeToolDescriptor> = catalog.toList()

    val encoded: JSONArray by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        if (fingerprint.isBlank()) {
            protocol.encodeToolCatalog(descriptors)
        } else {
            AgentModelToolCatalogEncodingCache.getOrCompute(protocol, fingerprint) {
                protocol.encodeToolCatalog(descriptors)
            }
        }
    }
}

private object AgentModelToolCatalogEncodingCache {
    private val entries = WeakHashMap<AgentModelToolProtocolAdapter, LinkedHashMap<String, JSONArray>>()

    @Synchronized
    fun getOrCompute(
        protocol: AgentModelToolProtocolAdapter,
        fingerprint: String,
        compute: () -> JSONArray
    ): JSONArray {
        val protocolEntries = entries.getOrPut(protocol) {
            object : LinkedHashMap<String, JSONArray>(MAX_ENTRIES_PER_PROTOCOL, 0.75f, true) {
                override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, JSONArray>?): Boolean =
                    size > MAX_ENTRIES_PER_PROTOCOL
            }
        }
        return protocolEntries[fingerprint] ?: compute().also { protocolEntries[fingerprint] = it }
    }

    private const val MAX_ENTRIES_PER_PROTOCOL = 8
}
