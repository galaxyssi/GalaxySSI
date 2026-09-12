package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.UUID

object GalaxySSILinkDeliveryStore {
    private const val PREFS = "opaque_link_delivery_v2"
    private const val RECOVERY_DATABASE = "opaque_link_peer_recovery_v1"
    private const val KEY_OUTBOX = "outbox"
    private const val KEY_TRANSPORT_EPOCH = "transport_epoch"
    private const val WIRE_PAYLOAD_FILE = "wire_payload_file"
    private const val BLOCKED_BY_ATTACHMENT_TRANSFERS = "blocked_by_attachment_transfers"
    private const val BROKER_ACK_TIMEOUT_MILLIS = "broker_ack_timeout_millis"
    private const val ATTACHMENT_TRANSFER_ID = "attachment_transfer_id"
    private const val FILE_BACKED_WIRE_THRESHOLD_BYTES = 64 * 1024
    private const val MAX_RECOVERABLE_ENVELOPE_BYTES = 64 * 1024
    private const val OUTBOX_DIRECTORY = "opaque-link-outbox-v2"
    private const val RECOVERY_PREFIX = "envelope:"
    private var pendingReplayCursor = ""
    @Volatile private var inboxInstance: GalaxySSILinkInbox? = null
    private val SHA256 = Regex("[a-f0-9]{64}")
    private val WIRE_PAYLOAD_NAME = Regex("[a-f0-9]{64}\\.wire")

    @Volatile
    private var outboxDatabaseInstance: GalaxySSILinkOutboxDatabase? = null

    @Volatile
    private var outboxMigrationChecked = false

    enum class IncomingStageResult { STAGED, PENDING, COMPLETED, INVALID }

    internal fun outboundClientSourceMessageId(payload: JSONObject): Long =
        payload.optString("client_message_id").toLongOrNull()
            ?: payload.optLong("client_message_id", 0L).takeIf { it > 0L }
            ?: payload.optString("source_message_id").toLongOrNull()
            ?: payload.optLong("source_message_id", 0L).takeIf { it > 0L }
            ?: 0L

    data class PendingMessage(
        val messageId: String,
        val topic: String,
        val wirePayload: String,
        val attempts: Int,
        val createdAt: Long,
        val requiresValidatedNetwork: Boolean,
        val clientSourceMessageId: Long,
        val contactId: String,
        val brokerAckTimeoutMillis: Long,
        val attachmentTransferId: String,
        val recoveryFirstAttemptMillis: Long = 0L
    )

    data class ExhaustedMessage(
        val messageId: String,
        val clientSourceMessageId: Long,
        val contactId: String,
        val attempts: Int,
        val attachmentTransferId: String = "",
        val recovering: Boolean = false
    )

    data class PendingIncoming(
        val messageId: String,
        val payload: String,
        val createdAt: Long,
        val peerScope: String,
        val endpointId: String,
        val phone: Boolean
    )

    data class AttachmentDependencyRelease(
        val matchedMessages: Int,
        val releasedMessages: Int
    )

    @Synchronized
    fun ensureTransportEpoch(context: Context, epoch: String): Boolean {
        require(epoch.isNotBlank()) { "Transport epoch is required" }
        val preferences = preferences(context)
        if (preferences.readString(KEY_TRANSPORT_EPOCH, "") == epoch) return false
        clearOutboxFiles(context)
        recoveryDatabase(context).clear()
        outboxDatabase(context).clear()
        preferences.remove(KEY_OUTBOX)
        preferences.writeString(KEY_TRANSPORT_EPOCH, epoch)
        return true
    }

