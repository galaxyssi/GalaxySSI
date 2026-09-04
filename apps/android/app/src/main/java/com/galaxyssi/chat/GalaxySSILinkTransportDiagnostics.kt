package com.galaxyssi.chat

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID

internal enum class GalaxySSILinkDiagnosticKind(val wireName: String) {
    ENCRYPTED_REPLAY("encrypted_replay"),
    PENDING_REPLAY("pending_replay"),
    DUPLICATE_MESSAGE("duplicate_message"),
    DUPLICATE_RECEIPT("duplicate_receipt"),
    OLD_COUNTER("old_counter"),
    DECRYPT_FAILURE("decrypt_failure"),
    CHUNK_DUPLICATE("chunk_duplicate"),
    FRAGMENT_REJECTED("fragment_rejected");

    companion object {
        fun fromWireName(value: String): GalaxySSILinkDiagnosticKind? =
            entries.firstOrNull { it.wireName == value }
    }
}

internal data class GalaxySSILinkDiagnosticEvent(
    val id: String,
    val kind: GalaxySSILinkDiagnosticKind,
    val recordedAtMillis: Long,
    val endpointRef: String,
    val messageRef: String,
    val detailCode: String
)

internal data class GalaxySSILinkDiagnosticSnapshot(
    val totalEvents: Long,
    val counts: Map<GalaxySSILinkDiagnosticKind, Long>,
    val recentEvents: List<GalaxySSILinkDiagnosticEvent>
) {
    val replayCount: Long
        get() = count(GalaxySSILinkDiagnosticKind.ENCRYPTED_REPLAY) +
            count(GalaxySSILinkDiagnosticKind.PENDING_REPLAY)

    val duplicateCount: Long
        get() = count(GalaxySSILinkDiagnosticKind.DUPLICATE_MESSAGE) +
            count(GalaxySSILinkDiagnosticKind.DUPLICATE_RECEIPT) +
            count(GalaxySSILinkDiagnosticKind.CHUNK_DUPLICATE)

    val oldCounterCount: Long
        get() = count(GalaxySSILinkDiagnosticKind.OLD_COUNTER)

    val failureCount: Long
        get() = count(GalaxySSILinkDiagnosticKind.DECRYPT_FAILURE) +
            count(GalaxySSILinkDiagnosticKind.FRAGMENT_REJECTED)

    fun count(kind: GalaxySSILinkDiagnosticKind): Long = counts[kind] ?: 0L
}

internal interface GalaxySSILinkDiagnosticStore {
    fun read(): JSONObject
    fun write(value: JSONObject)
    fun clear()
}

internal class SharedPreferencesGalaxySSILinkDiagnosticStore(
    context: Context
) : GalaxySSILinkDiagnosticStore {
    private val preferences: SharedPreferences = context.applicationContext.getSharedPreferences(
        PREFERENCES,
        Context.MODE_PRIVATE
    )

    override fun read(): JSONObject = runCatching {
        JSONObject(preferences.getString(KEY_STATE, null) ?: "{}")
    }.getOrDefault(JSONObject())

    override fun write(value: JSONObject) {
        preferences.edit().putString(KEY_STATE, value.toString()).apply()
    }

    override fun clear() {
        preferences.edit().clear().apply()
    }

    companion object {
        const val PREFERENCES = "galaxyssi_link_transport_diagnostics"
        private const val KEY_STATE = "state"
    }
}

internal class InMemoryGalaxySSILinkDiagnosticStore : GalaxySSILinkDiagnosticStore {
    private var state = JSONObject()

    override fun read(): JSONObject = JSONObject(state.toString())

    override fun write(value: JSONObject) {
        state = JSONObject(value.toString())
    }

    override fun clear() {
        state = JSONObject()
    }
}

