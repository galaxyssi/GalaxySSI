package com.signalasi.chat

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID

internal enum class SignalASILinkDiagnosticKind(val wireName: String) {
    ENCRYPTED_REPLAY("encrypted_replay"),
    PENDING_REPLAY("pending_replay"),
    DUPLICATE_MESSAGE("duplicate_message"),
    DUPLICATE_RECEIPT("duplicate_receipt"),
    OLD_COUNTER("old_counter"),
    DECRYPT_FAILURE("decrypt_failure"),
    CHUNK_DUPLICATE("chunk_duplicate"),
    FRAGMENT_REJECTED("fragment_rejected");

    companion object {
        fun fromWireName(value: String): SignalASILinkDiagnosticKind? =
            entries.firstOrNull { it.wireName == value }
    }
}

internal data class SignalASILinkDiagnosticEvent(
    val id: String,
    val kind: SignalASILinkDiagnosticKind,
    val recordedAtMillis: Long,
    val endpointRef: String,
    val messageRef: String,
    val detailCode: String
)

internal data class SignalASILinkDiagnosticSnapshot(
    val totalEvents: Long,
    val counts: Map<SignalASILinkDiagnosticKind, Long>,
    val recentEvents: List<SignalASILinkDiagnosticEvent>
) {
    val replayCount: Long
        get() = count(SignalASILinkDiagnosticKind.ENCRYPTED_REPLAY) +
            count(SignalASILinkDiagnosticKind.PENDING_REPLAY)

    val duplicateCount: Long
        get() = count(SignalASILinkDiagnosticKind.DUPLICATE_MESSAGE) +
            count(SignalASILinkDiagnosticKind.DUPLICATE_RECEIPT) +
            count(SignalASILinkDiagnosticKind.CHUNK_DUPLICATE)

    val oldCounterCount: Long
        get() = count(SignalASILinkDiagnosticKind.OLD_COUNTER)

    val failureCount: Long
        get() = count(SignalASILinkDiagnosticKind.DECRYPT_FAILURE) +
            count(SignalASILinkDiagnosticKind.FRAGMENT_REJECTED)

    fun count(kind: SignalASILinkDiagnosticKind): Long = counts[kind] ?: 0L
}

internal interface SignalASILinkDiagnosticStore {
    fun read(): JSONObject
    fun write(value: JSONObject)
    fun clear()
}

internal class SharedPreferencesSignalASILinkDiagnosticStore(
    context: Context
) : SignalASILinkDiagnosticStore {
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
        const val PREFERENCES = "signalasi_link_transport_diagnostics"
        private const val KEY_STATE = "state"
    }
}

internal class InMemorySignalASILinkDiagnosticStore : SignalASILinkDiagnosticStore {
    private var state = JSONObject()

    override fun read(): JSONObject = JSONObject(state.toString())

    override fun write(value: JSONObject) {
        state = JSONObject(value.toString())
    }

    override fun clear() {
        state = JSONObject()
    }
}

internal class SignalASILinkDiagnosticLedger(
    private val store: SignalASILinkDiagnosticStore,
    private val clock: () -> Long = System::currentTimeMillis,
    private val maximumEvents: Int = DEFAULT_MAXIMUM_EVENTS
) {
    init {
        require(maximumEvents > 0)
    }

    @Synchronized
    fun record(
        kind: SignalASILinkDiagnosticKind,
        endpointIdentity: String = "",
        messageIdentity: String = "",
        detailCode: String = ""
    ): SignalASILinkDiagnosticSnapshot {
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
    fun snapshot(): SignalASILinkDiagnosticSnapshot = snapshotOf(store.read())

    @Synchronized
    fun clear() {
        store.clear()
    }

    private fun snapshotOf(state: JSONObject): SignalASILinkDiagnosticSnapshot {
        val countsObject = state.optJSONObject(KEY_COUNTS) ?: JSONObject()
        val counts = SignalASILinkDiagnosticKind.entries.associateWith { kind ->
            countsObject.optLong(kind.wireName, 0L)
        }
        val eventArray = state.optJSONArray(KEY_EVENTS) ?: JSONArray()
        val events = buildList {
            for (index in eventArray.length() - 1 downTo 0) {
                val item = eventArray.optJSONObject(index) ?: continue
                val kind = SignalASILinkDiagnosticKind.fromWireName(item.optString("kind")) ?: continue
                add(
                    SignalASILinkDiagnosticEvent(
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
        return SignalASILinkDiagnosticSnapshot(
            totalEvents = state.optLong(KEY_TOTAL, counts.values.sum()),
            counts = counts,
            recentEvents = events
        )
    }

    companion object {
        const val PROTOCOL = "signalasi.link-transport-diagnostics/1.0"
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

internal object SignalASILinkTransportDiagnostics {
    @Volatile
    private var ledger: SignalASILinkDiagnosticLedger? = null

    fun record(
        context: Context,
        kind: SignalASILinkDiagnosticKind,
        endpointIdentity: String = "",
        messageIdentity: String = "",
        detailCode: String = ""
    ): SignalASILinkDiagnosticSnapshot =
        runtime(context).record(kind, endpointIdentity, messageIdentity, detailCode)

    fun snapshot(context: Context): SignalASILinkDiagnosticSnapshot =
        runtime(context).snapshot()

    fun clear(context: Context) {
        runtime(context).clear()
    }

    internal fun classifyDecryptionFailure(error: Throwable): SignalASILinkDiagnosticKind {
        val className = error.javaClass.simpleName.lowercase(Locale.US)
        val message = error.message.orEmpty().lowercase(Locale.US)
        return when {
            "old counter" in message || "oldcounter" in message ->
                SignalASILinkDiagnosticKind.OLD_COUNTER
            "duplicatemessage" in className || "duplicate message" in message ->
                SignalASILinkDiagnosticKind.DUPLICATE_MESSAGE
            else -> SignalASILinkDiagnosticKind.DECRYPT_FAILURE
        }
    }

    internal fun classifyFragmentFailure(error: Throwable): SignalASILinkDiagnosticKind =
        if ("duplicate" in error.message.orEmpty().lowercase(Locale.US)) {
            SignalASILinkDiagnosticKind.CHUNK_DUPLICATE
        } else {
            SignalASILinkDiagnosticKind.FRAGMENT_REJECTED
        }

    @Synchronized
    private fun runtime(context: Context): SignalASILinkDiagnosticLedger =
        ledger ?: SignalASILinkDiagnosticLedger(
            SharedPreferencesSignalASILinkDiagnosticStore(context.applicationContext)
        ).also { ledger = it }
}