    @Synchronized
    fun enqueue(
        context: Context,
        messageId: String,
        topic: String,
        wirePayload: String,
        requiresValidatedNetwork: Boolean = false,
        blockedByAttachmentTransferIds: Collection<String> = emptyList(),
        clientSourceMessageId: Long = 0L,
        contactId: String = "",
        brokerAckTimeoutMillis: Long = MqttBrokerAckTimeoutPolicy.DEFAULT_TIMEOUT_MILLIS,
        attachmentTransferId: String = "",
        recoverableEnvelope: String = ""
    ) {
        val database = outboxDatabase(context)
        if (database.contains(messageId)) return
        val item = JSONObject()
            .put("message_id", messageId)
            .put("topic", topic)
            .put("status", "queued")
            .put("attempts", 0)
            .put("requires_validated_network", requiresValidatedNetwork)
            .put("client_source_message_id", clientSourceMessageId)
            .put("contact_id", contactId)
            .put(
                BROKER_ACK_TIMEOUT_MILLIS,
                MqttBrokerAckTimeoutPolicy.normalize(brokerAckTimeoutMillis)
            )
            .put("next_attempt_at", System.currentTimeMillis())
            .put("created_at", System.currentTimeMillis())
            .put("updated_at", System.currentTimeMillis())
        attachmentTransferId.lowercase()
            .takeIf { it.matches(SHA256) }
            ?.let { item.put(ATTACHMENT_TRANSFER_ID, it) }
        if (wirePayload.toByteArray(Charsets.UTF_8).size > FILE_BACKED_WIRE_THRESHOLD_BYTES) {
            item.put(WIRE_PAYLOAD_FILE, writeWirePayload(context, messageId, wirePayload))
        } else {
            item.put("wire_payload", wirePayload)
        }
        val dependencies = blockedByAttachmentTransferIds
            .map(String::lowercase)
            .distinct()
            .also { values ->
                require(values.all { it.matches(SHA256) }) {
                    "Attachment transfer dependency is invalid"
                }
            }
        if (dependencies.isNotEmpty()) {
            item.put(BLOCKED_BY_ATTACHMENT_TRANSFERS, JSONArray(dependencies))
        }
        if (recoverableEnvelope.isNotBlank()) {
            recoveryDatabase(context).writeString(recoveryKey(messageId), recoverableEnvelope)
        }
        check(database.insert(item)) { "Encrypted outbox message could not be persisted" }
    }

    internal fun recoverablePeerEnvelope(
        payload: JSONObject,
        applicationEnvelope: JSONObject,
        isDirectPhoneContact: Boolean
    ): String {
        if (!isDirectPhoneContact || payload.optString("type") != "peer_message") return ""
        val encoded = applicationEnvelope.toString()
        return encoded.takeIf {
            it.toByteArray(Charsets.UTF_8).size <= MAX_RECOVERABLE_ENVELOPE_BYTES
        }.orEmpty()
    }

    @Synchronized
    fun reencryptRecoverableMessages(
        context: Context,
        contactId: String,
        topic: String,
        encrypt: (JSONObject) -> JSONObject?
    ): Int {
        if (contactId.isBlank() || topic.isBlank()) return 0
        val values = outboxArray(context)
        val now = System.currentTimeMillis()
        var changed = 0
        for (index in 0 until values.length()) {
            val item = values.optJSONObject(index) ?: continue
            if (item.optString("contact_id") != contactId) continue
            val messageId = item.optString("message_id")
            val encodedEnvelope = recoveryDatabase(context).readString(
                recoveryKey(messageId),
                ""
            )
            val envelope = runCatching { JSONObject(encodedEnvelope) }.getOrNull() ?: continue
            val wirePayload = encrypt(envelope)?.toString() ?: continue
            replaceWirePayload(context, item, messageId, wirePayload)
            item.put("topic", topic)
                .put("status", "queued")
                .put("attempts", 0)
                .put("next_attempt_at", now)
                .put("updated_at", now)
            changed += 1
        }
        if (changed > 0) writeArray(context, KEY_OUTBOX, values)
        return changed
    }

    @Synchronized
    internal fun hasAttachmentDependency(context: Context, transferId: String): Boolean {
        val values = outboxArray(context)
        for (index in 0 until values.length()) {
            val dependencies = values.optJSONObject(index)?.optJSONArray(BLOCKED_BY_ATTACHMENT_TRANSFERS) ?: continue
            if ((0 until dependencies.length()).any { dependencies.optString(it) == transferId }) return true
        }
        return false
    }

    @Synchronized
    fun releaseAttachmentDependency(
        context: Context,
        transferId: String
    ): Int = releaseAttachmentDependencyResult(context, transferId).releasedMessages