internal class GalaxySSILinkDiagnosticLedger(
    private val store: GalaxySSILinkDiagnosticStore,
    private val clock: () -> Long = System::currentTimeMillis,
    private val maximumEvents: Int = DEFAULT_MAXIMUM_EVENTS
) {
    init {
        require(maximumEvents > 0)
    }

    @Synchronized
    fun record(
        kind: GalaxySSILinkDiagnosticKind,
        endpointIdentity: String = "",
        messageIdentity: String = "",
        detailCode: String = ""
    ): GalaxySSILinkDiagnosticSnapshot {
        val state = store.read()
        val counts = state.optJSONObject(KEY_COUNTS) ?: JSONObject()
        counts.put(kind.wireName, counts.optLong(kind.wireName, 0L) + 1L)

        val events = state.optJSONArray(KEY_EVENTS) ?: JSONArray()
        events.put(
            JSONObject()
                .put("id", UUID.randomUUID().toString())
                .put("kind", kind.wireName)
                .put("recorded_at", clock())
                .put("endpoint_ref", anonymizedReference(endpointIdentity))
                .put("message_ref", anonymizedReference(messageIdentity))
                .put("detail_code", normalizedDetailCode(detailCode))
        )
        while (events.length() > maximumEvents) {
            events.remove(0)
        }

        state.put(KEY_PROTOCOL, PROTOCOL)
        state.put(KEY_TOTAL, state.optLong(KEY_TOTAL, 0L) + 1L)
        state.put(KEY_COUNTS, counts)
        state.put(KEY_EVENTS, events)
        store.write(state)
        return snapshotOf(state)
    }

    @Synchronized
    fun snapshot(): GalaxySSILinkDiagnosticSnapshot = snapshotOf(store.read())

    @Synchronized
    fun clear() {
        store.clear()
    }

    private fun snapshotOf(state: JSONObject): GalaxySSILinkDiagnosticSnapshot {
        val countsObject = state.optJSONObject(KEY_COUNTS) ?: JSONObject()
        val counts = GalaxySSILinkDiagnosticKind.entries.associateWith { kind ->
            countsObject.optLong(kind.wireName, 0L)
        }
        val eventArray = state.optJSONArray(KEY_EVENTS) ?: JSONArray()
        val events = buildList {
            for (index in eventArray.length() - 1 downTo 0) {
                val item = eventArray.optJSONObject(index) ?: continue
                val kind = GalaxySSILinkDiagnosticKind.fromWireName(item.optString("kind")) ?: continue
                add(
                    GalaxySSILinkDiagnosticEvent(
                        id = item.optString("id"),
                        kind = kind,
                        recordedAtMillis = item.optLong("recorded_at"),
                        endpointRef = item.optString("endpoint_ref"),
                        messageRef = item.optString("message_ref"),
                        detailCode = item.optString("detail_code")
                    )
                )
            }
        }
        return GalaxySSILinkDiagnosticSnapshot(
            totalEvents = state.optLong(KEY_TOTAL, counts.values.sum()),
            counts = counts,
            recentEvents = events
        )
    }

    companion object {
        const val PROTOCOL = "galaxyssi.link-transport-diagnostics/1.0"
        const val DEFAULT_MAXIMUM_EVENTS = 40
        private const val KEY_PROTOCOL = "protocol"
        private const val KEY_TOTAL = "total_events"
        private const val KEY_COUNTS = "counts"
        private const val KEY_EVENTS = "recent_events"

        internal fun anonymizedReference(value: String): String {
            if (value.isBlank()) return ""
            return MessageDigest.getInstance("SHA-256")
                .digest(value.toByteArray(Charsets.UTF_8))
                .take(6)
                .joinToString("") { "%02x".format(Locale.US, it) }
        }

        internal fun normalizedDetailCode(value: String): String =
            value.trim()
                .lowercase(Locale.US)
                .replace(Regex("[^a-z0-9_.-]+"), "_")
                .trim('_')
                .take(64)
    }
}

internal object GalaxySSILinkTransportDiagnostics {
    @Volatile
    private var ledger: GalaxySSILinkDiagnosticLedger? = null

    fun record(
        context: Context,
        kind: GalaxySSILinkDiagnosticKind,
        endpointIdentity: String = "",
        messageIdentity: String = "",
        detailCode: String = ""
    ): GalaxySSILinkDiagnosticSnapshot =
        runtime(context).record(kind, endpointIdentity, messageIdentity, detailCode)

    fun snapshot(context: Context): GalaxySSILinkDiagnosticSnapshot =
        runtime(context).snapshot()

    fun clear(context: Context) {
        runtime(context).clear()
    }

    internal fun classifyDecryptionFailure(error: Throwable): GalaxySSILinkDiagnosticKind {
        val className = error.javaClass.simpleName.lowercase(Locale.US)
        val message = error.message.orEmpty().lowercase(Locale.US)
        return when {
            "old counter" in message || "oldcounter" in message ->
                GalaxySSILinkDiagnosticKind.OLD_COUNTER
            "duplicatemessage" in className || "duplicate message" in message ->
                GalaxySSILinkDiagnosticKind.DUPLICATE_MESSAGE
            else -> GalaxySSILinkDiagnosticKind.DECRYPT_FAILURE
        }
    }

    internal fun classifyFragmentFailure(error: Throwable): GalaxySSILinkDiagnosticKind =
        if ("duplicate" in error.message.orEmpty().lowercase(Locale.US)) {
            GalaxySSILinkDiagnosticKind.CHUNK_DUPLICATE
        } else {
            GalaxySSILinkDiagnosticKind.FRAGMENT_REJECTED
        }

    @Synchronized
    private fun runtime(context: Context): GalaxySSILinkDiagnosticLedger =
        ledger ?: GalaxySSILinkDiagnosticLedger(
            SharedPreferencesGalaxySSILinkDiagnosticStore(context.applicationContext)
        ).also { ledger = it }
}