    @Synchronized
    fun releaseAttachmentDependencyResult(
        context: Context,
        transferId: String
    ): AttachmentDependencyRelease {
        val normalized = transferId.lowercase()
        if (!normalized.matches(SHA256)) return AttachmentDependencyRelease(0, 0)
        val values = outboxArray(context)
        val now = System.currentTimeMillis()
        var matched = 0
        var released = 0
        var changed = false
        for (index in 0 until values.length()) {
            val item = values.optJSONObject(index) ?: continue
            val dependencies = item.optJSONArray(BLOCKED_BY_ATTACHMENT_TRANSFERS) ?: continue
            val remaining = JSONArray()
            var removed = false
            for (dependencyIndex in 0 until dependencies.length()) {
                val dependency = dependencies.optString(dependencyIndex).lowercase()
                if (dependency == normalized) {
                    removed = true
                } else if (dependency.isNotBlank()) {
                    remaining.put(dependency)
                }
            }
            if (!removed) continue
            matched += 1
            changed = true
            if (remaining.length() == 0) {
                item.remove(BLOCKED_BY_ATTACHMENT_TRANSFERS)
                item.put("status", "queued")
                    .put("next_attempt_at", now)
                    .put("updated_at", now)
                released += 1
            } else {
                item.put(BLOCKED_BY_ATTACHMENT_TRANSFERS, remaining)
            }
        }
        if (changed) writeArray(context, KEY_OUTBOX, values)
        return AttachmentDependencyRelease(matched, released)
    }

    @Synchronized
    fun discardBlockedByAttachmentTransfers(
        context: Context,
        transferIds: Collection<String>
    ): Int {
        val blockedIds = transferIds.map(String::lowercase).toSet()
        if (blockedIds.isEmpty()) return 0
        val source = outboxArray(context)
        val kept = JSONArray()
        var removed = 0
        for (index in 0 until source.length()) {
            val item = source.optJSONObject(index) ?: continue
            val dependencies = item.optJSONArray(BLOCKED_BY_ATTACHMENT_TRANSFERS)
            val blocked = dependencies != null &&
                (0 until dependencies.length()).any {
                    dependencies.optString(it).lowercase() in blockedIds
                }
            if (blocked) {
                deleteOutboxPayload(context, item)
                removed += 1
            } else {
                kept.put(item)
            }
        }
        if (removed > 0) writeArray(context, KEY_OUTBOX, kept)
        return removed
    }

    @Synchronized
    fun markPublished(context: Context, messageId: String) {
        updateOutbox(context, messageId) { item ->
            val attempts = item.optInt("attempts").coerceAtLeast(1)
            item.put("status", "published")
                .put(
                    "next_attempt_at",
                    System.currentTimeMillis() + GalaxySSILinkRetryPolicy.delayMillis(attempts)
                )
                .put("updated_at", System.currentTimeMillis())
        }
    }

    @Synchronized
    fun markAttempt(context: Context, messageId: String) {
        updateOutbox(context, messageId) { item ->
            val attempts = item.optInt("attempts") + 1
            if (!item.has("first_attempt_at")) item.put("first_attempt_at", System.currentTimeMillis())
            val delayMs = GalaxySSILinkRetryPolicy.delayMillis(attempts)
            item.put("status", "publishing")
                .put("attempts", attempts)
                .put("next_attempt_at", System.currentTimeMillis() + delayMs)
                .put("updated_at", System.currentTimeMillis())
        }
    }

    @Synchronized
    fun acknowledge(context: Context, messageId: String) {
        removePendingMessage(context, messageId)
    }

    @Synchronized
    fun discard(context: Context, messageId: String) {
        removePendingMessage(context, messageId)
    }

    @Synchronized
    internal fun discardClientSourceMessages(
        context: Context,
        sourceMessageIds: Collection<Long>
    ): Int {
        val recoveryKeys = mutableListOf<String>()
        val removed = outboxDatabase(context).deleteByClientSourceMessageIds(sourceMessageIds) { item ->
            deleteWirePayload(context, item)
            item.optString("message_id").takeIf(String::isNotBlank)?.let { messageId ->
                recoveryKeys += recoveryKey(messageId)
            }
        }
        recoveryDatabase(context).removeAll(recoveryKeys)
        return removed
    }

    internal fun pendingCount(context: Context): Int = outboxDatabase(context).count()

    @Synchronized
    fun discardAttachmentTransferMessages(context: Context, transferId: String): Int {
        val normalized = transferId.lowercase()
        if (!normalized.matches(SHA256)) return 0
        val source = outboxArray(context)
        val kept = JSONArray()
        var removed = 0
        for (index in 0 until source.length()) {
            val item = source.optJSONObject(index) ?: continue
            if (item.optString(ATTACHMENT_TRANSFER_ID).lowercase() == normalized) {
                deleteOutboxPayload(context, item)
                removed += 1
            } else {
                kept.put(item)
            }
        }
        if (removed > 0) writeArray(context, KEY_OUTBOX, kept)
        return removed
    }

    private fun removePendingMessage(context: Context, messageId: String) {
        if (messageId.isBlank()) return
        outboxDatabase(context).delete(messageId)?.let { deleteOutboxPayload(context, it) }
    }

    @Synchronized
    fun discardExhausted(
        context: Context,
        maxAttempts: Int,
        attachmentMaxAttempts: Int = maxAttempts,
        nowMillis: Long = System.currentTimeMillis(),
        activeMessageIds: Set<String> = emptySet()
    ): List<ExhaustedMessage> {
        require(maxAttempts > 0) { "Maximum delivery attempts must be positive" }
        require(attachmentMaxAttempts >= maxAttempts) {
            "Attachment delivery attempts cannot be lower than the ordinary budget"
        }
        val source = outboxDatabase(context).exhausted(
            maxAttempts,
            attachmentMaxAttempts,
            nowMillis
        )
        val handledTransfers = mutableSetOf<String>()
        val handledSourceMessages = mutableSetOf<Long>()
        val exhausted = buildList {
            for (index in 0 until source.length()) {
                val item = source.optJSONObject(index) ?: continue
                val attempts = item.optInt("attempts")
                val messageId = item.optString("message_id")
                if (messageId in activeMessageIds) continue
                val transferId = item.optString(ATTACHMENT_TRANSFER_ID).lowercase()
                    .takeIf { it.matches(SHA256) }
                    .orEmpty()
                val sourceMessageId = item.optLong("client_source_message_id")
                val contactId = item.optString("contact_id")
                if (transferId.isBlank() &&
                    AgentConnectorResponseStore.hasReceivedDelivery(context, sourceMessageId, contactId)
                ) {
                    removePendingMessage(context, messageId)
                    continue
                }
                if (transferId.isBlank() && AgentDeliveryRetryPolicy.eligible(context, sourceMessageId, contactId) &&
                    AgentDeliveryRetryPolicy.defer(item, maxAttempts, nowMillis)
                ) {
                    outboxDatabase(context).update(messageId) { stored ->
                        for (key in listOf("attempts", "agent_recovery_attempts", "status", "next_attempt_at", "updated_at")) {
                            stored.put(key, item.get(key))
                        }
                    }
                    add(ExhaustedMessage(messageId, sourceMessageId, contactId, attempts, recovering = true))
                    continue
                }
                if (transferId.isNotBlank()) {
                    if (sourceMessageId > 0L) {
                        if (!handledSourceMessages.add(sourceMessageId)) continue
                        discardClientSourceMessages(context, setOf(sourceMessageId))
                    } else {
                        if (!handledTransfers.add(transferId)) continue
                        discardAttachmentTransferMessages(context, transferId)
                        discardBlockedByAttachmentTransfers(context, setOf(transferId))
                    }
                } else {
                    outboxDatabase(context).delete(messageId)?.let {
                        deleteOutboxPayload(context, it)
                    }
                }
                add(
                    ExhaustedMessage(
                        messageId = messageId,
                        clientSourceMessageId = sourceMessageId,
                        contactId = item.optString("contact_id"),
                        attempts = attempts,
                        attachmentTransferId = transferId
                    )
                )
            }
        }
        return exhausted
    }

    internal fun isDeliveryExhausted(
        item: JSONObject,
        maxAttempts: Int,
        attachmentMaxAttempts: Int = maxAttempts,
        nowMillis: Long
    ): Boolean {
        val attemptLimit = if (isRecoverableAttachmentTransfer(item)) {
            attachmentMaxAttempts
        } else {
            maxAttempts
        }
        return item.optInt("attempts") >= attemptLimit &&
            item.optLong("next_attempt_at", nowMillis) <= nowMillis
    }

    @Synchronized
    fun discardRoutes(context: Context, routes: GalaxySSILinkProtocol.Routes): Int {
        inbox(context).forget(peerScope(routes))
        inbox(context).forget("pair:" + peerScope(routes))
        inbox(context).forget("blob:" + peerScope(routes))
        MqttRouteState(context).forgetRoute(peerScope(routes))
        val source = outboxArray(context)
        val discardedTopics = routes.receiveWindow + routes.up
        for (index in 0 until source.length()) {
            val item = source.optJSONObject(index) ?: continue
            if (item.optString("topic") in discardedTopics) deleteOutboxPayload(context, item)
        }
        val kept = retainMessagesOutsideTopics(source, discardedTopics)
        val removed = source.length() - kept.length()
        if (removed > 0) writeArray(context, KEY_OUTBOX, kept)
        return removed
    }

    @Synchronized
    fun pending(
        context: Context,
        allowValidatedNetworkMessages: Boolean = true,
        maxAttempts: Int = Int.MAX_VALUE,
        attachmentMaxAttempts: Int = maxAttempts,
        limit: Int = Int.MAX_VALUE
    ): List<PendingMessage> = pendingFromArray(
        outboxDatabase(context).retryCandidates(
            nowMillis = System.currentTimeMillis(),
            allowValidatedNetworkMessages = allowValidatedNetworkMessages,
            maxAttempts = maxAttempts,
            attachmentMaxAttempts = attachmentMaxAttempts,
            limit = limit
        ),
        System.currentTimeMillis(),
        allowValidatedNetworkMessages,
        maxAttempts,
        attachmentMaxAttempts
    ) { item ->
        item.optString("wire_payload").ifBlank {
            readWirePayload(context, item.optString(WIRE_PAYLOAD_FILE))
        }
    }

    @Synchronized
    fun hasPendingClientSourceMessageId(context: Context, sourceMessageId: Long): Boolean =
        outboxDatabase(context).hasClientSourceMessageId(sourceMessageId)

    internal fun containsClientSourceMessageId(values: JSONArray, sourceMessageId: Long): Boolean {
        if (sourceMessageId <= 0L) return false
        for (index in 0 until values.length()) {
            if (values.optJSONObject(index)
                    ?.optLong("client_source_message_id", 0L) == sourceMessageId
            ) {
                return true
            }
        }
        return false
    }

    @Synchronized
    fun nextRetryDelayMillis(
        context: Context,
        nowMillis: Long = System.currentTimeMillis(),
        allowValidatedNetworkMessages: Boolean = true
    ): Long? = outboxDatabase(context)
        .nextRetryAt(allowValidatedNetworkMessages)
        ?.let { (it - nowMillis).coerceAtLeast(0L) }

    internal fun nextRetryDelayFromArray(
        values: JSONArray,
        nowMillis: Long,
        allowValidatedNetworkMessages: Boolean = true
    ): Long? {
        var earliest: Long? = null
        for (index in 0 until values.length()) {
            val item = values.optJSONObject(index) ?: continue
            if (hasAttachmentDependencies(item)) continue
            if (
                item.optBoolean("requires_validated_network", false) &&
                !allowValidatedNetworkMessages
            ) continue
            val nextAttemptAt = item.optLong("next_attempt_at", nowMillis)
            earliest = minOf(earliest ?: nextAttemptAt, nextAttemptAt)
        }
        return earliest?.let { (it - nowMillis).coerceAtLeast(0L) }
    }

    @Synchronized
    fun makePendingImmediatelyRetryable(context: Context) {
        val now = System.currentTimeMillis()
        outboxDatabase(context).makePendingImmediatelyRetryable(now)
    }

    internal fun pendingFromArray(
        values: JSONArray,
        nowMillis: Long,
        allowValidatedNetworkMessages: Boolean = true,
        maxAttempts: Int = Int.MAX_VALUE,
        attachmentMaxAttempts: Int = maxAttempts,
        wirePayload: (JSONObject) -> String = { it.optString("wire_payload") }
    ): List<PendingMessage> {
        val byRoute = linkedMapOf<String, ArrayDeque<PendingMessage>>()
        for (index in 0 until values.length()) {
            val item = values.optJSONObject(index) ?: continue
            if (hasAttachmentDependencies(item)) continue
            if (
                item.optBoolean("requires_validated_network", false) &&
                !allowValidatedNetworkMessages
            ) continue
            val attemptLimit = if (isRecoverableAttachmentTransfer(item)) {
                attachmentMaxAttempts
            } else {
                maxAttempts
            }
            if (item.optInt("attempts") >= attemptLimit) continue
            if (item.optLong("next_attempt_at") > nowMillis) continue
            val topic = item.optString("topic")
            val pending = PendingMessage(
                item.optString("message_id"),
                topic,
                wirePayload(item),
                item.optInt("attempts"),
                item.optLong("created_at"),
                item.optBoolean("requires_validated_network", false),
                item.optLong("client_source_message_id"),
                item.optString("contact_id"),
                MqttBrokerAckTimeoutPolicy.normalize(
                    item.optLong(
                        BROKER_ACK_TIMEOUT_MILLIS,
                        MqttBrokerAckTimeoutPolicy.DEFAULT_TIMEOUT_MILLIS
                    )
                ),
                item.optString(ATTACHMENT_TRANSFER_ID).lowercase(),
                if (item.optInt("agent_recovery_attempts") > 0) {
                    item.optLong("first_attempt_at", item.optLong("created_at"))
                } else 0L
            )
            byRoute.getOrPut(routeScope(topic)) { ArrayDeque() }.addLast(pending)
        }
        return buildList {
            val activeRoutes = ArrayDeque(byRoute.values)
            while (activeRoutes.isNotEmpty()) {
                val route = activeRoutes.removeFirst()
                add(route.removeFirst())
                if (route.isNotEmpty()) activeRoutes.addLast(route)
            }
        }
    }

    private fun routeScope(topic: String): String = topic

    internal fun recoverableAttachmentTransferId(payload: JSONObject): String =
        payload.optString("transfer_id").lowercase().takeIf {
            payload.optString("type") in setOf(
                "input_attachment_manifest",
                "input_attachment_chunk",
                "input_attachment_blob_offer"
            ) && it.matches(SHA256)
        }.orEmpty()

    private fun isRecoverableAttachmentTransfer(item: JSONObject): Boolean =
        item.optString(ATTACHMENT_TRANSFER_ID).lowercase().matches(SHA256)

    internal fun inbox(context: Context): GalaxySSILinkInbox = inboxInstance ?: synchronized(this) {
        inboxInstance ?: GalaxySSILinkInbox(inboundDatabase(context)).also { inboxInstance = it }
    }

    internal fun peerScope(routes: GalaxySSILinkProtocol.Routes): String =
        "${routes.clientRouteId}|${routes.localFingerprint}|${routes.remoteFingerprint}"

    internal fun stageLocalIncoming(context: Context, scope: String, endpoint: String, payload: JSONObject): IncomingStageResult {
        val clean = JSONObject(payload.toString()).apply { remove(MqttImmutableContent.RECORD_KEY) }
        val accepted = inbox(context).accept(GalaxySSILinkInbox.Peer(scope, endpoint, false),
            payload.getString("message_id"), MqttImmutableContent.hash(clean), payload)
        return when (accepted.stage) {
            GalaxySSILinkInbox.Stage.STORED -> IncomingStageResult.STAGED
            GalaxySSILinkInbox.Stage.PENDING -> IncomingStageResult.PENDING
            GalaxySSILinkInbox.Stage.COMPLETED -> IncomingStageResult.COMPLETED
        }
    }

    @Synchronized
    fun pendingIncoming(context: Context): List<PendingIncoming> {
        val store = inbox(context)
        store.pruneCompleted()
        var rows = store.pending(pendingReplayCursor)
        if (rows.isEmpty() && pendingReplayCursor.isNotEmpty()) rows = store.pending()
        pendingReplayCursor = rows.lastOrNull()?.recordKey.orEmpty()
        return rows.map { PendingIncoming(it.messageId, it.payload, it.createdAt, it.peer.scope, it.peer.endpoint, it.peer.phone) }
    }

    private val inboundDispatch = MqttInboxDispatchGate()

    internal fun beginIncomingDispatch(context: Context, payload: JSONObject): Boolean {
        val key = payload.optString(MqttImmutableContent.RECORD_KEY)
        if (!inboundDispatch.acquire(key)) return false
        return try {
            inbox(context).isPending(payload).also { if (!it) inboundDispatch.release(key) }
        } catch (error: Exception) {
            inboundDispatch.release(key)
            throw error
        }
    }

    internal fun retryIncoming(payload: JSONObject) =
        inboundDispatch.release(payload.optString(MqttImmutableContent.RECORD_KEY))

    fun completeIncoming(context: Context, payload: JSONObject): Boolean =
        inbox(context).complete(payload).also { retryIncoming(payload) }

    @Synchronized
    fun clear(context: Context) {
        clearOutboxFiles(context)
        outboxDatabase(context).clear()
        preferences(context).clear()
        inbox(context).clear()
        inboundDispatch.clear()
        inboundDatabase(context).let { it.removeAll(it.keys("multipath:")) }
        pendingReplayCursor = ""
        recoveryDatabase(context).clear()
        outboxMigrationChecked = true
    }

    private fun updateOutbox(context: Context, messageId: String, block: (JSONObject) -> Unit) {
        outboxDatabase(context).update(messageId, block)
    }

    private fun outboxArray(context: Context): JSONArray = outboxDatabase(context).readAll()

    private fun outboxDatabase(context: Context): GalaxySSILinkOutboxDatabase {
        val database = outboxDatabaseInstance ?: synchronized(this) {
            outboxDatabaseInstance ?: GalaxySSILinkOutboxDatabase(context.applicationContext).also {
                outboxDatabaseInstance = it
            }
        }
        if (!outboxMigrationChecked) synchronized(this) {
            if (!outboxMigrationChecked) {
                val preferences = preferences(context)
                val legacy = preferences.readString(KEY_OUTBOX, "")
                if (legacy.isNotBlank()) {
                    val items = runCatching { JSONArray(legacy) }.getOrDefault(JSONArray())
                    if (items.length() > 0) database.replaceAll(items)
                    preferences.remove(KEY_OUTBOX)
                }
                outboxMigrationChecked = true
            }
        }
        return database
    }

    private fun inboundDatabase(context: Context): AgentEncryptedDatabase =
        AndroidPersistentSignalStore.database(context.applicationContext)

    internal fun transportMetadataDatabase(context: Context): AgentEncryptedDatabase = inboundDatabase(context)

    private fun recoveryDatabase(context: Context): AgentEncryptedDatabase =
        AgentEncryptedDatabase(context.applicationContext, RECOVERY_DATABASE)

    private fun recoveryKey(messageId: String): String = "$RECOVERY_PREFIX$messageId"

    private fun readArray(context: Context, key: String): JSONArray {
        val raw = preferences(context).readString(key, "[]")
        return runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
    }

    private fun writeArray(context: Context, key: String, value: JSONArray) {
        if (key == KEY_OUTBOX) {
            outboxDatabase(context).replaceAll(value)
        } else {
            preferences(context).writeString(key, value.toString())
        }
    }

    private fun preferences(context: Context): AgentEncryptedPreferences =
        AgentEncryptedPreferences(context.applicationContext, PREFS)

    private fun writeWirePayload(context: Context, messageId: String, payload: String): String {
        val directory = outboxDirectory(context)
        val name = MessageDigest.getInstance("SHA-256")
            .digest(messageId.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) } + ".wire"
        val target = File(directory, name)
        val temporary = File(directory, ".$name.tmp")
        temporary.writeText(payload, Charsets.UTF_8)
        check(temporary.renameTo(target)) { "Encrypted outbox payload could not be committed" }
        return name
    }

    private fun replaceWirePayload(
        context: Context,
        item: JSONObject,
        messageId: String,
        payload: String
    ) {
        deleteWirePayload(context, item)
        item.remove("wire_payload")
        item.remove(WIRE_PAYLOAD_FILE)
        if (payload.toByteArray(Charsets.UTF_8).size > FILE_BACKED_WIRE_THRESHOLD_BYTES) {
            item.put(WIRE_PAYLOAD_FILE, writeWirePayload(context, messageId, payload))
        } else {
            item.put("wire_payload", payload)
        }
    }

    private fun deleteOutboxPayload(context: Context, item: JSONObject) {
        deleteWirePayload(context, item)
        recoveryDatabase(context).remove(recoveryKey(item.optString("message_id")))
    }

    private fun readWirePayload(context: Context, name: String): String {
        if (!name.matches(WIRE_PAYLOAD_NAME)) return ""
        val directory = outboxDirectory(context).canonicalFile
        val target = File(directory, name).canonicalFile
        if (!target.path.startsWith(directory.path + File.separator) || !target.isFile) return ""
        return runCatching { target.readText(Charsets.UTF_8) }.getOrDefault("")
    }

    private fun deleteWirePayload(context: Context, item: JSONObject) {
        val name = item.optString(WIRE_PAYLOAD_FILE)
        if (!name.matches(WIRE_PAYLOAD_NAME)) return
        val directory = outboxDirectory(context).canonicalFile
        val target = File(directory, name).canonicalFile
        if (target.path.startsWith(directory.path + File.separator)) target.delete()
    }

    private fun clearOutboxFiles(context: Context) {
        outboxDirectory(context).deleteRecursively()
    }

    private fun outboxDirectory(context: Context): File =
        File(context.applicationContext.filesDir, OUTBOX_DIRECTORY).apply {
            check(mkdirs() || isDirectory) { "Encrypted outbox directory is unavailable" }
        }

    private fun hasAttachmentDependencies(item: JSONObject): Boolean =
        item.optJSONArray(BLOCKED_BY_ATTACHMENT_TRANSFERS)?.length()?.let { it > 0 } == true

    internal fun retainMessagesOutsideTopics(source: JSONArray, discardedTopics: Set<String>): JSONArray {
        if (discardedTopics.isEmpty()) return JSONArray(source.toString())
        val kept = JSONArray()
        for (index in 0 until source.length()) {
            val item = source.optJSONObject(index) ?: continue
            if (item.optString("topic") !in discardedTopics) kept.put(JSONObject(item.toString()))
        }
        return kept
    }
}

internal object GalaxySSILinkDeliveryAckPolicy {
    private const val TRANSPORT_MESSAGE_ID = "transport_message_id"
    private const val CLIENT_SOURCE_MESSAGE_ID = "client_source_message_id"

    fun transportMessageId(payload: JSONObject): String =
        payload.optString(TRANSPORT_MESSAGE_ID)
            .takeIf(::isUuid)
            .orEmpty()

    fun clientSourceMessageId(payload: JSONObject): String =
        payload.optString(CLIENT_SOURCE_MESSAGE_ID)
            .ifBlank { payload.optString("source_message_id").takeUnless(::isUuid).orEmpty() }

    private fun isUuid(value: String): Boolean =
        value.isNotBlank() && runCatching { UUID.fromString(value) }.isSuccess
}

internal object GalaxySSILinkCiphertextReplayPolicy {
    private val ENCRYPTED_FIELDS = listOf(
        "scheme",
        "from",
        "to",
        "signal_type",
        "type",
        "message_type",
        "messageType",
        "body"
    )

    fun digest(wire: JSONObject): String {
        val canonical = buildString {
            ENCRYPTED_FIELDS.forEach { key ->
                if (!wire.has(key)) return@forEach
                val value = wire.opt(key)?.toString().orEmpty()
                append(key.length).append(':').append(key)
                    .append('=').append(value.length).append(':').append(value).append(';')
            }
        }
        return MessageDigest.getInstance("SHA-256")
            .digest(canonical.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
    }
}

internal object GalaxySSILinkRetryPolicy {
    private const val INITIAL_DELAY_MILLIS = 2_000L
    private const val MAX_DELAY_MILLIS = 300_000L

    fun delayMillis(attempt: Int): Long {
        val exponent = (attempt.coerceAtLeast(1) - 1).coerceAtMost(8)
        // Allow the peer receipt round trip before resending a broker-accepted packet.
        return (INITIAL_DELAY_MILLIS shl exponent).coerceIn(30_000L, MAX_DELAY_MILLIS)
    }
}
