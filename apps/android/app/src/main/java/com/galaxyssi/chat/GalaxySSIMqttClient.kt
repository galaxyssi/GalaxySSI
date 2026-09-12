package com.galaxyssi.chat

import com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTraceContext
import com.galaxyssi.chat.voice.metrics.VoiceTraceEvents
import com.galaxyssi.chat.voice.asr.remote.RemoteWhisperNodeRegistry
import com.galaxyssi.chat.metrics.AgentLatencyTelemetry
import com.galaxyssi.chat.metrics.AgentTransportTiming

import android.content.Context
import com.galaxyssi.chat.blob.AndroidBlobTransfers
import com.galaxyssi.chat.blob.AndroidBlobArtifactReceives
import com.galaxyssi.chat.blob.AndroidBlobArtifactCapability
import com.galaxyssi.chat.blob.BlobRelayConfiguration
import com.galaxyssi.chat.blob.BlobRelayConfigurations
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import org.eclipse.paho.client.mqttv3.IMqttActionListener
import org.eclipse.paho.client.mqttv3.IMqttDeliveryToken
import org.eclipse.paho.client.mqttv3.IMqttToken
import org.eclipse.paho.client.mqttv3.MqttMessage
import org.json.JSONObject
import org.json.JSONArray
import java.util.LinkedHashMap
import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

internal object PairingConfirmationDeliveryPolicy {
    fun messageId(suppliedId: String, desktopId: String, clientRouteId: String): String =
        suppliedId.trim().ifBlank { "pairing-confirmed:$desktopId:$clientRouteId" }

    fun needsSessionBootstrap(hasExistingSession: Boolean, routePaired: Boolean = true): Boolean =
        !hasExistingSession || !routePaired

    fun isFirstDelivery(stage: GalaxySSILinkDeliveryStore.IncomingStageResult): Boolean =
        stage == GalaxySSILinkDeliveryStore.IncomingStageResult.STAGED
}

object GalaxySSIMqttClient {
    private const val TAG = "GalaxySSILink"
    private const val MQTT_QOS = 1
    private const val MAX_INLINE_ATTACHMENT_BYTES = 320 * 1024
    private const val PAIRING_CLAIM_MAX_AGE_MILLIS = 9 * 60_000L
    private const val SUBSCRIPTION_RETRY_DELAY_MILLIS = 3_000L
    private const val MAX_EXECUTION_POLICY_PROMPT_CHARS = 24_000
    private const val MAX_FRAGMENT_INFLIGHT = 8
    private const val MAX_FRAGMENT_INFLIGHT_PER_TRANSFER = 4
    private const val MAX_OUTBOX_RETRY_BATCH = 4
    private const val MAX_OUTBOX_DELIVERY_ATTEMPTS = 6
    private const val MAX_ATTACHMENT_OUTBOX_DELIVERY_ATTEMPTS = 9
    private const val MIN_OUTBOX_RETRY_DELAY_MILLIS = 250L
    private const val MAX_OUTBOX_RETRY_DELAY_MILLIS = 30_000L
    private const val ATTACHMENT_REQUEST_RETRY_MILLIS = 15_000L

    private data class PendingPairingClaim(
        val desktopId: String,
        val topic: String,
        val wirePayload: String,
        val queuedAtMillis: Long
    )

    private data class PendingOpaquePacket(
        val topic: String,
        val wirePayload: String,
        val purpose: String,
        val expiresAtMillis: Long,
        val receiveTopics: Set<String>
    )

    private data class OutboundFragmentTransfer(
        val key: String,
        val durableMessageId: String?,
        val topic: String,
        val packets: List<String>,
        val purpose: String,
        val brokerAckTimeoutMillis: Long,
        val timing: AgentTransportTiming.Attempt? = null,
        val queuedAtElapsedMillis: Long = SystemClock.elapsedRealtime(),
        var nextPacketIndex: Int = 0,
        var outstanding: Int = 0,
        var failed: Boolean = false,
        val publications: List<MqttPoolTransport.Publication> = emptyList()
    )

    private val approvedPhoneDecisionReplayScheduled = AtomicBoolean(false)
    private val initialOutboxRecoveryPrepared = AtomicBoolean(false)
    private val inboundReplayScheduled = AtomicBoolean(false)
    private val inboundReplayTimerLock = Any()
    private val inboundReplayRetryRunnable = Runnable { schedulePendingIncomingReplay() }
    private val inboundReplayExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "galaxyssi-inbound-replay").apply { isDaemon = true }
    }
    private data class InboundPacket(val topic: String, val payload: ByteArray, val enqueuedAt: Long,
                                   val ingress: MqttBrokerPool.Ingress)
    private val inboundBindings = MqttInboundBindings()
    private val inboundMqttPool = MqttInboundRoutePool<InboundPacket>(
        process = { packet ->
            if (BuildConfig.DEBUG) Log.d("GalaxySSILatency",
                "mqtt_inbound stage=queue ms=${android.os.SystemClock.elapsedRealtime() - packet.enqueuedAt} bytes=${packet.payload.size}")
            timedInbound("handle") { handleIncoming(packet.topic, packet.payload, packet.ingress) }
        },
        onFailure = { Log.e(TAG, "MQTT inbound handler failed type=${it.javaClass.simpleName}") }
    )
    private val inboundAdmissionLogAt = java.util.concurrent.atomic.AtomicLong()
    private val attachmentTransferExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "galaxyssi-link-attachments").apply { isDaemon = true }
    }
    private val attachmentControlInbox = AttachmentControlInbox(attachmentTransferExecutor)
    private val outboxDispatchExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "galaxyssi-link-outbox").apply { isDaemon = true }
    }
    private val brokerCompletionExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "galaxyssi-link-broker-completion").apply { isDaemon = true }
    }
    private val outboxDispatchRunning = AtomicBoolean(false)
    private val retryHandler = Handler(Looper.getMainLooper())
    private val subscriptionRecoveryState = MqttSubscriptionRecoveryState()
    private val subscriptionCoordinator = GalaxySSILinkSubscriptionCoordinator(MQTT_QOS, ::completeSubscriptionAttempt)
    private val subscriptionRetryScheduled = AtomicBoolean(false)
    private val subscriptionRefreshScheduled = AtomicBoolean(false)
    private val retryRunnable = object : Runnable {
        override fun run() {
            if (connected) dispatchPendingMessages()
        }
    }
    private val brokerAckWatchdog = MqttBrokerAckWatchdog(
        MqttBrokerAckTimeoutPolicy.DEFAULT_TIMEOUT_MILLIS
    )
    private val brokerDeliveryRegistration = MqttBrokerDeliveryRegistration()
    private val brokerTransportGeneration = AtomicLong()
    private val transportReceiptAttempts = ConcurrentHashMap<Int, LinkTransportReceiptAttempt>()
    private val brokerAckWatchdogRunnable = Runnable {
        val timedOutAgeMillis = brokerAckWatchdog.oldestTimedOutPendingAgeMillis(
            SystemClock.elapsedRealtime()
        )
        if (connected && timedOutAgeMillis != null) {
            recoverStalledTransport(timedOutAgeMillis)
        } else {
            scheduleBrokerAckWatchdog()
        }
    }
    private val subscriptionRetryRunnable = Runnable {
        if (subscriptionRetryScheduled.compareAndSet(true, false)) subscribe()
    }
    private val topicRotationRefreshRunnable = object : Runnable {
        override fun run() {
            if (!connected) return
            subscribe()
            scheduleTopicRotationRefresh()
        }
    }
    private val pairingClaimRetryRunnable = Runnable { flushPendingPairingClaim() }
    private val listeners = CopyOnWriteArraySet<Listener>()
    private val pendingOpaquePackets = CopyOnWriteArrayList<PendingOpaquePacket>()
    private val deliveryMessageIds = ConcurrentHashMap<Int, String>()
    private val attachmentRetryRunnables = ConcurrentHashMap<String, Runnable>()
    private val outboxDispatchLock = Any()
    private val fragmentTransferLock = Any()
    private val fragmentTransfers = LinkedHashMap<String, OutboundFragmentTransfer>()
    private val fragmentTransferKeysByMid = HashMap<Int, String>()
    private var fragmentInflight = 0
    private val pairingClaimLock = Any()
    @Volatile private var client: MqttPoolTransport? = null
    @Volatile private var peerRoutes: MqttPeerRoutes? = null
    private val poolStateRefreshScheduled = AtomicBoolean()
    private val poolRecoveryRequested = AtomicBoolean()
    private var pendingPairingClaim: PendingPairingClaim? = null
    private var lastPairingClaimAttemptAt = 0L
    @Volatile private var connected = false
    @Volatile private var secureReady = false
    @Volatile private var lastConnectorStatusRequestAt = 0L
    @Volatile private var lastCapabilityManifestRequestAt = 0L
    @Volatile private var appContext: Context? = null

    interface Listener {
        fun onConnectionChanged(isConnected: Boolean) = Unit
        fun onSecureChannelChanged(isReady: Boolean) = Unit
        fun onMessage(payload: String) = Unit
        fun onDeliveryFailed(sourceMessageId: Long, contactId: String, reason: String) = Unit
        fun onPcInfo(ip: String, port: Int) = Unit
    }

    fun addListener(listener: Listener) {
        listeners.add(listener)
        listener.onConnectionChanged(connected)
        listener.onSecureChannelChanged(secureReady)
        schedulePendingIncomingReplay()
    }

    fun removeListener(listener: Listener) {
        listeners.remove(listener)
    }

    fun isConnected(): Boolean = connected

    fun isRequestReplyReady(): Boolean = connected && peerRoutes?.anyReady() == true

    fun isSecureReady(): Boolean = secureReady

    fun refreshOpaqueSubscriptions(context: Context) {
        bindApplicationContext(context)
        if (client?.isConnected == true) subscribe() else connect(context)
    }

    internal fun applicationContext(): Context? = appContext

    internal fun bindApplicationContext(context: Context) {
        appContext = context.applicationContext
    }

    fun completeIncomingDelivery(context: Context, payload: String) {
        val value = runCatching { JSONObject(payload) }.getOrNull() ?: return
        GalaxySSILinkDeliveryStore.completeIncoming(context.applicationContext, value)
    }

    fun retryIncomingDelivery(payload: String) {
        val value = runCatching { JSONObject(payload) }.getOrNull() ?: return
        retryStoredIncoming(value)
    }

    fun forgetSecureChannel() {
        val context = appContext
        setSecureReady(context != null && GalaxySSILinkProtocol.allServerLinks(context).any { it.paired })
    }

    fun unsubscribeServer(context: Context, desktopId: String) {
        val mqtt = client ?: return
        if (!mqtt.isConnected) return
        val link = GalaxySSILinkProtocol.serverLink(context, desktopId) ?: return
        subscriptionCoordinator.unsubscribe(
            mqtt,
            link.routes.receiveWindow,
            "desktop_${desktopId.takeLast(8)}"
        )
    }

    fun publishServerRevocation(context: Context, desktopId: String): Boolean =
        GalaxySSIMqttDesktopControl.publishServerRevocation(context, desktopId)

    fun publishDesktopToolCall(desktopId: String, payload: JSONObject): Boolean =
        GalaxySSIMqttDesktopControl.publishToolCall(desktopId, payload)

    fun publishRemoteWhisperPacket(desktopId: String, payload: JSONObject): Boolean =
        GalaxySSIMqttDesktopControl.publishRemoteWhisperPacket(desktopId, payload)

    fun publishDesktopExecutorRequest(
        desktopId: String,
        payload: JSONObject,
        durable: Boolean = true
    ): Boolean = GalaxySSIMqttDesktopControl.publishExecutorRequest(desktopId, payload, durable)

    fun publishDesktopControlAuthorizationsRequest(desktopId: String): Boolean =
        GalaxySSIMqttDesktopControl.requestAuthorizations(desktopId)

    fun publishDesktopControlRevoke(desktopId: String, authorizationId: String): Boolean =
        GalaxySSIMqttDesktopControl.revokeAuthorization(desktopId, authorizationId)

    fun requestDesktopEvolutionTasks(desktopId: String): Boolean =
        GalaxySSIMqttDesktopControl.requestEvolutionTasks(desktopId)

    fun createDesktopEvolutionTask(
        desktopId: String,
        problem: String,
        scope: List<String>,
        acceptance: List<String>,
        reproductionSteps: List<String> = emptyList(),
        riskLevel: String = "medium",
        maxAttempts: Int = 3,
        agentId: String = "codex"
    ): Boolean = GalaxySSIMqttDesktopControl.createEvolutionTask(
        desktopId,
        problem,
        scope,
        acceptance,
        reproductionSteps,
        riskLevel,
        maxAttempts,
        agentId
    )

    fun controlDesktopEvolutionTask(
        desktopId: String,
        taskId: String,
        action: String,
        approvalHash: String = ""
    ): Boolean {
        return GalaxySSIMqttDesktopControl.controlEvolutionTask(
            desktopId, taskId, action, approvalHash
        )
    }

    fun publishDesktopToolCancel(
        desktopId: String,
        callId: String,
        taskId: String,
        conversationId: String
    ): Boolean = GalaxySSIMqttDesktopControl.publishToolCancel(
        desktopId, callId, taskId, conversationId
    )

    fun requestDesktopArtifactDownload(block: AgentRichBlock): Boolean =
        GalaxySSIMqttDesktopControl.requestArtifactDownload(block)

    internal fun publishDesktopControlPayload(
        desktopId: String,
        payload: JSONObject,
        durable: Boolean = true,
        clientRouteId: String = ""
    ): Boolean {
        val context = appContext ?: return false
        val link = if (clientRouteId.isBlank()) {
            GalaxySSILinkProtocol.serverLink(context, desktopId)
        } else {
            GalaxySSILinkProtocol.serverLink(context, desktopId, clientRouteId)
        } ?: return false
        val mqtt = client ?: return false
        if (!mqtt.isConnected || !link.paired || !GalaxySSICrypto.hasDesktopSession(context, desktopId)) return false
        payload.put("desktop_id", desktopId)
        val envelope = runCatching {
            GalaxySSILinkProtocol.makeEnvelope(payload, GalaxySSICrypto.localGalaxySSIId(), desktopId)
        }.getOrNull() ?: return false
        val encrypted = GalaxySSICrypto.encryptPayloadForDesktop(desktopId, envelope) ?: return false
        val messageId = envelope.getString("message_id")
        val wirePayload = encrypted.toString()
        if (durable) {
            GalaxySSILinkDeliveryStore.enqueue(context, messageId, link.routes.control, wirePayload,
                receiptRoutes = link.routes, transportTraffic = MqttTrafficPolicy.classify(payload))
            if (peerRoutes?.readyForTopic(link.routes.control) != true) {
                scheduleOutboxRetries()
                return true
            }
            GalaxySSILinkDeliveryStore.markAttempt(context, messageId)
        }
        if (!publishWirePayload(
            mqtt,
            link.routes.control,
            wirePayload,
            "desktop_control",
            messageId, transportTraffic = MqttTrafficPolicy.classify(payload)
        )) {
            if (durable) {
                scheduleOutboxRetries()
                return true
            }
            return false
        }
        return true
    }

    fun verifyPcIdentityFromQr(contents: String): Boolean =
        GalaxySSIMqttDesktopControl.verifyPcIdentityFromQr(contents)

    @Synchronized fun connect(context: Context) {
        prepareReliableQueue(context)
        val current = client
        if (current != null) {
            current.start()
            return
        }
        lateinit var mqtt: MqttPoolTransport
        mqtt = MqttPoolTransport(object : MqttPoolTransport.Listener {
            override fun onConnectionChanged(connected: Boolean) {
                outboxDispatchExecutor.execute {
                    if (client !== mqtt) return@execute
                    if (mqtt.isConnected) onTransportConnected(context.applicationContext) else {
                        invalidateSubscriptions()
                        clearWireTransportState()
                        setConnected(false)
                        setSecureReady(false)
                        retryHandler.removeCallbacks(retryRunnable)
                    }
                }
            }
            override fun onSubscriptionsChanged() { schedulePoolStateRefresh() }
            override fun onPacket(ingress: MqttBrokerPool.Ingress, topic: String, payload: ByteArray) {
                if (client !== mqtt) return
                val scope = inboundBindings.scope(topic) ?: return
                val enqueuedAt = SystemClock.elapsedRealtime()
                val admission = inboundMqttPool.submit(scope, InboundPacket(topic, payload, enqueuedAt, ingress), payload.size)
                if (admission != MqttInboundRoutePool.Admission.ACCEPTED) {
                    val previous = inboundAdmissionLogAt.get()
                    if (enqueuedAt - previous >= 5_000 && inboundAdmissionLogAt.compareAndSet(previous, enqueuedAt))
                        Log.w(TAG, "MQTT inbound queue deferred packet reason=$admission")
                }
            }
            override fun onPublished(token: IMqttDeliveryToken, accepted: Boolean) {
                if (client !== mqtt) return
                if (accepted) handleBrokerDeliveryComplete(context.applicationContext, token.messageId)
                else handleBrokerDeliveryFailure(context.applicationContext, token.messageId)
            }
            override fun onMaintenanceFailure(error: Throwable) {
                Log.w(TAG, "MQTT maintenance deferred type=${error.javaClass.simpleName}")
            }
        }, classify = { topic, payload -> peerRoutes?.classify(topic, payload) })
        val routes = MqttPeerRoutes(mqtt, MqttRouteState(context.applicationContext), GalaxySSILinkProtocol::sealWirePacket,
            onReady = { schedulePoolStateRefresh(recover = true) },
            onFailure = { Log.w(TAG, "MQTT resume deferred type=${it.javaClass.simpleName}") },
            onChanged = { schedulePoolStateRefresh() })
        client = mqtt
        peerRoutes = routes
        mqtt.onTick = { routes.maintenance() }
        outboxDispatchExecutor.execute {
            refreshPoolBindings(context.applicationContext)
            if (context.getSystemService(android.net.ConnectivityManager::class.java).activeNetwork == null)
                mqtt.networkUnavailable()
            mqtt.start()
        }
    }

    private fun refreshPoolBindings(context: Context): AndroidMqttPeerBindings.Snapshot =
        AndroidMqttPeerBindings.load(context).also { peerRoutes?.replace(it.bindings) }

    private fun schedulePoolStateRefresh(recover: Boolean = false) {
        if (recover) poolRecoveryRequested.set(true)
        if (!poolStateRefreshScheduled.compareAndSet(false, true)) return
        outboxDispatchExecutor.execute {
            poolStateRefreshScheduled.set(false)
            val context = appContext ?: return@execute
            val requested = poolRecoveryRequested.getAndSet(false)
            val wasReady = secureReady
            setSecureReady(isRequestReplyReady())
            flushPendingPairingClaim()
            flushPendingOpaquePackets()
            if (secureReady && (requested || !wasReady)) {
                GalaxySSILinkDeliveryStore.makePendingImmediatelyRetryable(context)
                AndroidAgentRecoveryWake.connectionChanged(context, true)
                requestMissingSignalSessions(context)
                requestConnectorStatuses(context)
                dispatchPendingMessages()
                scheduleOutboxRetries()
            }
        }
    }

    private fun handleResume(routes: GalaxySSILinkProtocol.Routes, wire: JSONObject, ingress: MqttBrokerPool.Ingress): Boolean {
        if (wire.optString("type") !in setOf("link_resume", "link_resume_ack")) return false
        val scope = GalaxySSILinkDeliveryStore.peerScope(routes)
        peerRoutes?.handleVerified(scope, wire, ingress,
            listOf(scope, routes.localFingerprint.lowercase(), routes.remoteFingerprint.lowercase(), routes.linkSecret))
        return true
    }

    private fun handleTransportReceipt(routes: GalaxySSILinkProtocol.Routes, wire: JSONObject,
        ingress: MqttBrokerPool.Ingress, endpoint: String, phone: Boolean = false): Boolean {
        val context = appContext ?: return false
        return AndroidMqttDelivery.receiveReceipt(context, routes, wire, ingress, peerRoutes) { receipt ->
            AgentLatencyTelemetry.transport.received(endpoint, receipt.getString("transport_message_id"))
            retryHandler.post { scheduleOutboxRetries() }
            if (!phone) notifyMessageListeners(receipt.put("desktop_id", endpoint))
        }
    }

    private fun publishBootstrap(mqtt: MqttPoolTransport, topic: String, wire: String, receiveTopics: Set<String>): Boolean {
        val hash = MqttRouteAdvertisement.sha256(wire)
        var submitted = false
        mqtt.readyPathGenerations(receiveTopics).keys.forEach { broker ->
            runCatching {
                mqtt.publish(topic, mqttMessage(wire), publication = MqttPoolTransport.Publication(
                    "pairing", hash, hash, MqttMultipathPolicy.Traffic.CONTROL, receiveTopics,
                    bootstrap = true, preferredBroker = broker))
            }.onSuccess { if (it.exception == null) submitted = true }
        }
        return submitted
    }

    internal fun prepareReliableQueue(context: Context) {
        val applicationContext = context.applicationContext
        appContext = applicationContext
        GalaxySSICrypto.initialize(applicationContext)
        schedulePendingIncomingReplay()
    }

    fun connectAfterNetworkAvailable(context: Context) {
        val network = context.getSystemService(android.net.ConnectivityManager::class.java).activeNetwork ?: return
        client?.networkAvailable(network.toString())
        if (client?.isConnected == true) {
            GalaxySSILinkDeliveryStore.makePendingImmediatelyRetryable(context)
            dispatchPendingMessages()
            return
        }
        connect(context)
    }

    fun waitForNetwork(context: Context) {
        if (context.getSystemService(android.net.ConnectivityManager::class.java).activeNetwork != null) return
        client?.networkUnavailable()
    }

    fun reconnect(context: Context) {
        client?.let { it.networkAvailable(); it.repair(); refreshOpaqueSubscriptions(context) } ?: connect(context)
    }

    fun publishUserMessage(
        content: String,
        contactId: String = "hermes",
        topicOverride: String? = null,
        clientMessageId: Long? = null,
        deliveryTrace: org.json.JSONArray? = null,
        conversationId: String = "",
        turnId: String = "",
        taskId: String = "",
        executionMode: AgentTaskExecutionMode? = null,
        connectorTaskMode: String = "",
        executionPolicyPrompt: String = "",
        agentModelId: String = "",
        agentReasoningEffort: AgentModelReasoningEffort = AgentModelReasoningEffort.AUTO,
        traceId: String = VoiceLatencyTraceContext.currentTraceId(),
        runId: String = "",
        agentInstanceId: String = "",
        teamId: String = "",
        agentTeamMessage: Boolean = false,
        trustedBackgroundCognition: Boolean = false
    ): Boolean = publishUserMessageResult(
        content = content,
        contactId = contactId,
        topicOverride = topicOverride,
        clientMessageId = clientMessageId,
        deliveryTrace = deliveryTrace,
        conversationId = conversationId,
        turnId = turnId,
        taskId = taskId,
        runId = runId,
        executionMode = executionMode,
        connectorTaskMode = connectorTaskMode,
        executionPolicyPrompt = executionPolicyPrompt,
        agentModelId = agentModelId,
        agentReasoningEffort = agentReasoningEffort,
        traceId = traceId,
        agentInstanceId = agentInstanceId,
        teamId = teamId,
        agentTeamMessage = agentTeamMessage,
        trustedBackgroundCognition = trustedBackgroundCognition
    ).accepted

    internal fun publishUserMessageResult(
        content: String,
        contactId: String = "hermes",
        topicOverride: String? = null,
        clientMessageId: Long? = null,
        deliveryTrace: org.json.JSONArray? = null,
        conversationId: String = "",
        turnId: String = "",
        taskId: String = "",
        executionMode: AgentTaskExecutionMode? = null,
        connectorTaskMode: String = "",
        executionPolicyPrompt: String = "",
        agentModelId: String = "",
        agentReasoningEffort: AgentModelReasoningEffort = AgentModelReasoningEffort.AUTO,
        traceId: String = VoiceLatencyTraceContext.currentTraceId(),
        runId: String = "",
        agentInstanceId: String = "",
        teamId: String = "",
        agentTeamMessage: Boolean = false,
        trustedBackgroundCognition: Boolean = false
    ): MqttPublishResult {
        val publishStartedAt = SystemClock.elapsedRealtime()
        val publishStartedNs = SystemClock.elapsedRealtimeNanos()
        var previousStageAt = publishStartedAt
        fun recordPublishStage(stage: String, details: String = "") {
            val now = SystemClock.elapsedRealtime()
            Log.i(
                "GalaxySSILatency",
                "mqtt_publish stage=$stage delta_ms=${now - previousStageAt} " +
                    "total_ms=${now - publishStartedAt}${details.takeIf(String::isNotBlank)?.let { " $it" }.orEmpty()}"
            )
            previousStageAt = now
        }
        val context = appContext
        val resolvedConversationId = AgentTaskIdentityPolicy.conversationId(
            contactId,
            conversationId
        )
        val resolvedTurnId = AgentTaskIdentityPolicy.turnId(clientMessageId, turnId)
        val resolvedTaskId = AgentTaskIdentityPolicy.taskId(
            ownerId = GalaxySSICrypto.localGalaxySSIId(),
            contactId = contactId,
            sourceMessageId = clientMessageId,
            conversationId = resolvedConversationId,
            turnId = resolvedTurnId,
            requested = taskId
        )
        context?.let {
            com.galaxyssi.chat.metrics.AgentLatencyTelemetry.publishStarted(
                it, resolvedTaskId, resolvedTurnId, publishStartedNs
            )
        }
        val configuredExecutionMode = context
            ?.let(::SharedPreferencesAgentSafetySettingsStore)
            ?.load()
            ?.taskExecutionMode
            ?: AgentTaskExecutionMode.AUTO_COMPLETE
        val boundedExecutionPolicyPrompt = executionPolicyPrompt.trim()
            .take(MAX_EXECUTION_POLICY_PROMPT_CHARS)
        val resolvedExecutionMode = executionMode ?: AgentTaskExecutionModePolicy.resolve(
            boundedExecutionPolicyPrompt.ifBlank { content },
            configuredExecutionMode
        ).mode
        val taskBudget = context
            ?.let(::AgentTaskBudgetStore)
            ?.load()
            ?: AgentTaskBudget.forProfile(AgentTaskBudgetProfile.ADAPTIVE)
        val payload = JSONObject()
            .put("type", "text")
            .put("content", content)
            .put("contact_id", contactId)
            .put("task_id", resolvedTaskId)
            .put("conversation_id", resolvedConversationId)
            .put("turn_id", resolvedTurnId)
            .put("execution_mode", resolvedExecutionMode.wireValue)
            .put("task_budget", AgentTaskBudgetJsonCodec.encode(taskBudget))
            .put("time", System.currentTimeMillis())
        connectorTaskMode.trim().takeIf(String::isNotBlank)?.let {
            payload.put("connector_task_mode", it.take(96))
        }
        boundedExecutionPolicyPrompt.takeIf(String::isNotBlank)?.let {
            payload.put("execution_policy_prompt", it)
        }
        AgentInvocationRequestJsonCodec.encode(agentModelId, agentReasoningEffort)?.let {
            payload.put("agent_invocation", it)
        }
        recordPublishStage("payload_ready", "chars=${content.length}")
        runId.trim().takeIf(String::isNotBlank)?.let { payload.put("run_id", it) }
        agentInstanceId.trim()
            .takeIf { it.matches(Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,95}")) }
            ?.let { payload.put("agent_instance_id", it) }
        teamId.trim()
            .takeIf { it.matches(Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")) }
            ?.let { payload.put("team_id", it) }
        if (agentTeamMessage) payload.put("agent_team_message", true)
        val resolvedTraceId = traceId.trim().takeIf { it.matches(Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")) }
            .orEmpty()
        if (resolvedTraceId.isNotBlank()) {
            payload
                .put("trace_id", resolvedTraceId)
                .put("voice_session_id", resolvedTraceId)
            context?.let {
                VoiceLatencyTelemetry.record(
                    it,
                    resolvedTraceId,
                    VoiceTraceEvents.AGENT_RUN_CREATE_STARTED,
                    mapOf(
                        "agent_provider" to contactId.substringAfterLast(':').ifBlank { "remote_agent" },
                        "transport" to "galaxyssi_link"
                    ),
                    once = true
                )
            }
        }
        val sourceAttachments = context
            ?.let { AgentTurnAttachmentRegistry.get(resolvedTurnId) }
            .orEmpty()
        val disclosure = context?.takeIf { usesPcConnectorTunnel(contactId) }?.let {
            AgentDataDisclosureLedger.beginDesktopRequest(
                context = it,
                contactId = contactId,
                text = content,
                attachments = sourceAttachments,
                conversationId = resolvedConversationId,
                taskId = resolvedTaskId,
                turnId = resolvedTurnId
            )
        }
        recordPublishStage("disclosure_ready", "attachments=${sourceAttachments.size}")
        if (disclosure?.allowed == false) return MqttPublishResult.FAILED
        fun disclosureFailed(reason: String): MqttPublishResult {
            if (context != null && disclosure != null) {
                AgentDataDisclosureLedger.update(
                    context,
                    disclosure,
                    AgentDisclosureStatus.FAILED,
                    reason
                )
            }
            return MqttPublishResult.FAILED
        }
        fun disclosureCompleted(result: MqttPublishResult): MqttPublishResult {
            context?.let {
                com.galaxyssi.chat.metrics.AgentLatencyTelemetry.record(
                    it, resolvedTaskId, "phone_request_queued",
                    outcome = if (result.accepted) "completed" else "failed"
                )
            }
            if (context != null && disclosure != null) {
                AgentDataDisclosureLedger.update(
                    context,
                    disclosure,
                    when (result) {
                        MqttPublishResult.PUBLISHED -> AgentDisclosureStatus.SENT
                        MqttPublishResult.QUEUED -> AgentDisclosureStatus.QUEUED
                        MqttPublishResult.FAILED -> AgentDisclosureStatus.FAILED
                    },
                    if (result == MqttPublishResult.FAILED) "GalaxySSI Link publish failed" else ""
                )
            }
            return result
        }
        if (context != null) {
            val policy = LanguagePolicySettings.get(context)
            payload
                .put("response_language", LanguagePolicySettings.resolve(policy.responseLanguage))
                .put("response_language_preference", policy.responseLanguage)
        }
        clientMessageId?.let { payload.put("client_message_id", it) }
        var outboundAttachments: List<AgentPreparedOutboundAttachment> = emptyList()
        if (context != null) {
            val attachments = sourceAttachments
            val mediaProfile = AgentMediaNetworkDetector.detect(context)
            if (attachments.isNotEmpty() && usesPcConnectorTunnel(contactId)) {
                val desktopId = AppStore.desktopIdForContact(context, contactId)
                val link = GalaxySSILinkProtocol.serverLink(context, desktopId)
                    ?: return disclosureFailed("No paired Desktop route is available")
                outboundAttachments = runCatching {
                    AgentOutboundAttachmentTransferStore.prepare(
                        context = context,
                        scope = AgentAttachmentTransferScope(
                            contactId = contactId,
                            desktopId = desktopId,
                            clientRouteId = link.routes.clientRouteId,
                            conversationId = resolvedConversationId,
                            taskId = resolvedTaskId,
                            turnId = resolvedTurnId,
                            clientMessageId = clientMessageId
                        ),
                        attachments = attachments,
                        mediaProfile = mediaProfile
                    )
                }.onFailure {
                    Log.e(TAG, "Agent attachment transfer preparation failed", it)
                }.getOrNull() ?: return disclosureFailed("Attachment transfer preparation failed")
                payload.put(
                    "attachments",
                    JSONArray(outboundAttachments.map(AgentPreparedOutboundAttachment::descriptor))
                )
            } else {
                GalaxySSIMqttAttachmentEncoder.encodeInline(
                    context,
                    attachments,
                    mediaProfile,
                    MAX_INLINE_ATTACHMENT_BYTES,
                    taskId = resolvedTaskId
                )
                    .takeIf { it.length() > 0 }
                    ?.let { payload.put("attachments", it) }
            }
            if (attachments.any(GalaxySSIMqttAttachmentEncoder::isTransportMedia)) {
                payload
                    .put("media_network_profile", mediaProfile.id)
                    .put("defer_media_upload", mediaProfile.deferMediaUpload)
            }
        }
        recordPublishStage("metadata_ready")
        deliveryTrace?.let { payload.put("delivery_trace", it) }
        if (context != null) {
            AppStore.contactById(context, contactId)?.let { contact ->
                payload
                    .put("agent_id", contact.optString("agent_id").ifBlank { AppStore.agentIdForContact(context, contactId) })
                    .put("desktop_id", contact.optString("desktop_id"))
                    .put("desktop_name", contact.optString("desktop_name"))
            }
        }
        val topic = topicOverride ?: outgoingTopic(contactId)
        if (outboundAttachments.isNotEmpty()) {
            val activeContext = context
                ?: return disclosureFailed("Attachment transfer context is unavailable")
            val blobIds = mutableSetOf<String>()
            try {
                outboundAttachments.forEach { if (AndroidBlobTransfers.register(activeContext, it)) blobIds.add(it.transferId) }
            } catch (error: Exception) {
                AndroidBlobTransfers.cancel(activeContext, blobIds)
                AgentOutboundAttachmentTransferStore.discard(activeContext, outboundAttachments.map { it.transferId })
                return disclosureFailed("Attachment transfer journal could not be saved")
            }
            val queuedTask = synchronized(outboxDispatchLock) {
                for (attachmentStep in AgentAttachmentPublishOrder.initialSteps(outboundAttachments.filterNot { it.transferId in blobIds })) {
                    if (!publishJsonResult(
                            attachmentStep.payload(),
                            topic,
                            contactId,
                            queueOnly = true,
                            deferQueuedDispatch = true
                        ).accepted
                    ) return@synchronized MqttPublishResult.FAILED
                }
                publishJsonResult(
                    payload,
                    topic,
                    contactId,
                    queueOnly = true,
                    blockedByAttachmentTransferIds = outboundAttachments.map { it.transferId },
                    deferQueuedDispatch = true
                )
            }
            if (!queuedTask.accepted) {
                AndroidBlobTransfers.cancel(activeContext, blobIds)
                AgentOutboundAttachmentTransferStore.discard(
                    activeContext,
                    outboundAttachments.map { it.transferId }
                )
                return disclosureFailed("Attachment transfer and Agent task could not be queued")
            }
            AndroidBlobTransfers.activate(activeContext, blobIds)
            if (client?.isConnected != true) connect(activeContext)
            scheduleOutboxRetries()
            return disclosureCompleted(queuedTask).also {
                recordPublishStage("queued_with_attachments", "result=${it.name}")
            }
        }
        val publishResult = publishJsonResult(
            payload,
            topic,
            contactId,
            trustedBackgroundCognitionAuthorized = trustedBackgroundCognition
        )
        recordPublishStage("transport_accepted", "result=${publishResult.name}")
        return disclosureCompleted(publishResult).also {
            recordPublishStage("audit_completed", "result=${it.name}")
        }
    }

    internal fun publishPeerMessageResult(
        content: String,
        contactId: String,
        topicOverride: String? = null,
        clientMessageId: Long? = null,
        deliveryTrace: JSONArray? = null,
        attachments: List<AgentInputAttachment> = emptyList(),
        messageKind: String = "text",
        durationMillis: Long = 0L,
        dispatchQueued: Boolean = true
    ): MqttPublishResult {
        val context = appContext ?: return MqttPublishResult.FAILED
        val message = PeerChatTransport.prepare(context, content, contactId, topicOverride,
            clientMessageId, deliveryTrace, attachments, messageKind, durationMillis)
            ?: return MqttPublishResult.FAILED
        val prepared = message.attachments
        val payload = message.payload
        val topic = message.topic
        if (prepared.isEmpty()) {
            val queued = publishJsonResult(
                payload,
                topic,
                contactId,
                queueOnly = true,
                deferQueuedDispatch = true
            )
            if (queued.accepted && dispatchQueued) {
                if (client?.isConnected != true) connect(context)
                dispatchPendingMessages()
            }
            return queued
        }
        prepared.forEach { transfer ->
            notifyMessageListeners(
                PeerAttachmentTransferProgress.event(
                    transfer,
                    contactId,
                    "outbound",
                    0,
                    PeerAttachmentTransferProgress.STATE_AVAILABLE
                )
            )
        }
        val publishPlan = AgentAttachmentPublishOrder.peerMessagePlan(
            prepared,
            eagerAttachment = { attachment ->
                PeerAttachmentTransferProgress.shouldAutoReceive(attachment.mimeType)
            }
        )
        val queued = synchronized(outboxDispatchLock) {
            for (step in publishPlan.transferSteps) {
                if (!publishJsonResult(
                        step.payload(),
                        topic,
                        contactId,
                        queueOnly = true,
                        deferQueuedDispatch = true
                    ).accepted
                ) return@synchronized MqttPublishResult.FAILED
            }
            publishJsonResult(
                payload,
                topic,
                contactId,
                queueOnly = true,
                blockedByAttachmentTransferIds = publishPlan.blockedTransferIds,
                deferQueuedDispatch = true
            )
        }
        if (!queued.accepted) return MqttPublishResult.FAILED.also {
            AgentOutboundAttachmentTransferStore.discard(context, prepared.map { it.transferId })
        }
        if (dispatchQueued) {
            if (client?.isConnected != true) connect(context)
            scheduleOutboxRetries()
        }
        return queued
    }

    fun requestPeerAttachmentDownload(
        context: Context,
        attachment: PeerChatAttachment,
        contactId: String
    ): Boolean {
        if (attachment.transferId.isBlank() || contactId.isBlank()) return false
        val app = context.applicationContext
        attachmentTransferExecutor.execute {
            val result = PeerIncomingAttachmentStore.requestDownload(
                app,
                attachment.transferId,
                contactId
            ) ?: return@execute
            dispatchIncomingAttachmentResult(app, result, contactId, notifyProgress = true)
        }
        return true
    }

    fun publishAgentTaskCancel(
        taskId: String,
        contactId: String,
        sourceMessageId: Long,
        conversationId: String,
        turnId: String,
        topicOverride: String? = null
    ): Boolean = GalaxySSIMqttMessagePublisher.publishTaskCancel(
        taskId,
        contactId,
        sourceMessageId,
        conversationId,
        turnId,
        topicOverride
    )

    fun publishAgentTaskApproval(
        decision: AgentRemoteApprovalDecision,
        topicOverride: String? = null
    ): Boolean = GalaxySSIMqttMessagePublisher.publishTaskApproval(decision, topicOverride)

    fun publishAgentConversationDelete(conversationId: String, taskIds: Set<String>): Boolean =
        GalaxySSIMqttMessagePublisher.publishConversationDelete(conversationId, taskIds)

    fun publishProfileUpdate(contactId: String, topicOverride: String? = null): Boolean =
        GalaxySSIMqttMessagePublisher.publishProfileUpdate(contactId, topicOverride)

    fun publishPairingClaim(pairingQr: JSONObject): Boolean {
        val context = appContext ?: return false
        if (!GalaxySSILinkProtocol.validatePairingQr(pairingQr)) return false
        val existing = GalaxySSILinkProtocol.serverLink(context, pairingQr.optString("desktop_id"))
        val link = GalaxySSILinkProtocol.ensureServerLink(
            context,
            pairingQr,
            rotateClientRoute = GalaxySSILinkProtocol.shouldRotateClientRoute(existing, pairingQr)
        )
        subscribe()
        val profile = AppStore.profile(context)
        val device = GalaxySSIDeviceIdentity.current(
            context,
            profile,
            GalaxySSICrypto.localIdentitySha256()
        )
        DesktopRemoteControl.markPairingOffer(context, pairingQr)
        val controlAuthorizationToken = pairingQr
            .optJSONObject("desktop_control_authorization")
            ?.optString("token").orEmpty()
        val payload = JSONObject()
            .put("protocol", GalaxySSILinkProtocol.NAME)
            .put("version", GalaxySSILinkProtocol.VERSION)
            .put("type", "galaxyssi_pairing_claim")
            .put("pairing_token", pairingQr.optString("pairing_token"))
            .put("from", GalaxySSICrypto.localGalaxySSIId())
            .put("signal_name", GalaxySSICrypto.localGalaxySSIId())
            .put("signal_device_id", 1)
            .put("client_route_id", link.routes.clientRouteId)
            .put("client_name", device.displayName)
            .put("platform", "android")
            .put("client_device_id", device.deviceId)
            .put("device_name", device.deviceName)
            .put("device_manufacturer", device.manufacturer)
            .put("device_model", device.model)
            .put("platform_version", device.platformVersion)
            .put("profile_name", device.profileName)
            .put("galaxyssi_id", profile.optString("galaxyssi_id"))
            .put("identity_fingerprint", GalaxySSICrypto.localIdentitySha256())
            .put("identity_public_key", GalaxySSICrypto.localIdentityPublicKey())
            .put("signal_bundle", GalaxySSICrypto.localSignalBundleJson())
            .put("desktop_control_authorization_token", controlAuthorizationToken)
            .put(
                "requested_access_profile",
                pairingQr.optJSONObject("pairing_access")?.optString("profile").orEmpty()
            )
            .put("time", System.currentTimeMillis())
        val encryptedClaim = runCatching { GalaxySSILinkProtocol.encryptPairingClaim(payload, pairingQr) }
            .getOrElse {
                Log.e(TAG, "Pairing claim encryption failed", it)
                return false
            }
        synchronized(pairingClaimLock) {
            pendingPairingClaim = PendingPairingClaim(
                desktopId = link.desktopId,
                topic = pairingQr.getString("pairing_topic"),
                wirePayload = encryptedClaim,
                queuedAtMillis = System.currentTimeMillis()
            )
            lastPairingClaimAttemptAt = 0L
        }
        if (client?.isConnected == true) flushPendingPairingClaim() else connect(context)
        return true
    }

    fun publishPhoneContactRequest(targetCard: JSONObject): Boolean =
        GalaxySSIMqttMessagePublisher.publishPhoneContactRequest(targetCard)

    fun publishPhoneContactDecision(targetId: String, approved: Boolean): Boolean =
        GalaxySSIMqttMessagePublisher.publishPhoneContactDecision(targetId, approved)

    private fun publishPhoneContactBundle(targetCard: JSONObject): Boolean =
        GalaxySSIMqttMessagePublisher.publishPhoneContactBundle(targetCard)

    internal fun publishOpaquePairingOrConnect(
        context: Context,
        topic: String,
        secret: String,
        payload: JSONObject,
        purpose: String
    ): Boolean = publishOpaquePacketOrConnect(context, topic, secret, payload, purpose)

    internal fun publishOpaqueRelationshipOrConnect(
        context: Context,
        topic: String,
        secret: String,
        payload: JSONObject,
        purpose: String
    ): Boolean = publishOpaquePacketOrConnect(context, topic, secret, payload, purpose)

    private fun publishOpaquePacketOrConnect(
        context: Context,
        topic: String,
        secret: String,
        payload: JSONObject,
        purpose: String
    ): Boolean {
        val sealed = runCatching {
            GalaxySSILinkProtocol.sealWirePacket(payload.toString(), secret)
        }.onFailure { Log.w(TAG, "Opaque packet encryption failed purpose=$purpose", it) }
            .getOrNull() ?: return false
        val mqtt = client
        val routes = AppStore.phoneRoutesForIdentity(context, payload.optString("to")) ?: return false
        if (mqtt?.isConnected == true && publishBootstrap(mqtt, topic, sealed, routes.receiveWindow)) return true
        pendingOpaquePackets += PendingOpaquePacket(
            topic,
            sealed,
            purpose,
            System.currentTimeMillis() + PhoneContactCard.CONTROL_MAX_AGE_MILLIS,
            routes.receiveWindow
        )
        connect(context)
        return true
    }

    private fun flushPendingOpaquePackets() {
        val mqtt = client ?: return
        if (!mqtt.isConnected) return
        val now = System.currentTimeMillis()
        pendingOpaquePackets.toList().forEach { pending ->
            if (pending.expiresAtMillis < now ||
                publishBootstrap(mqtt, pending.topic, pending.wirePayload, pending.receiveTopics)
            ) pendingOpaquePackets.remove(pending)
        }
    }

    private fun flushPendingPairingClaim() {
        val pending = synchronized(pairingClaimLock) { pendingPairingClaim } ?: return
        if (System.currentTimeMillis() - pending.queuedAtMillis > PAIRING_CLAIM_MAX_AGE_MILLIS) {
            synchronized(pairingClaimLock) {
                if (pendingPairingClaim == pending) pendingPairingClaim = null
            }
            Log.w(TAG, "Discarded expired pending pairing claim")
            notifyPairingFailure(pending.desktopId, "timeout")
            return
        }
        synchronized(pairingClaimLock) {
            val now = SystemClock.elapsedRealtime()
            if (lastPairingClaimAttemptAt != 0L && now - lastPairingClaimAttemptAt < 3_000L) return
            lastPairingClaimAttemptAt = now
        }
        val mqtt = client
        val required = appContext?.let { GalaxySSILinkProtocol.serverLink(it, pending.desktopId)?.routes?.receiveWindow }.orEmpty()
        if (mqtt == null || !mqtt.isConnected || !publishBootstrap(mqtt, pending.topic, pending.wirePayload, required)
        ) {
            retryHandler.removeCallbacks(pairingClaimRetryRunnable)
            retryHandler.postDelayed(pairingClaimRetryRunnable, 3_000L)
            return
        }
        retryHandler.removeCallbacks(pairingClaimRetryRunnable)
        retryHandler.postDelayed(pairingClaimRetryRunnable, 3_000L)
        Log.i(TAG, "Published pending pairing claim desktop=${pending.desktopId.takeLast(8)}")
    }

    fun publishGroupTextMessage(
        content: String,
        groupId: String,
        groupName: String,
        memberId: String,
        memberTopic: String
    ): Boolean = GalaxySSIMqttMessagePublisher.publishGroupTextMessage(
        content,
        groupId,
        groupName,
        memberId,
        memberTopic
    )

    fun publishFileMessage(
        fileId: String,
        name: String,
        size: Long,
        contentType: String,
        caption: String = "",
        contactId: String = "hermes",
        topicOverride: String? = null
    ): Boolean = GalaxySSIMqttMessagePublisher.publishFileMessage(
        fileId,
        name,
        size,
        contentType,
        caption,
        contactId,
        topicOverride
    )

    fun requestSignalBundleForContact(context: Context, contactId: String): Boolean =
        GalaxySSIMqttMessagePublisher.requestSignalBundle(context, contactId)

    private fun publishJson(payload: JSONObject, topic: String?, contactId: String = "hermes"): Boolean =
        publishJsonResult(payload, topic, contactId).accepted

    internal fun publishJsonForTransport(
        payload: JSONObject,
        topic: String?,
        contactId: String
    ): Boolean = publishJson(payload, topic, contactId)

    internal fun outgoingTopicFor(contactId: String): String? = outgoingTopic(contactId)

    internal fun publishBlobOffer(payload: JSONObject, contactId: String): Boolean =
        publishJsonResult(payload, outgoingTopic(contactId), contactId, queueOnly = true).accepted

    internal fun notifyBlobProgress(payload: JSONObject) = notifyMessageListeners(payload)

    internal fun persistBlobArtifactEvent(context: Context, payload: JSONObject): Boolean {
        require(payload.optString("type") in setOf("artifact_available", "artifact_download_failed"))
        val link = GalaxySSILinkProtocol.serverLink(context, payload.getString("desktop_id")) ?: return false
        if (!link.paired || link.routes.clientRouteId != payload.optString("client_route_id")) return false
        val stage = GalaxySSILinkDeliveryStore.stageLocalIncoming(context,
            "blob:" + GalaxySSILinkDeliveryStore.peerScope(link.routes), link.desktopId, payload)
        if (stage == GalaxySSILinkDeliveryStore.IncomingStageResult.INVALID) return false
        com.galaxyssi.chat.blob.BlobArtifactCardUpdates.publish(payload)
        schedulePendingIncomingReplay()
        return true
    }

    internal fun dispatchBlobDependencies() { retryHandler.post { dispatchPendingMessages() } }

    private fun publishJsonResult(
        payload: JSONObject,
        topic: String?,
        contactId: String = "hermes",
        queueOnly: Boolean = false,
        blockedByAttachmentTransferIds: Collection<String> = emptyList(),
        deferQueuedDispatch: Boolean = false,
        trustedBackgroundCognitionAuthorized: Boolean = false
    ): MqttPublishResult {
        if (GalaxySSITransportPrivacyPolicy.isLocalOnly(payload, trustedBackgroundCognitionAuthorized)) {
            Log.w(
                TAG,
                "Publish rejected by local-only privacy boundary type=${payload.optString("type")}"
            )
            return MqttPublishResult.FAILED
        }
        if (topic.isNullOrBlank()) {
            Log.w(TAG, "Publish rejected: target topic is blank")
            return MqttPublishResult.FAILED
        }
        val context = appContext ?: return MqttPublishResult.FAILED
        if (payload.optString("trace_id").isBlank()) {
            payload.put("trace_id", UUID.randomUUID().toString())
        }
        val targetId = if (usesPcConnectorTunnel(contactId)) {
            AppStore.desktopIdForContact(context, contactId)
        } else contactId
        val receiptRoutes = if (usesPcConnectorTunnel(contactId)) {
            GalaxySSILinkProtocol.allServerLinks(context).firstOrNull { topic in it.routes.sendWindow }?.routes
        } else AppStore.phoneRoutesForIdentity(context, contactId)?.takeIf { topic in it.sendWindow }
        if (receiptRoutes == null) return MqttPublishResult.FAILED
        if (usesPcConnectorTunnel(contactId) &&
            !AppStore.isDesktopDeviceContact(context, contactId) &&
            payload.optString("task_id").isNotBlank()
        ) {
            val link = GalaxySSILinkProtocol.serverLink(context, targetId)
                ?: return MqttPublishResult.FAILED
            val requestedRouteId = payload.optString("client_route_id")
            if (requestedRouteId.isNotBlank() &&
                requestedRouteId != link.routes.clientRouteId
            ) {
                Log.w(TAG, "Agent task publish rejected: stale client route identity")
                return MqttPublishResult.FAILED
            }
            payload.put("client_route_id", link.routes.clientRouteId)
            val identity = AgentTaskIdentity(
                clientRouteId = payload.optString("client_route_id"),
                conversationId = payload.optString("conversation_id"),
                taskId = payload.optString("task_id"),
                turnId = payload.optString("turn_id")
            )
            if (!identity.isComplete) {
                Log.w(TAG, "Agent task publish rejected: incomplete task identity")
                return MqttPublishResult.FAILED
            }
            val sourceMessageId = payload.optString("client_message_id").toLongOrNull()
                ?: payload.optLong("client_message_id", 0L)
            if (sourceMessageId > 0L) {
                AgentTaskIdentityStore.register(
                    context,
                    contactId,
                    sourceMessageId,
                    identity
                )
            }
        }
        val publishStartedAt = System.currentTimeMillis()
        payload.put("client_sent_at_ms", publishStartedAt)
        val trace = payload.optJSONArray("delivery_trace") ?: JSONArray().also {
            payload.put("delivery_trace", it)
        }
        trace.put(JSONObject()
            .put("stage", "phone_publish_started")
            .put("at", publishStartedAt)
            .put("detail", contactId))
        payload.optJSONObject("task_budget")?.let { encodedBudget ->
            val estimatedBytes = payload.toString().toByteArray(Charsets.UTF_8).size.toLong()
            val taskBudgetDecision = AgentTaskBudgetPolicy.evaluate(
                budget = AgentTaskBudgetJsonCodec.decode(encodedBudget),
                usage = AgentTaskBudgetUsage(
                    networkBytes = estimatedBytes,
                    usageEstimated = true
                ),
                environment = AgentTaskBudgetProbe.environment(context),
                networkRequired = true,
                trustedNetworkTarget = usesPcConnectorTunnel(contactId)
            )
            if (!taskBudgetDecision.allowed) {
                Log.w(TAG, "Publish rejected by task budget: ${taskBudgetDecision.reason}")
                return MqttPublishResult.FAILED
            }
            payload.put(
                "task_budget_usage",
                AgentTaskBudgetJsonCodec.encodeUsage(
                    AgentTaskBudgetUsage(
                        networkBytes = estimatedBytes,
                        usageEstimated = true
                    )
                )
            )
        }
        val applicationEnvelope = GalaxySSILinkProtocol.makeEnvelope(
            payload,
            GalaxySSICrypto.localGalaxySSIId(),
            targetId
        )
        val encrypted = if (usesPcConnectorTunnel(contactId)) {
            val desktopId = AppStore.desktopIdForContact(context, contactId)
            if (desktopId.isNotBlank()) {
                GalaxySSICrypto.encryptPayloadForDesktop(desktopId, applicationEnvelope)
            } else {
                null
            }
        } else {
            GalaxySSICrypto.encryptPayloadForContact(contactId, applicationEnvelope)
        } ?: run {
            appContext?.let { requestSignalBundleForContact(it, contactId) }
            Log.w(TAG, "Encrypted publish deferred: secure session refresh requested for $contactId")
            return MqttPublishResult.FAILED
        }
        val messageId = applicationEnvelope.getString("message_id")
        val wirePayload = encrypted.toString()
        val brokerAckTimeoutMillis = MqttBrokerAckTimeoutPolicy.forPayloadType(
            payload.optString("type")
        )
        val attachmentTransferId =
            GalaxySSILinkDeliveryStore.recoverableAttachmentTransferId(payload)
        GalaxySSIMqttWireChunking.permanentRejectionReason(wirePayload)?.let { reason ->
            val sourceMessageId = GalaxySSILinkDeliveryStore.outboundClientSourceMessageId(payload)
            Log.e(TAG, "MQTT wire payload permanently rejected message=$messageId reason=$reason")
            listeners.forEach { listener ->
                listener.onDeliveryFailed(sourceMessageId, contactId, "delivery_payload_rejected")
            }
            return MqttPublishResult.FAILED
        }
        val deferMediaUpload = payload.optBoolean("defer_media_upload", false)
        GalaxySSILinkDeliveryStore.enqueue(
            context,
            messageId,
            topic,
            wirePayload,
            requiresValidatedNetwork = deferMediaUpload,
            blockedByAttachmentTransferIds = blockedByAttachmentTransferIds,
            clientSourceMessageId = GalaxySSILinkDeliveryStore.outboundClientSourceMessageId(payload),
            contactId = contactId,
            brokerAckTimeoutMillis = brokerAckTimeoutMillis,
            attachmentTransferId = attachmentTransferId,
            receiptRoutes = receiptRoutes,
            transportTraffic = MqttTrafficPolicy.classify(payload),
            recoverableEnvelope = GalaxySSILinkDeliveryStore.recoverablePeerEnvelope(
                payload,
                applicationEnvelope,
                isDirectPhoneContact = AppStore.phoneRoutesForIdentity(context, contactId) != null &&
                    !usesPcConnectorTunnel(contactId)
            )
        )
        if (!payload.optBoolean("peer_chat")) {
            AgentLatencyTelemetry.transportQueued(context, targetId, messageId,
                com.galaxyssi.chat.metrics.AgentTransportTiming.taskId(payload))
        }
        if (queueOnly) {
            if (!deferQueuedDispatch) {
                if (client?.isConnected != true) connect(context)
                scheduleOutboxRetries()
            }
            return MqttPublishResult.QUEUED
        }
        if (deferMediaUpload) {
            Log.i(
                TAG,
                "Deferred encrypted media message until validated network contact=$contactId"
            )
            return MqttPublishResult.QUEUED
        }

        val mqtt = client
        if (mqtt?.isConnected != true) {
            Log.i(TAG, "Queued encrypted MQTT message until reconnect contact=$contactId")
            connect(context)
            scheduleOutboxRetries()
            return MqttOutboxDispatchPolicy.result(connected = false, published = false)
        }

        if (peerRoutes?.readyForTopic(topic) != true) {
            scheduleOutboxRetries()
            return MqttPublishResult.QUEUED
        }
        GalaxySSILinkDeliveryStore.markAttempt(context, messageId)
        val published = publishWirePayload(
            mqtt,
            topic,
            wirePayload,
            "encrypted_message",
            messageId,
            brokerAckTimeoutMillis, transportTraffic = MqttTrafficPolicy.classify(payload)
        )
        if (!published) {
            scheduleOutboxRetries()
            return MqttOutboxDispatchPolicy.result(connected = true, published = false)
        }
        Log.i(
            TAG,
            "Queued encrypted MQTT message topic=$topic wire_bytes=${wirePayload.toByteArray(Charsets.UTF_8).size}"
        )
        return MqttOutboxDispatchPolicy.result(connected = true, published = true)
    }

    private fun retryPendingMessages() = synchronized(outboxDispatchLock) {
        val context = appContext ?: return
        val mqtt = client ?: return
        if (!mqtt.isConnected || !isRequestReplyReady()) return
        GalaxySSILinkDeliveryStore.discardExhausted(
            context,
            MAX_OUTBOX_DELIVERY_ATTEMPTS,
            MAX_ATTACHMENT_OUTBOX_DELIVERY_ATTEMPTS,
            activeMessageIds = deliveryMessageIds.values.toSet() + synchronized(fragmentTransferLock) {
                fragmentTransfers.values.mapNotNull { it.durableMessageId }.toSet()
            }
        ).forEach { exhausted ->
            if (exhausted.recovering) {
                Log.w(TAG, "Agent delivery confirmation pending source=${exhausted.clientSourceMessageId} message=${exhausted.messageId}; original request retained")
                AndroidAgentRecoveryWake.request(context)
                return@forEach
            }
            if (AgentConnectorResponseStore.hasReceivedDelivery(context, exhausted.clientSourceMessageId, exhausted.contactId)) {
                Log.i(TAG, "Ignored late transport failure for received Agent request source=${exhausted.clientSourceMessageId}")
                return@forEach
            }
            Log.e(
                TAG,
                "MQTT delivery exhausted message=${exhausted.messageId} " +
                    "contact=${exhausted.contactId} attempts=${exhausted.attempts}"
            )
            listeners.forEach { listener ->
                listener.onDeliveryFailed(
                    exhausted.clientSourceMessageId,
                    exhausted.contactId,
                    if (exhausted.attachmentTransferId.isBlank()) {
                        "delivery_retry_exhausted"
                    } else {
                        "attachment_delivery_retry_exhausted"
                    }
                )
            }
        }
        val mediaProfile = AgentMediaNetworkDetector.detect(context)
        var submitted = 0
        for (
            pending in GalaxySSILinkDeliveryStore.pending(
                context,
                allowValidatedNetworkMessages = mediaProfile.canUploadDeferredMedia,
                maxAttempts = MAX_OUTBOX_DELIVERY_ATTEMPTS,
                attachmentMaxAttempts = MAX_ATTACHMENT_OUTBOX_DELIVERY_ATTEMPTS,
                limit = MAX_OUTBOX_RETRY_BATCH
            )
        ) {
            if (submitted >= MAX_OUTBOX_RETRY_BATCH) break
            if (pending.topic.isBlank() || pending.wirePayload.isBlank()) continue
            if (isFragmentTransferActive(pending.messageId) ||
                deliveryMessageIds.containsValue(pending.messageId)) continue
            val permanentRejection =
                GalaxySSIMqttWireChunking.permanentRejectionReason(pending.wirePayload)
            if (permanentRejection != null) {
                GalaxySSILinkDeliveryStore.discard(context, pending.messageId)
                Log.e(
                    TAG,
                    "Discarded permanently rejected MQTT outbox message=${pending.messageId} " +
                        "contact=${pending.contactId} reason=$permanentRejection"
                )
                listeners.forEach { listener ->
                    listener.onDeliveryFailed(
                        pending.clientSourceMessageId,
                        pending.contactId,
                        "delivery_payload_rejected"
                    )
                }
                continue
            }
            if (AgentConnectorResponseStore.hasReceivedDelivery(context, pending.clientSourceMessageId, pending.contactId)) {
                if (pending.attachmentTransferId.isBlank()) {
                    GalaxySSILinkDeliveryStore.acknowledge(context, pending.messageId)
                    continue
                }
            }
            if (AgentTerminalDeliveryStore.isTerminal(context, pending.clientSourceMessageId)) {
                GalaxySSILinkDeliveryStore.discard(context, pending.messageId)
                continue
            }
            if (AgentDeliveryRetryPolicy.expired(pending.recoveryFirstAttemptMillis, System.currentTimeMillis())) {
                GalaxySSILinkDeliveryStore.discard(context, pending.messageId)
                listeners.forEach { it.onDeliveryFailed(pending.clientSourceMessageId,
                    pending.contactId, "delivery_recovery_expired") }
                continue
            }
            // Never fall back to a stale mailbox after a relationship was revoked/replaced.
            val currentTopic = if (pending.contactId.isNotBlank()) {
                outgoingTopic(pending.contactId)
            } else {
                // Internal control envelopes have no contact id. Resolve only a still-authorized link.
                GalaxySSILinkProtocol.allServerLinks(context).firstOrNull {
                    pending.topic in it.routes.sendWindow &&
                        GalaxySSILinkProtocol.isCryptographicallyReady(context, it)
                }?.routes?.control
            }
            if (currentTopic == null || peerRoutes?.readyForTopic(currentTopic) != true) {
                GalaxySSILinkDeliveryStore.waitForPeerRoute(context, pending.messageId)
                continue
            }
            GalaxySSILinkDeliveryStore.markAttempt(context, pending.messageId)
            val published = publishWirePayload(
                mqtt,
                currentTopic,
                pending.wirePayload,
                "outbox_retry",
                pending.messageId,
                pending.brokerAckTimeoutMillis, transportTraffic = pending.transportTraffic
            )
            if (!published) break
            submitted += 1
        }
    }

    private fun dispatchPendingMessages() {
        if (!connected || !outboxDispatchRunning.compareAndSet(false, true)) return
        outboxDispatchExecutor.execute {
            try {
                retryPendingMessages()
            } finally {
                outboxDispatchRunning.set(false)
                retryHandler.post { scheduleOutboxRetries() }
            }
        }
    }

    private fun scheduleOutboxRetries() {
        retryHandler.removeCallbacks(retryRunnable)
        if (!connected) return
        val context = appContext ?: return
        val mediaProfile = AgentMediaNetworkDetector.detect(context)
        val delayMillis = GalaxySSILinkDeliveryStore.nextRetryDelayMillis(
            context,
            allowValidatedNetworkMessages = mediaProfile.canUploadDeferredMedia
        ) ?: return
        retryHandler.postDelayed(
            retryRunnable,
            delayMillis.coerceIn(
                MIN_OUTBOX_RETRY_DELAY_MILLIS,
                MAX_OUTBOX_RETRY_DELAY_MILLIS
            )
        )
    }

    private fun publishSafely(
        mqtt: MqttPoolTransport,
        topic: String,
        message: MqttMessage,
        purpose: String,
        timing: AgentTransportTiming.Attempt? = null,
        delivery: MqttDeliveryDispatch.Delivery? = null,
        publication: MqttPoolTransport.Publication? = null
    ): IMqttDeliveryToken? = MqttPublishGuard.attempt {
        val callback = if (timing == null) null else object : IMqttActionListener {
                override fun onSuccess(asyncActionToken: IMqttToken?) {
                    AgentLatencyTelemetry.transport.broker(timing)
                }
                override fun onFailure(asyncActionToken: IMqttToken?, exception: Throwable?) {
                    AgentLatencyTelemetry.transport.broker(timing, "failed")
                }
            }
        val token = if (delivery == null) mqtt.publish(topic, message, timing, callback, publication)
            else mqtt.publishDelivery(topic, delivery, timing, callback)
        token.exception?.let { throw it }
        token
    }.onFailure {
        AgentLatencyTelemetry.transport.broker(timing, "failed")
        Log.w(TAG, "MQTT publish deferred purpose=$purpose", it)
    }.getOrNull()

    private fun publishWirePayload(
        mqtt: MqttPoolTransport,
        topic: String,
        wirePayload: String,
        purpose: String,
        durableMessageId: String? = null,
        brokerAckTimeoutMillis: Long = MqttBrokerAckTimeoutPolicy.DEFAULT_TIMEOUT_MILLIS,
        receiptAttempt: LinkTransportReceiptAttempt? = null,
        transportTraffic: String = "message"
    ): Boolean {
        val context = appContext ?: return false
        val serverLink = GalaxySSILinkProtocol.allServerLinks(context).firstOrNull {
            topic in it.routes.sendWindow
        }
        val linkSecret = serverLink?.routes?.linkSecret ?: AppStore.phoneLinkSecretForOutgoingTopic(context, topic) ?: run {
            Log.w(TAG, "Opaque publish rejected: relationship key not found")
            return false
        }
        val rawPackets = runCatching { GalaxySSIMqttWireChunking.encode(wirePayload) }
            .onFailure { Log.e(TAG, "MQTT wire payload rejected purpose=$purpose", it) }.getOrNull() ?: return false
        var packets = runCatching {
            rawPackets.map { packet ->
                GalaxySSILinkProtocol.sealWirePacket(packet, linkSecret)
            }
        }
            .onFailure { Log.e(TAG, "MQTT wire payload rejected purpose=$purpose", it) }
            .getOrNull() ?: return false
        if (BuildConfig.DEBUG) Log.d(TAG, "MQTT wire prepared purpose=$purpose packets=${packets.size} " +
            "max_packet_bytes=${packets.maxOf { it.length }} pending_ack=${brokerAckWatchdog.pendingCount()}")
        if (receiptAttempt != null && packets.size != 1) return false
        if (packets.size == 1) {
            val delivery = if (durableMessageId.isNullOrBlank() || receiptAttempt != null) null else {
                runCatching { peerRoutes?.prepareDelivery(topic, JSONObject(wirePayload), durableMessageId,
                    MqttTrafficPolicy.parse(transportTraffic)) }
                    .onFailure { Log.w(TAG, "MQTT attempt preparation deferred: ${it.javaClass.simpleName}") }
                    .getOrNull() ?: return false
            }
            val timing = AgentLatencyTelemetry.transport.begin(serverLink?.desktopId.orEmpty(), durableMessageId.orEmpty())
            val token = publishSafely(
                mqtt,
                topic,
                mqttMessage(packets.first()),
                purpose,
                timing,
                delivery?.takeIf { it.sizeBound <= MqttBrokerCatalog.SMALL_PACKET_BYTES }
            ) ?: return false
            if (!durableMessageId.isNullOrBlank()) {
                deliveryMessageIds[token.messageId] = durableMessageId
            }
            if (receiptAttempt != null) transportReceiptAttempts[token.messageId] = receiptAttempt
            val acknowledgedEarly = trackBrokerDelivery(token, brokerAckTimeoutMillis)
            if (acknowledgedEarly || token.isComplete) {
                appContext?.let { context ->
                    retryHandler.post { handleBrokerDeliveryComplete(context, token.messageId) }
                }
            }
            return true
        }

        val key = durableMessageId?.let { "durable:$it" } ?: "ephemeral:${UUID.randomUUID()}"
        synchronized(fragmentTransferLock) {
            if (fragmentTransfers.containsKey(key)) return true
            val routed = if (durableMessageId.isNullOrBlank()) emptyList() else
                AndroidMqttChunks.prepare(context, topic, rawPackets, linkSecret, peerRoutes) ?: return false
            if (routed.isNotEmpty()) packets = routed.map { it.first }
            fragmentTransfers[key] = OutboundFragmentTransfer(
                key = key,
                durableMessageId = durableMessageId,
                topic = topic,
                packets = packets,
                purpose = purpose,
                brokerAckTimeoutMillis = brokerAckTimeoutMillis,
                timing = AgentLatencyTelemetry.transport.begin(serverLink?.desktopId.orEmpty(), durableMessageId.orEmpty()),
                publications = routed.map { it.second }
            )
            pumpFragmentTransfersLocked(mqtt)
            val transfer = fragmentTransfers[key]
            if (transfer == null) return false
            if (transfer.failed && transfer.outstanding == 0) {
                fragmentTransfers.remove(key)
                return false
            }
        }
        Log.i(
            TAG,
            "MQTT fragmented transfer queued purpose=$purpose chunks=${packets.size} " +
                "wire_bytes=${wirePayload.toByteArray(Charsets.UTF_8).size}"
        )
        return true
    }

    private fun mqttMessage(payload: String): MqttMessage =
        MqttMessage(payload.toByteArray(Charsets.UTF_8)).apply {
            qos = MQTT_QOS
            isRetained = false
        }

    private fun pumpFragmentTransfersLocked(mqtt: MqttPoolTransport) {
        var madeProgress: Boolean
        do {
            madeProgress = false
            val transfers = fragmentTransfers.values.toList()
            for (transfer in transfers) {
                if (fragmentInflight >= MAX_FRAGMENT_INFLIGHT) return
                if (transfer.failed ||
                    transfer.nextPacketIndex >= transfer.packets.size ||
                    transfer.outstanding >= MAX_FRAGMENT_INFLIGHT_PER_TRANSFER
                ) {
                    continue
                }
                val packetIndex = transfer.nextPacketIndex
                val token = publishSafely(
                    mqtt,
                    transfer.topic,
                    mqttMessage(transfer.packets[packetIndex]),
                    "${transfer.purpose}_fragment_${packetIndex + 1}_of_${transfer.packets.size}",
                    publication = transfer.publications.getOrNull(packetIndex)
                )
                if (token == null) {
                    transfer.failed = true
                    AgentLatencyTelemetry.transport.broker(transfer.timing, "failed")
                    if (!transfer.durableMessageId.isNullOrBlank()) {
                        retryHandler.post { scheduleOutboxRetries() }
                    }
                    if (transfer.outstanding == 0) fragmentTransfers.remove(transfer.key)
                    continue
                }
                transfer.nextPacketIndex += 1
                transfer.outstanding += 1
                fragmentInflight += 1
                fragmentTransferKeysByMid[token.messageId] = transfer.key
                val acknowledgedEarly = trackBrokerDelivery(
                    token,
                    transfer.brokerAckTimeoutMillis
                )
                if (acknowledgedEarly || token.isComplete) {
                    appContext?.let { context ->
                        retryHandler.post { handleBrokerDeliveryComplete(context, token.messageId) }
                    }
                }
                madeProgress = true
            }
        } while (madeProgress && fragmentInflight < MAX_FRAGMENT_INFLIGHT)
    }

    private fun completeFragmentDelivery(context: Context, mid: Int, generation: Long): Boolean {
        var completedMessageId: String? = null
        var failedMessageId: String? = null
        synchronized(fragmentTransferLock) {
            if (brokerTransportGeneration.get() != generation) return true
            val key = fragmentTransferKeysByMid.remove(mid) ?: return false
            val transfer = fragmentTransfers[key] ?: return true
            transfer.outstanding = (transfer.outstanding - 1).coerceAtLeast(0)
            fragmentInflight = (fragmentInflight - 1).coerceAtLeast(0)
            when {
                transfer.failed && transfer.outstanding == 0 -> {
                    fragmentTransfers.remove(key)
                    failedMessageId = transfer.durableMessageId
                }
                transfer.nextPacketIndex >= transfer.packets.size && transfer.outstanding == 0 -> {
                    fragmentTransfers.remove(key)
                    AgentLatencyTelemetry.transport.broker(transfer.timing)
                    completedMessageId = transfer.durableMessageId
                    Log.i(
                        TAG,
                        "MQTT fragmented transfer broker-acked chunks=${transfer.packets.size} " +
                            "purpose=${transfer.purpose} " +
                            "elapsed_ms=${SystemClock.elapsedRealtime() - transfer.queuedAtElapsedMillis}"
                    )
                }
            }
            client?.takeIf { it.isConnected }?.let(::pumpFragmentTransfersLocked)
        }
        completedMessageId?.let { GalaxySSILinkDeliveryStore.markPublished(context, it) }
        if (failedMessageId != null) scheduleOutboxRetries()
        return true
    }

    private fun trackBrokerDelivery(
        token: IMqttDeliveryToken,
        timeoutMillis: Long
    ): Boolean {
        val acknowledgedEarly = synchronized(brokerDeliveryRegistration) {
            val early = brokerDeliveryRegistration.onPublished(token.messageId)
            if (token.exception != null) {
                appContext?.let { handleBrokerDeliveryFailure(it, token.messageId) }
                return false
            }
            brokerAckWatchdog.onPublished(token.messageId, SystemClock.elapsedRealtime(), timeoutMillis)
            early
        }
        scheduleBrokerAckWatchdog()
        return acknowledgedEarly
    }

    private fun handleBrokerDeliveryComplete(context: Context, mid: Int) {
        synchronized(brokerDeliveryRegistration) {
            if (!brokerDeliveryRegistration.onAcknowledged(mid)) return
            if (BuildConfig.DEBUG) Log.d(TAG, "MQTT broker ACK mid=$mid elapsed_ms=" +
                brokerAckWatchdog.pendingAgeMillis(mid, SystemClock.elapsedRealtime()))
            brokerAckWatchdog.onAcknowledged(mid)
        }
        scheduleBrokerAckWatchdog()
        val callbackClient = client
        val generation = brokerTransportGeneration.get()
        val receipt = transportReceiptAttempts[mid]
        val durableMessageId = deliveryMessageIds[mid]
        // Disk IO and fragment pumping must not block Paho's ACK/keepalive callback thread.
        brokerCompletionExecutor.execute {
            if (client !== callbackClient || brokerTransportGeneration.get() != generation) return@execute
            runCatching {
                if (receipt != null && transportReceiptAttempts.remove(mid, receipt)) {
                    AndroidTransportReceipts.acknowledge(context, receipt)
                }
                if (!completeFragmentDelivery(context, mid, generation) && durableMessageId != null &&
                    deliveryMessageIds.remove(mid, durableMessageId)) {
                    GalaxySSILinkDeliveryStore.markPublished(context, durableMessageId)
                }
            }.onFailure { Log.w(TAG, "Broker completion persistence deferred", it) }
            retryHandler.post { scheduleOutboxRetries() }
        }
    }

    private fun handleBrokerDeliveryFailure(context: Context, mid: Int) {
        synchronized(brokerDeliveryRegistration) {
            brokerDeliveryRegistration.onFailed(mid)
            brokerAckWatchdog.onAcknowledged(mid)
        }
        scheduleBrokerAckWatchdog()
        val callbackClient = client
        val generation = brokerTransportGeneration.get()
        brokerCompletionExecutor.execute {
            if (client !== callbackClient || brokerTransportGeneration.get() != generation) return@execute
            transportReceiptAttempts.remove(mid)
            deliveryMessageIds.remove(mid)
            synchronized(fragmentTransferLock) {
                fragmentTransferKeysByMid[mid]?.let { key -> fragmentTransfers[key]?.failed = true }
            }
            completeFragmentDelivery(context, mid, generation)
            retryHandler.post { scheduleOutboxRetries() }
        }
    }

    private fun scheduleBrokerAckWatchdog() {
        retryHandler.removeCallbacks(brokerAckWatchdogRunnable)
        if (!connected) return
        val delayMillis = brokerAckWatchdog.nextCheckDelayMillis(SystemClock.elapsedRealtime()) ?: return
        retryHandler.postDelayed(brokerAckWatchdogRunnable, delayMillis.coerceAtLeast(100L))
    }

    private fun recoverStalledTransport(oldestAgeMillis: Long) {
        Log.w(TAG, "MQTT physical publication stalled age_ms=$oldestAgeMillis; repairing affected paths")
        client?.repair()
        scheduleBrokerAckWatchdog()
    }

    private fun isFragmentTransferActive(messageId: String): Boolean =
        synchronized(fragmentTransferLock) {
            fragmentTransfers.containsKey("durable:$messageId")
        }

    private fun clearWireTransportState() {
        brokerTransportGeneration.incrementAndGet()
        AgentLatencyTelemetry.transport.disconnected()
        deliveryMessageIds.clear()
        transportReceiptAttempts.clear()
        brokerDeliveryRegistration.clear()
        brokerAckWatchdog.clear()
        retryHandler.removeCallbacks(brokerAckWatchdogRunnable)
        synchronized(fragmentTransferLock) {
            fragmentTransfers.clear()
            fragmentTransferKeysByMid.clear()
            fragmentInflight = 0
        }
    }

    private fun outgoingTopic(contactId: String): String? =
        appContext?.let { AppStore.outgoingTopicForContact(it, contactId) }

    private fun usesPcConnectorTunnel(contactId: String): Boolean {
        if (contactId == "hermes") return true
        val context = appContext ?: return false
        return AppStore.usesPcConnectorTunnel(context, contactId)
    }

    private fun handleIncoming(topic: String, opaquePayload: ByteArray, ingress: MqttBrokerPool.Ingress) {
        val context = appContext ?: return
        PhoneContactCard.sessionForTopic(context, topic)?.let { session ->
            val inner = runCatching {
                GalaxySSILinkProtocol.openWirePacket(opaquePayload, session.getString("secret"))
            }.getOrNull() ?: return
            val payload = runCatching { JSONObject(inner) }.getOrNull() ?: return
            handlePhonePairingIncoming(context, payload, session, null)
            return
        }
        AppStore.phoneRelationshipForTopic(context, topic)?.let { relationship ->
            val secret = relationship.optString("link_secret")
            val inner = runCatching {
                GalaxySSILinkProtocol.openWirePacket(opaquePayload, secret)
            }.getOrNull() ?: return
            val wire = runCatching { JSONObject(inner) }.getOrNull() ?: return
            val routes = GalaxySSILinkProtocol.Routes(relationship.getString("client_route_id"), secret,
                relationship.getString("local_identity_fingerprint"), relationship.getString("identity_fingerprint"))
            if (handleResume(routes, wire, ingress)) return
            val endpoint = relationship.optString("galaxyssi_id").ifBlank { relationship.optString("hermes_id") }
                .ifBlank { relationship.optString("id") }
            if (handleTransportReceipt(routes, wire, ingress, endpoint, phone = true)) return
            if (AndroidMqttChunks.receive(context, routes, wire, ingress, peerRoutes, endpoint, GalaxySSICrypto.localGalaxySSIId(),
                    onWire = { decoded, transfer -> handlePhoneRelationshipWire(context, topic, relationship, decoded, chunkTransferId = transfer) },
                    repeatReceipt = { publishPhoneContactReceipt(context, endpoint, it) })) return
            handlePhoneRelationshipWire(context, topic, relationship, wire, AndroidMqttDelivery.frame(routes, wire, ingress))
            return
        }
        val link = GalaxySSILinkProtocol.allServerLinks(context).firstOrNull {
            topic in it.routes.receiveWindow
        } ?: run {
            Log.w(TAG, "Rejected message on unknown opaque mailbox")
            return
        }
        val inner = runCatching {
            GalaxySSILinkProtocol.openWirePacket(opaquePayload, link.routes.linkSecret)
        }.onFailure {
            Log.w(TAG, "Rejected opaque packet", it)
        }.getOrNull() ?: return
        val wire = runCatching { JSONObject(inner) }
            .onFailure { Log.w(TAG, "Rejected opaque packet content", it) }
            .getOrNull() ?: return
        if (handleResume(link.routes, wire, ingress)) return
        if (handleTransportReceipt(link.routes, wire, ingress, link.desktopId)) return
        if (AndroidMqttChunks.receive(context, link.routes, wire, ingress, peerRoutes, link.desktopId, GalaxySSICrypto.localGalaxySSIId(),
                onWire = { decoded, transfer -> handleIncomingDecoded(topic, link, decoded, chunkTransferId = transfer) },
                repeatReceipt = { publishInboundReceipt(link, it) })) return
        handleIncomingDecoded(topic, link, wire, AndroidMqttDelivery.frame(link.routes, wire, ingress))
    }

    private fun handlePhoneRelationshipWire(
        context: Context,
        topic: String,
        relationship: JSONObject,
        wire: JSONObject,
        deliveryFrame: MqttDeliveryEnvelope.Frame? = null,
        chunkTransferId: String? = null
    ) {
        if (PhoneContactCard.isRelationshipControlType(wire.optString("type"))) {
            handlePhonePairingIncoming(context, wire, null, relationship)
        } else {
            handlePhoneContactIncoming(context, topic, wire, deliveryFrame, chunkTransferId)
        }
    }

    private fun handlePhonePairingIncoming(
        context: Context,
        payload: JSONObject,
        rendezvous: JSONObject?,
        relationship: JSONObject?
    ) {
        val type = payload.optString("type")
        if (!PhoneContactCard.isControlType(type) ||
            !PhoneContactCard.isAddressedToLocalIdentity(payload, GalaxySSICrypto.localGalaxySSIId()) ||
            !PhoneContactCard.isFreshControlPayload(payload)
        ) return
        if ((rendezvous != null) != (type == PhoneContactCard.REQUEST_TYPE)) return
        if ((relationship != null) != (type != PhoneContactCard.REQUEST_TYPE)) return
        val card = PhoneContactCard.cardFromControlPayload(payload) ?: return
        if (!GalaxySSICrypto.verifyPublicIdentitySignature(
                card.optString("identity_public_key"),
                card.optString("identity_fingerprint"),
                PhoneContactCard.canonicalBytes(card),
                card.optString("signature")
            )
        ) return
        val remoteFingerprint = card.optString("identity_fingerprint")
        val relationshipSecret: String
        val localRouteId: String
        if (rendezvous != null) {
            val session = rendezvous ?: return
            if (payload.optString("pairing_token") != session.optString("token")) return
            val claim = PhoneContactCard.claimSession(
                context,
                session.getString("topic"),
                payload.getString("pairing_token"),
                remoteFingerprint
            ) ?: return
            val derivedRoutes = GalaxySSICrypto.derivePhoneRelationshipRoutes(
                card.optString("identity_public_key"),
                remoteFingerprint
            ) ?: return
            relationshipSecret = derivedRoutes.linkSecret
            val existingRoutes = AppStore.phoneRoutesForIdentity(
                context,
                card.optString("galaxyssi_id")
            )
            if (existingRoutes != null &&
                !existingRoutes.remoteFingerprint.equals(remoteFingerprint, ignoreCase = true)
            ) return
            if (claim.alreadyClaimed && existingRoutes != null &&
                existingRoutes.linkSecret == derivedRoutes.linkSecret &&
                existingRoutes.clientRouteId == derivedRoutes.clientRouteId
            ) {
                publishPhoneContactBundle(card)
                return
            }
            localRouteId = derivedRoutes.clientRouteId
        } else {
            val routes = relationship?.let {
                runCatching {
                    GalaxySSILinkProtocol.Routes(
                        it.getString("client_route_id"),
                        it.getString("link_secret"),
                        it.getString("local_identity_fingerprint"),
                        it.getString("identity_fingerprint")
                    )
                }.getOrNull()
            } ?: return
            if (routes.remoteFingerprint != remoteFingerprint) return
            relationshipSecret = routes.linkSecret
            localRouteId = routes.clientRouteId
        }
        if (!PhoneContactCard.acceptControlMessage(context, payload)) return
        if (!AppStore.importPhoneContactRequest(
                context,
                payload,
                relationshipSecret,
                localRouteId
            )
        ) return
        val contactId = card.optString("galaxyssi_id")
        if (rendezvous != null && AppStore.canCommunicateWith(context, contactId)) {
            AppStore.refreshTrustedPhoneRelationship(
                context = context,
                remoteCard = card,
                linkSecret = relationshipSecret,
                clientRouteId = localRouteId
            )
        }
        if (type == PhoneContactCard.APPROVAL_TYPE &&
            !AppStore.approveFriendRequestForGalaxySSIId(context, contactId)
        ) return
        if (type == PhoneContactCard.REJECTION_TYPE) {
            ChatHistoryStore.appendSystemNotification(
                context,
                context.getString(
                    R.string.phone_contact_request_rejected,
                    card.optString("name", context.getString(R.string.fallback_contact_name))
                ),
                "phone-contact-rejected:${payload.optString("control_id")}"
            )
        }
        subscribe()
        if (type == PhoneContactCard.REQUEST_TYPE) {
            if (!publishPhoneContactBundle(card)) return
        } else if (type == PhoneContactCard.BUNDLE_REFRESH_TYPE) {
            if (!publishPhoneContactBundle(card)) return
        }
        if (PeerSignalBundlePolicy.replacesExistingSession(type)) {
            val recovered = PeerSignalSessionRecoveryCoordinator.reencryptPendingMessages(
                context,
                contactId
            )
            if (recovered > 0) {
                Log.i(TAG, "Re-encrypted $recovered pending peer messages after session refresh")
                scheduleOutboxRetries()
            }
        }
        notifyMessageListeners(
            JSONObject()
                .put(
                    "type",
                    when (type) {
                        PhoneContactCard.REQUEST_TYPE -> "phone_contact_request_received"
                        PhoneContactCard.BUNDLE_REFRESH_TYPE -> "phone_contact_session_refreshed"
                        PhoneContactCard.APPROVAL_TYPE -> "phone_contact_request_approved"
                        PhoneContactCard.REJECTION_TYPE -> "phone_contact_request_rejected"
                        else -> "phone_contact_session_ready"
                    }
                )
                .put("contact_id", contactId)
                .put("name", card.optString("name"))
        )
    }

    private fun handleIncomingDecoded(
        topic: String,
        link: GalaxySSILinkProtocol.ServerLink,
        wire: JSONObject,
        deliveryFrame: MqttDeliveryEnvelope.Frame? = null,
        chunkTransferId: String? = null
    ) {
        val context = appContext ?: return
        if (wire.optString("type") == "pairing_rejected") {
            if (wire.optString("protocol") != GalaxySSILinkProtocol.NAME ||
                wire.optInt("version") != GalaxySSILinkProtocol.VERSION ||
                wire.optString("desktop_id") != link.desktopId ||
                wire.optString("desktop_fingerprint") != link.desktopFingerprint ||
                wire.optString("client_route_id") != link.routes.clientRouteId ||
                link.paired
            ) return
            val removed = synchronized(pairingClaimLock) {
                if (pendingPairingClaim?.desktopId != link.desktopId) false else {
                    pendingPairingClaim = null
                    true
                }
            }
            if (removed) {
                retryHandler.removeCallbacks(pairingClaimRetryRunnable)
                notifyPairingFailure(link.desktopId, wire.optString("reason"))
            }
            return
        }
        if (wire.optString("type") == "pairing_confirmed") {
            handlePairingConfirmation(link, wire)
            return
        }
        if (wire.optString("scheme") != "signal" ||
            !GalaxySSILinkProtocol.isCryptographicallyReady(context, link)
        ) {
            Log.w(TAG, "Rejected non-Signal traffic on paired relationship")
            return
        }
        if (wire.optString("from") == GalaxySSICrypto.localGalaxySSIId() &&
            wire.optString("to") == link.desktopId
        ) {
            return
        }
        if (wire.optString("from") != link.desktopId || wire.optString("to") != GalaxySSICrypto.localGalaxySSIId()) {
            Log.w(TAG, "Rejected Signal envelope with mismatched endpoint identity")
            return
        }
        val peer = GalaxySSILinkInbox.Peer(GalaxySSILinkDeliveryStore.peerScope(link.routes), link.desktopId, false)
        val inbox = GalaxySSILinkDeliveryStore.inbox(context)
        val ciphertextDigest = GalaxySSILinkCiphertextReplayPolicy.digest(wire)
        inbox.replay(peer.scope, ciphertextDigest)?.let { known ->
            AndroidMqttChunks.releaseStored(context, link.routes, chunkTransferId, ciphertextDigest)
            if (known.receiptRequired) publishInboundReceipt(link, known.messageId)
            AndroidMqttDelivery.stored(context, link.routes, deliveryFrame, known.messageId, peerRoutes)
            if (!known.completed) schedulePendingIncomingReplay()
            GalaxySSILinkTransportDiagnostics.record(context, GalaxySSILinkDiagnosticKind.ENCRYPTED_REPLAY,
                link.desktopId, known.messageId, "durable_pre_decrypt")
            return
        }
        var accepted: GalaxySSILinkInbox.Accepted? = null
        when (val result = timedInbound("signal_decrypt") {
            GalaxySSICrypto.decryptEnvelopeDetailed(wire) { envelope ->
                accepted = acceptSignalPlaintext(inbox, peer, envelope, ciphertextDigest, MqttDeliveryEnvelope.contentHash(wire), deliveryFrame)
            }
        }) {
            is GalaxySSICrypto.EnvelopeDecryptionResult.Success -> Unit
            is GalaxySSICrypto.EnvelopeDecryptionResult.Failure -> {
                GalaxySSILinkTransportDiagnostics.record(context,
                    GalaxySSILinkTransportDiagnostics.classifyDecryptionFailure(result.error),
                    link.desktopId, ciphertextDigest, result.error.javaClass.simpleName)
                return
            }
            GalaxySSICrypto.EnvelopeDecryptionResult.Rejected -> return
        }
        val stored = checkNotNull(accepted)
        AndroidMqttChunks.releaseStored(context, link.routes, chunkTransferId, ciphertextDigest)
        AndroidMqttDelivery.stored(context, link.routes, deliveryFrame, stored.payload.getString("message_id"), peerRoutes)
        if (!link.paired) GalaxySSILinkProtocol.markPaired(context, link.desktopId)
        setSecureReady(true)
        if (stored.payload.optString("type") != "delivery_ack") publishInboundReceipt(link, stored.payload.getString("message_id"))
        when (stored.stage) {
            GalaxySSILinkInbox.Stage.COMPLETED -> return
            GalaxySSILinkInbox.Stage.PENDING -> { schedulePendingIncomingReplay(); return }
            GalaxySSILinkInbox.Stage.STORED -> timedInbound("dispatch") {
                dispatchIncomingPayload(context, stored.payload, link.desktopId)
            }
        }
    }

    private fun acceptSignalPlaintext(
        inbox: GalaxySSILinkInbox, peer: GalaxySSILinkInbox.Peer, envelope: JSONObject, ciphertextDigest: String, wireHash: String,
        deliveryFrame: MqttDeliveryEnvelope.Frame? = null
    ): GalaxySSILinkInbox.Accepted {
        require(envelope.optString("source_id") == peer.endpoint &&
            envelope.optString("target_id") == GalaxySSICrypto.localGalaxySSIId()) { "Signal application endpoint mismatch" }
        deliveryFrame?.validateApplication(envelope.optString("message_id"), wireHash)
        val immutableHash = MqttImmutableContent.hash(envelope)
        val payload = GalaxySSILinkProtocol.unwrapEnvelope(envelope) ?: error("Invalid Signal application envelope")
        if (payload.optString("type") in setOf("input_attachment_receipt", AgentAttachmentRecoveryRequest.REQUEST_TYPE)) {
            payload.put("source_id", peer.endpoint)
        }
        return inbox.accept(peer, envelope.getString("message_id"), immutableHash, payload,
            ciphertextDigest, receiptRequired = payload.optString("type") != "delivery_ack", wireHash = wireHash)
    }

    private inline fun <T> timedInbound(stage: String, block: () -> T): T {
        if (!BuildConfig.DEBUG) return block()
        val started = android.os.SystemClock.elapsedRealtime()
        try {
            return block()
        } finally {
            Log.d("GalaxySSILatency", "mqtt_inbound stage=$stage ms=${android.os.SystemClock.elapsedRealtime() - started}")
        }
    }

    private fun handlePhoneContactIncoming(context: Context, topic: String, wire: JSONObject,
                                          deliveryFrame: MqttDeliveryEnvelope.Frame? = null, chunkTransferId: String? = null) {
        val localId = GalaxySSICrypto.localGalaxySSIId()
        val senderId = wire.optString("from")
        if (wire.optString("scheme") != "signal" || senderId.isBlank() || wire.optString("to") != localId ||
            !AppStore.canCommunicateWith(context, senderId)) return
        val routes = AppStore.phoneRoutesForIdentity(context, senderId) ?: return
        if (topic !in routes.receiveWindow) return
        val peer = GalaxySSILinkInbox.Peer(GalaxySSILinkDeliveryStore.peerScope(routes), senderId, true)
        val inbox = GalaxySSILinkDeliveryStore.inbox(context)
        val ciphertextDigest = GalaxySSILinkCiphertextReplayPolicy.digest(wire)
        inbox.replay(peer.scope, ciphertextDigest)?.let { known ->
            AndroidMqttChunks.releaseStored(context, routes, chunkTransferId, ciphertextDigest)
            if (known.receiptRequired) publishPhoneContactReceipt(context, senderId, known.messageId)
            AndroidMqttDelivery.stored(context, routes, deliveryFrame, known.messageId, peerRoutes)
            if (!known.completed) schedulePendingIncomingReplay()
            return
        }
        var accepted: GalaxySSILinkInbox.Accepted? = null
        PeerSignalSessionRecoveryCoordinator.decryptOrRequestRefresh(context, senderId, wire) { envelope ->
            accepted = acceptSignalPlaintext(inbox, peer, envelope, ciphertextDigest, MqttDeliveryEnvelope.contentHash(wire), deliveryFrame)
        } ?: return
        val stored = checkNotNull(accepted)
        AndroidMqttChunks.releaseStored(context, routes, chunkTransferId, ciphertextDigest)
        AndroidMqttDelivery.stored(context, routes, deliveryFrame, stored.payload.getString("message_id"), peerRoutes)
        if (stored.payload.optString("type") != "delivery_ack") {
            publishPhoneContactReceipt(context, senderId, stored.payload.getString("message_id"))
        }
        when (stored.stage) {
            GalaxySSILinkInbox.Stage.COMPLETED -> return
            GalaxySSILinkInbox.Stage.PENDING -> { schedulePendingIncomingReplay(); return }
            GalaxySSILinkInbox.Stage.STORED -> dispatchPhoneStored(context, stored.payload, senderId, routes)
        }
    }

    private fun dispatchPhoneStored(context: Context, payload: JSONObject, senderId: String, routes: GalaxySSILinkProtocol.Routes) {
        if (!GalaxySSILinkDeliveryStore.beginIncomingDispatch(context, payload)) {
            deferPendingIncomingReplay(2_000)
            return
        }
        try { dispatchPhonePayload(context, payload, senderId, routes) }
        catch (error: Exception) { retryStoredIncoming(payload, error) }
    }

    private fun dispatchPhonePayload(context: Context, payload: JSONObject, senderId: String, routes: GalaxySSILinkProtocol.Routes) {
        if (GalaxySSITransportPrivacyPolicy.isLocalOnly(payload)) {
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (payload.optString("type") == "delivery_ack") {
            if (GalaxySSILinkDeliveryStore.acknowledgeVerified(context, routes, payload)) {
                AndroidMqttDelivery.acceptedMessage(client, routes, payload)
            }
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (payload.optString("type") == BlobRelayConfiguration.TYPE) {
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (payload.optString("type") == "input_attachment_receipt") {
            processAttachmentControl(context, payload) {
                handleInputAttachmentReceipt(context, payload, senderId)
            }
            return
        }
        if (payload.optString("type") in setOf("input_attachment_manifest", "input_attachment_chunk")) {
            dispatchStoredAttachment(context, payload, senderId, routes)
            return
        }
        if (payload.optString("type") == "peer_message" && payload.optJSONArray("attachments") != null) {
            val attachments = PeerIncomingAttachmentStore.resolveMessageAttachments(
                context,
                senderId,
                payload
            ) ?: run {
                Log.w(TAG, "Deferred peer message until verified attachments are available")
                retryStoredIncoming(payload)
                return
            }
            payload.put("attachments", attachments)
        }
        payload.put("contact_id", senderId)
        notifyMessageListeners(payload)
    }

    private fun publishPhoneContactReceipt(context: Context, contactId: String, messageId: String) {
        AndroidTransportReceipts.enqueue(context, contactId, phone = true, messageId)
    }

    private fun dispatchIncomingPayload(
        context: Context,
        payload: JSONObject,
        sourceDesktopId: String = payload.optString("desktop_id")
    ) {
        if (!GalaxySSILinkDeliveryStore.beginIncomingDispatch(context, payload)) {
            deferPendingIncomingReplay(2_000)
            return
        }
        try { dispatchDesktopPayload(context, payload, sourceDesktopId) }
        catch (error: Exception) { retryStoredIncoming(payload, error) }
    }

    private fun dispatchDesktopPayload(context: Context, payload: JSONObject, sourceDesktopId: String) {
        if (payload.optBoolean("blob_publication") &&
            payload.optString("type") in setOf("artifact_available", "artifact_download_failed")) {
            if (listeners.isNotEmpty()) {
                notifyMessageListeners(payload)
                GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            } else retryStoredIncoming(payload)
            return
        }
        val link = GalaxySSILinkProtocol.serverLink(context, sourceDesktopId)
            ?.takeIf { it.paired } ?: run { retryStoredIncoming(payload); return }
        if (payload.optString("type") == "artifact_blob_offer") {
            AndroidBlobArtifactReceives.receive(context, sourceDesktopId, payload.optString("conversation_id"), payload) { result ->
                result.onSuccess {
                    runCatching { GalaxySSILinkDeliveryStore.completeIncoming(context, payload) }
                        .onFailure { retryStoredIncoming(payload, it) }
                }.onFailure { retryStoredIncoming(payload, it) }
            }
            return
        }
        if (payload.optString("type") == BlobRelayConfiguration.TYPE) {
            BlobRelayConfigurations.ingest(context, payload, sourceDesktopId)
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            AndroidBlobTransfers.wake(context)
            AndroidBlobArtifactReceives.wake(context)
            AndroidBlobArtifactCapability.refresh(context)
            return
        }
        if (GalaxySSITransportPrivacyPolicy.isLocalOnly(payload)) {
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (!payload.optBoolean("peer_chat") && payload.optString("task_id").isNotBlank() &&
            payload.optString("type") in setOf("agent_task_event", "agent_task_approval_result", "text",
                "artifact_chunk", AgentAttachmentRecoveryRequest.REQUEST_TYPE)) {
            val identity = AgentTaskIdentity(payload.optString("client_route_id"), payload.optString("conversation_id"),
                payload.optString("task_id"), payload.optString("turn_id"))
            if (!identity.isComplete || identity.clientRouteId != link.routes.clientRouteId ||
                !AgentTaskIdentityStore.matches(context, payload)) {
                Log.w(TAG, "Rejected Agent payload outside its authenticated task turn")
                GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
                return
            }
            com.galaxyssi.chat.metrics.AgentLatencyTelemetry.received(context, payload)
        }
        if (payload.optString("type") == "delivery_ack") {
            if (GalaxySSILinkDeliveryStore.acknowledgeVerified(context, link.routes, payload)) {
                AndroidMqttDelivery.acceptedMessage(client, link.routes, payload)
                AgentLatencyTelemetry.transport.received(sourceDesktopId, payload.getString("transport_message_id"))
                retryHandler.post { scheduleOutboxRetries() }
                notifyMessageListeners(payload)
            }
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (!payload.optBoolean("peer_chat") && payload.optString("task_id").isNotBlank() &&
            payload.optString("type") in setOf("text", "agent_task_event") &&
            AgentTaskIdentityStore.matchesRegistered(context, payload)
        ) {
            val finalReply = payload.optString("type") == "text"
            val observation = if (finalReply) AgentRemoteOutcomeCodec.decode(payload, "")
                else AgentRemoteOutcomeCodec.observation(payload)
            if (observation == null || !AgentConnectorResponseStore.observeExecution(context, observation,
                    finalReply = finalReply)) {
                GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
                return
            }
            if (payload.optString("type") == "text" && payload.optString("task_status") in AgentRemoteOutcomeCodec.FAILURES) {
                payload.put("content", AgentRemoteOutcomeCodec.content(context, payload))
            }
        }
        if (payload.optString("type") == "agent_task_result_receipt_confirmed") {
            AndroidAgentResultReceipts.receive(context, payload, sourceDesktopId)
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (payload.optString("type") == "agent_task_result_page") {
            AndroidAgentResultRecovery.receive(context, payload, sourceDesktopId)
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (payload.optString("type") == "agent_task_recovery_result") {
            AndroidAgentRemoteRecovery.receive(context, payload, sourceDesktopId)
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (payload.optString("type") in setOf("input_attachment_manifest", "input_attachment_chunk")) {
            dispatchStoredAttachment(context, payload, sourceDesktopId, link.routes)
            return
        }
        AgentRemoteReputation.ingest(context, payload)?.let { result ->
            if (!result.accepted) {
                Log.w(TAG, "Rejected Agent execution receipt: ${result.reason}")
            }
        }
        if (payload.optString("type") == "capability_manifest") {
            GalaxySSILinkProtocol.updatePairingAccess(
                context,
                sourceDesktopId,
                payload.optJSONObject("pairing_access")
            )
            GalaxySSILinkProtocol.markCapabilityManifestReceived(
                context,
                sourceDesktopId,
                payload.optInt("manifest_version", 0)
            )
            RemoteWhisperNodeRegistry.ingest(context, payload, sourceDesktopId)
            AgentDesktopRemoteNativeTools.updateManifest(context, payload)
        }
        if (payload.optString("type") == "artifact_chunk") {
            val result = runCatching { AgentDesktopArtifactStore.ingest(context, payload) }
                .onFailure { Log.w(TAG, "Rejected Desktop artifact chunk", it) }
                .getOrNull()
            if (result?.completed == true) {
                val clientRouteId = payload.optString("client_route_id")
                GalaxySSIMqttDesktopControl.publishArtifactReceipt(
                    sourceDesktopId,
                    clientRouteId,
                    result
                )
                val requestedDownload =
                    GalaxySSIMqttDesktopControl.consumePendingArtifactDownload(result.artifactUri)
                GalaxySSIMqttDesktopControl.consumePendingArtifactFetch(result.artifactUri)
                val savedPath = if (requestedDownload) {
                    AgentDesktopArtifactStore.saveArtifactUriToDownloads(context, result.artifactUri)
                        .getOrNull()
                } else null
                notifyMessageListeners(
                    JSONObject()
                        .put("type", "artifact_available")
                        .put("artifact_id", result.artifactId)
                        .put("artifact_uri", result.artifactUri)
                        .put("task_id", result.taskId)
                        .put("saved_path", savedPath.orEmpty())
                        .put("save_requested", requestedDownload)
                )
            }
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (payload.optString("type") == "artifact_redelivery_result") {
            val artifactUri = payload.optString("artifact_uri")
            if (payload.optString("status") != "stored") {
                GalaxySSIMqttDesktopControl.consumePendingArtifactDownload(artifactUri)
                GalaxySSIMqttDesktopControl.consumePendingArtifactFetch(artifactUri)
                notifyMessageListeners(
                    JSONObject()
                        .put("type", "artifact_download_failed")
                        .put("artifact_id", payload.optString("artifact_id"))
                        .put("artifact_uri", artifactUri)
                )
            }
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (payload.optString("type") == "input_attachment_receipt") {
            processAttachmentControl(context, payload) {
                handleInputAttachmentReceipt(context, payload, payload.optString("source_id").ifBlank { sourceDesktopId })
            }
            return
        }
        if (payload.optString("type") == AgentAttachmentRecoveryRequest.REQUEST_TYPE) {
            processAttachmentControl(context, payload) {
                handleInputAttachmentRequest(context, payload, payload.optString("source_id").ifBlank { sourceDesktopId })
            }
            return
        }
        if (payload.optString("type") == "proactive_task_event") {
            AgentRemoteProactiveEventStore(context).ingest(payload, sourceDesktopId)
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (payload.optString("type") == "proactive_webhook_event") {
            AgentProactiveTaskScheduler.acceptRemoteWebhook(
                context = context,
                taskId = payload.optString("task_id"),
                eventId = payload.optString("event_id"),
                payload = payload.optJSONObject("payload") ?: JSONObject(),
                sourceDesktopId = sourceDesktopId
            )
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (DesktopRemoteControl.handleInbound(context, payload)) {
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (AgentDesktopRemoteNativeTools.handleInbound(payload)) {
            GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
            return
        }
        if (handleSecureControlMessage(payload)) {
            notifyMessageListeners(payload)
            return
        }
        payload.optJSONArray("connector_agents")?.let { AppStore.updateConnectorAgentStatuses(context, it) }
        notifyMessageListeners(payload)
    }

    private fun processAttachmentControl(context: Context, payload: JSONObject, process: () -> Unit) {
        val id = payload.optString(MqttImmutableContent.RECORD_KEY)
        attachmentControlInbox.enqueue(id, process,
            complete = { GalaxySSILinkDeliveryStore.completeIncoming(context, payload) },
            failed = { error ->
                retryStoredIncoming(payload, error)
            })
    }

    private fun dispatchStoredAttachment(context: Context, payload: JSONObject, sourceId: String,
                                         routes: GalaxySSILinkProtocol.Routes) {
        processAttachmentControl(context, payload) {
            val result = checkNotNull(PeerIncomingAttachmentStore.ingest(context, payload, sourceId, routes)) {
                "Attachment chunk or manifest is not durably accepted"
            }
            dispatchIncomingAttachmentResult(context, result, sourceId, notifyProgress = true, routesOverride = routes)
        }
    }

    private fun retryStoredIncoming(payload: JSONObject, error: Throwable? = null) {
        if (error != null) Log.w(TAG, "Inbound work retained for replay: ${error.javaClass.simpleName}")
        GalaxySSILinkDeliveryStore.retryIncoming(payload)
        if (listeners.isNotEmpty()) deferPendingIncomingReplay(2_000)
    }

    private fun deferPendingIncomingReplay(delayMillis: Long) = synchronized(inboundReplayTimerLock) {
        retryHandler.removeCallbacks(inboundReplayRetryRunnable)
        retryHandler.postDelayed(inboundReplayRetryRunnable, delayMillis)
    }

    private fun notifyMessageListeners(payload: JSONObject) {
        if (listeners.isEmpty()) {
            GalaxySSILinkDeliveryStore.retryIncoming(payload)
            return
        }
        com.galaxyssi.chat.blob.BlobArtifactCardUpdates.publish(payload)
        val encoded = payload.toString()
        listeners.forEach { listener ->
            runCatching { listener.onMessage(encoded) }
                .onFailure { retryStoredIncoming(payload, it) }
        }
    }

    private fun schedulePendingIncomingReplay() {
        val context = appContext ?: return
        if (!inboundReplayScheduled.compareAndSet(false, true)) return
        inboundReplayExecutor.execute {
            var more = false
            try {
                val pending = GalaxySSILinkDeliveryStore.pendingIncoming(context)
                more = pending.isNotEmpty()
                if (pending.isNotEmpty()) {
                    Log.i(TAG, "Replaying durable inbound messages count=${pending.size}")
                }
                pending.forEach { incoming ->
                    val payload = runCatching { JSONObject(incoming.payload) }
                        .onFailure {
                            Log.w(TAG, "Unreadable durable inbound message retained: ${it.javaClass.simpleName}")
                        }
                        .getOrNull() ?: return@forEach
                    if (incoming.phone) {
                        val routes = AppStore.phoneRoutesForIdentity(context, incoming.endpointId)
                        if (routes != null && AppStore.canCommunicateWith(context, incoming.endpointId) &&
                            GalaxySSILinkDeliveryStore.peerScope(routes) == incoming.peerScope) {
                            dispatchPhoneStored(context, payload, incoming.endpointId, routes)
                        } else GalaxySSILinkDeliveryStore.inbox(context).forget(incoming.peerScope)
                    } else {
                        val link = GalaxySSILinkProtocol.serverLink(context, incoming.endpointId)
                        val scope = link?.let { GalaxySSILinkDeliveryStore.peerScope(it.routes) }
                        if (link?.paired == true && incoming.peerScope in setOf(scope, "pair:$scope", "blob:$scope")) {
                            dispatchIncomingPayload(context, payload, incoming.endpointId)
                        } else GalaxySSILinkDeliveryStore.inbox(context).forget(incoming.peerScope)
                    }
                }
            } catch (error: Exception) {
                Log.w(TAG, "Durable inbox replay deferred: ${error.javaClass.simpleName}")
                more = true
            } finally {
                inboundReplayScheduled.set(false)
                if (more) deferPendingIncomingReplay(if (listeners.isEmpty()) 15_000 else 2_000)
            }
        }
    }

    private fun publishInboundReceipt(link: GalaxySSILinkProtocol.ServerLink, receivedMessageId: String) {
        val context = appContext ?: return
        AndroidTransportReceipts.enqueue(context, link.desktopId, phone = false, receivedMessageId)
    }

    internal fun publishTransportReceipt(topic: String, wire: String, attempt: LinkTransportReceiptAttempt): Boolean {
        val mqtt = client?.takeIf { it.isConnected && canPublishTransportReceipt() } ?: return false
        return publishWirePayload(mqtt, topic, wire, "durable_transport_receipt", receiptAttempt = attempt)
    }

    internal fun canPublishTransportReceipt(): Boolean = isRequestReplyReady() && transportReceiptAttempts.size < 2

    private fun handlePairingConfirmation(link: GalaxySSILinkProtocol.ServerLink, json: JSONObject) {
        val context = appContext ?: return
        if (json.optString("protocol") != GalaxySSILinkProtocol.NAME ||
            json.optInt("version") != GalaxySSILinkProtocol.VERSION ||
            json.optString("client_route_id") != link.routes.clientRouteId
        ) return
        val desktopId = json.optString("desktop_id")
        if (desktopId != link.desktopId) return
        val messageId = PairingConfirmationDeliveryPolicy.messageId(
            suppliedId = json.optString("message_id"),
            desktopId = desktopId,
            clientRouteId = link.routes.clientRouteId
        )
        json.put("message_id", messageId)
        val expected = json.optString("desktop_fingerprint")
        if (!expected.equals(link.desktopFingerprint, ignoreCase = true)) return
        val hasSession = GalaxySSICrypto.hasDesktopSession(context, desktopId)
        val sessionReady = if (PairingConfirmationDeliveryPolicy.needsSessionBootstrap(hasSession, link.paired)) {
            json.optJSONObject("signal_bundle")?.let { bundle ->
                GalaxySSICrypto.processPcBundleForDesktop(
                    desktopId,
                    bundle,
                    expected,
                    replaceExisting = !link.paired
                )
            } == true
        } else {
            true
        }
        if (!sessionReady) return
        synchronized(pairingClaimLock) {
            if (pendingPairingClaim?.desktopId == desktopId) pendingPairingClaim = null
        }
        retryHandler.removeCallbacks(pairingClaimRetryRunnable)
        GalaxySSILinkProtocol.markPaired(
            context,
            desktopId,
            json.optJSONObject("pairing_access")
        )
        AppStore.updateDesktopDeviceContact(context, json)
        refreshPoolBindings(context)
        schedulePoolStateRefresh(recover = true)
        setSecureReady(true)
        dispatchPendingMessages()
        json.optJSONArray("connector_agents")?.let { AppStore.updateConnectorAgentStatuses(context, it) }
        val stage = GalaxySSILinkDeliveryStore.stageLocalIncoming(context,
            "pair:" + GalaxySSILinkDeliveryStore.peerScope(link.routes), desktopId, json)
        if (!PairingConfirmationDeliveryPolicy.isFirstDelivery(stage)) return
        requestConnectorStatuses(
            context = context,
            forceCapabilityManifest = true,
            targetDesktopId = desktopId,
            bypassThrottle = true
        )
        listeners.forEach { listener -> listener.onMessage(json.toString()) }
    }

    private fun notifyPairingFailure(desktopId: String, reason: String) {
        val context = appContext ?: return
        val message = context.getString(
            if (reason == "token_bound") R.string.desktop_pairing_code_used
            else R.string.desktop_pairing_timed_out
        )
        val event = JSONObject()
            .put("type", "pairing_failed")
            .put("desktop_id", desktopId)
            .put("sender", "system")
            .put("contact_id", "system")
            .put("message_id", UUID.randomUUID().toString())
            .put("content", message)
        retryHandler.post {
            android.widget.Toast.makeText(context, message, android.widget.Toast.LENGTH_LONG).show()
            listeners.forEach { it.onMessage(event.toString()) }
        }
    }

    private fun handleSecureControlMessage(json: JSONObject): Boolean {
        return when (json.optString("type")) {
            "pairing_revoked" -> {
                val context = appContext ?: return true
                Log.w(TAG, "Pairing revoked by desktop connector")
                val desktopId = json.optString("desktop_id")
                if (desktopId.isNotBlank()) {
                    val removed = DesktopPairingLifecycle.remove(context, desktopId)
                    json.put("revoked_contact_ids", JSONArray(removed.contactIds))
                } else {
                    AppStore.deleteContact(context, "hermes", deleteMessages = true)
                }
                setSecureReady(GalaxySSILinkProtocol.allServerLinks(context).any { it.paired })
                true
            }
            else -> false
        }
    }

    private fun requestMissingSignalSessions(context: Context) {
        AndroidBlobArtifactCapability.refresh(context, reconnect = true)
        setSecureReady(isRequestReplyReady())
        resumePendingAttachmentTransfers(context)
        resumePendingIncomingAttachmentDownloads(context)
    }

    private fun resumePendingAttachmentTransfers(context: Context) {
        AndroidBlobTransfers.wake(context)
        AndroidBlobArtifactReceives.wake(context)
        attachmentTransferExecutor.execute {
            AgentOutboundAttachmentTransferStore.pending(context).forEach { attachment ->
                if (AndroidBlobTransfers.owns(context, attachment.transferId)) return@forEach
                val desktopLink = GalaxySSILinkProtocol.serverLink(context, attachment.scope.desktopId)
                val phoneRoutes = AppStore.phoneRoutesForIdentity(context, attachment.scope.desktopId)
                val route = desktopLink?.routes ?: phoneRoutes ?: return@forEach
                if (desktopLink != null && !desktopLink.paired) return@forEach
                if (route.clientRouteId != attachment.scope.clientRouteId) return@forEach
                publishJsonResult(
                    attachment.manifestPayload(resume = true),
                    route.up,
                    attachment.scope.contactId
                )
            }
        }
    }

    private fun resumePendingIncomingAttachmentDownloads(context: Context) {
        attachmentTransferExecutor.execute {
            PeerIncomingAttachmentStore.pendingDownloads(context).forEach { pending ->
                val routes = attachmentRoutes(context, pending.sourceId) ?: return@forEach
                val result = PeerIncomingAttachmentStore.requestDownload(
                    context,
                    pending.transferId,
                    pending.sourceId
                ) ?: return@forEach
                dispatchIncomingAttachmentResult(
                    context,
                    result,
                    pending.sourceId,
                    notifyProgress = true,
                    routesOverride = routes
                )
            }
        }
    }

    private fun handleInputAttachmentReceipt(
        context: Context,
        payload: JSONObject,
        sourceDesktopId: String
    ) {
        if (AndroidBlobTransfers.acceptReceipt(context, payload, sourceDesktopId)) return
        val transfer = AgentOutboundAttachmentTransferStore.find(
            context,
            payload.optString("transfer_id").lowercase()
        ) ?: return
        if (
            transfer.scope.desktopId != sourceDesktopId ||
            payload.optString("client_route_id") != transfer.scope.clientRouteId
        ) return
        if (AndroidBlobTransfers.owns(context, transfer.transferId)) {
            AndroidBlobTransfers.wake(context)
            return
        }
        val progress = payload.optInt("progress", -1).takeIf { it >= 0 }
            ?: PeerAttachmentTransferProgress.percent(
                payload.optLong("received_bytes", 0L),
                transfer.sizeBytes
            )
        notifyMessageListeners(
            PeerAttachmentTransferProgress.event(
                transfer,
                sourceDesktopId,
                "outbound",
                progress,
                if (payload.optString("status") == "stored") {
                    PeerAttachmentTransferProgress.STATE_COMPLETE
                } else {
                    PeerAttachmentTransferProgress.STATE_UPLOADING
                },
                payload.optLong("received_bytes", 0L)
            )
        )
        if (payload.optString("status") == "stored") {
            val acknowledgement = AgentOutboundAttachmentTransferStore.acknowledgeStored(
                context,
                payload
            ) ?: return
            Log.i(
                TAG,
                "Stored input attachment acknowledged transfer=${acknowledgement.transferId.take(12)} " +
                    "matched=${acknowledgement.matchedMessages} " +
                    "released=${acknowledgement.releasedMessages}"
            )
            retryHandler.post {
                dispatchPendingMessages()
            }
            return
        }
        if (payload.optString("status") != "missing") return
        val requested = runCatching {
            AgentAttachmentTransferProtocol.expandMissingRanges(
                payload.optJSONArray("missing_ranges"),
                transfer.chunkCount
            ).also { indices ->
                require(indices.size <= PeerAttachmentTransferProgress.MAX_REQUEST_WINDOW_CHUNKS) {
                    "Attachment transfer window is too large"
                }
            }
        }.onFailure {
            Log.w(TAG, "Rejected invalid attachment resume request", it)
        }.getOrNull() ?: return
        val desktopLink = GalaxySSILinkProtocol.serverLink(context, sourceDesktopId)
        val route = desktopLink?.routes ?: AppStore.phoneRoutesForIdentity(context, sourceDesktopId) ?: return
        if (desktopLink != null && !desktopLink.paired) return
        if (route.clientRouteId != transfer.scope.clientRouteId) return
        requested.forEach { index ->
            publishJsonResult(
                transfer.chunkPayload(index),
                route.up,
                transfer.scope.contactId
            )
        }
    }

    private fun dispatchIncomingAttachmentResult(
        context: Context,
        result: PeerIncomingAttachmentStore.IngestResult,
        sourceId: String,
        notifyProgress: Boolean,
        routesOverride: GalaxySSILinkProtocol.Routes? = null
    ) {
        if (notifyProgress) result.progress?.let(::notifyMessageListeners)
        val receipt = result.receipt ?: return
        val routes = routesOverride ?: attachmentRoutes(context, sourceId) ?: return
        publishJsonResult(receipt, routes.up, sourceId)
        val transferId = receipt.optString("transfer_id")
        if (receipt.optString("status") == "missing") {
            scheduleIncomingAttachmentRetry(context, transferId, sourceId)
        } else {
            cancelIncomingAttachmentRetry(transferId, sourceId)
        }
    }

    private fun attachmentRoutes(
        context: Context,
        sourceId: String
    ): GalaxySSILinkProtocol.Routes? {
        val desktopLink = GalaxySSILinkProtocol.serverLink(context, sourceId)
        if (desktopLink != null && !desktopLink.paired) return null
        return desktopLink?.routes ?: AppStore.phoneRoutesForIdentity(context, sourceId)
    }

    private fun scheduleIncomingAttachmentRetry(
        context: Context,
        transferId: String,
        sourceId: String
    ) {
        if (transferId.isBlank() || sourceId.isBlank()) return
        val key = "$sourceId:$transferId"
        attachmentRetryRunnables.remove(key)?.let(retryHandler::removeCallbacks)
        val app = context.applicationContext
        val retry = Runnable {
            attachmentRetryRunnables.remove(key)
            attachmentTransferExecutor.execute {
                val result = PeerIncomingAttachmentStore.requestDownload(app, transferId, sourceId)
                    ?: return@execute
                dispatchIncomingAttachmentResult(app, result, sourceId, notifyProgress = false)
            }
        }
        attachmentRetryRunnables[key] = retry
        retryHandler.postDelayed(retry, ATTACHMENT_REQUEST_RETRY_MILLIS)
    }

    private fun cancelIncomingAttachmentRetry(transferId: String, sourceId: String) {
        val key = "$sourceId:$transferId"
        attachmentRetryRunnables.remove(key)?.let(retryHandler::removeCallbacks)
    }

    private fun handleInputAttachmentRequest(
        context: Context,
        payload: JSONObject,
        sourceDesktopId: String
    ) {
        val request = AgentAttachmentRecoveryRequest.decode(payload) ?: return
        if (!AgentTaskIdentityStore.matchesRegistered(context, payload)) {
            Log.w(TAG, "Rejected attachment recovery outside a registered task")
            return
        }
        val link = GalaxySSILinkProtocol.serverLink(context, sourceDesktopId) ?: return
        if (
            !link.paired ||
            link.routes.clientRouteId != request.clientRouteId ||
            AppStore.desktopIdForContact(context, request.contactId) != sourceDesktopId
        ) return
        val restored = runCatching {
            AgentAttachmentWorkspaceStager.restoreByIds(
                context,
                request.conversationId,
                request.attachmentIds
            )
        }.onFailure {
            Log.w(TAG, "Requested attachment recovery lookup failed", it)
        }.getOrElse {
            publishJsonResult(
                request.result(
                    status = "failed",
                    error = "Requested attachment could not be restored"
                ),
                link.routes.up,
                request.contactId
            )
            return
        }
        val availableIds = restored.map(AgentInputAttachment::id)
        val missingIds = request.attachmentIds.filterNot(availableIds::contains)
        if (restored.isEmpty()) {
            publishJsonResult(
                request.result(
                    status = "missing",
                    missingAttachmentIds = missingIds
                ),
                link.routes.up,
                request.contactId
            )
            return
        }
        val prepared = runCatching {
            AgentOutboundAttachmentTransferStore.prepare(
                context = context,
                scope = AgentAttachmentTransferScope(
                    contactId = request.contactId,
                    desktopId = sourceDesktopId,
                    clientRouteId = request.clientRouteId,
                    conversationId = request.conversationId,
                    taskId = request.taskId,
                    turnId = request.turnId,
                    clientMessageId = request.sourceMessageId,
                    attachmentRequestId = request.requestId
                ),
                attachments = restored,
                mediaProfile = AgentMediaNetworkDetector.detect(context)
            )
        }.onFailure {
            Log.w(TAG, "Requested attachment recovery preparation failed", it)
        }.getOrElse {
            publishJsonResult(
                request.result(
                    status = "failed",
                    availableAttachmentIds = availableIds,
                    missingAttachmentIds = missingIds,
                    error = "Requested attachment could not be prepared"
                ),
                link.routes.up,
                request.contactId
            )
            return
        }
        publishJsonResult(
            request.result(
                status = "transferring",
                availableAttachmentIds = availableIds,
                missingAttachmentIds = missingIds
            ),
            link.routes.up,
            request.contactId
        )
        prepared.forEach { attachment ->
            if (AndroidBlobTransfers.register(context, attachment, immediate = true)) return@forEach
            publishJsonResult(
                attachment.manifestPayload(resume = false),
                link.routes.up,
                request.contactId
            )
            for (chunkIndex in 0 until attachment.chunkCount) {
                publishJsonResult(
                    attachment.chunkPayload(chunkIndex),
                    link.routes.up,
                    request.contactId
                )
            }
        }
    }

    private fun scheduleConnectorStatusRequest() {
        retryHandler.postDelayed({
            appContext?.let(::requestConnectorStatuses)
        }, 500L)
    }

    private fun requestConnectorStatuses(
        context: Context,
        forceCapabilityManifest: Boolean = false,
        targetDesktopId: String? = null,
        bypassThrottle: Boolean = false
    ) {
        val mqtt = client ?: return
        if (!mqtt.isConnected) return
        val eligibleLinks = GalaxySSILinkProtocol.allServerLinks(context)
            .filter { link ->
                link.paired &&
                    peerRoutes?.readyForTopic(link.routes.control) == true &&
                    GalaxySSICrypto.hasDesktopSession(context, link.desktopId) &&
                    (targetDesktopId == null || link.desktopId == targetDesktopId)
            }
        if (eligibleLinks.isEmpty()) return
        val now = System.currentTimeMillis()
        if (forceCapabilityManifest) {
            if (!bypassThrottle && now - lastCapabilityManifestRequestAt < 15_000L) return
            lastCapabilityManifestRequestAt = now
        } else {
            if (!bypassThrottle && now - lastConnectorStatusRequestAt < 5_000L) return
            lastConnectorStatusRequestAt = now
        }
        eligibleLinks.forEach { link ->
                val requestManifest = forceCapabilityManifest ||
                    GalaxySSILinkProtocol.needsCapabilityManifest(link)
                val payload = JSONObject()
                    .put("type", "connector_status_request")
                    .put("contact_id", "system")
                    .put("desktop_id", link.desktopId)
                    .put("capability_manifest_version", link.capabilityManifestVersion)
                    .put("request_capability_manifest", requestManifest)
                    .put("request_blob_configuration", true)
                    .put("time", now)
                val envelope = GalaxySSILinkProtocol.makeEnvelope(
                    payload,
                    GalaxySSICrypto.localGalaxySSIId(),
                    link.desktopId
                )
                val encrypted = GalaxySSICrypto.encryptPayloadForDesktop(link.desktopId, envelope)
                    ?: return@forEach
                val published = publishWirePayload(
                    mqtt,
                    link.routes.control,
                    encrypted.toString(),
                    "connector_status"
                )
                if (published) {
                    Log.i(TAG, "Requested connector status desktop=${link.desktopId.takeLast(8)}")
                }
            }
    }

    fun requestCapabilityManifestRefresh(force: Boolean = false): Boolean {
        val context = appContext ?: return false
        val mqtt = client ?: return false
        if (!mqtt.isConnected) return false
        if (!force && GalaxySSILinkProtocol.allServerLinks(context).none {
                it.paired && GalaxySSILinkProtocol.needsCapabilityManifest(it)
            }
        ) return false
        retryHandler.post {
            requestConnectorStatuses(context, forceCapabilityManifest = force)
        }
        return true
    }

    private fun subscribe() {
        if (client?.isConnected != true || !subscriptionRefreshScheduled.compareAndSet(false, true)) return
        outboxDispatchExecutor.execute {
            subscriptionRefreshScheduled.set(false)
            subscribeNow()
        }
    }

    private fun subscribeNow() {
        val mqtt = client ?: return
        if (!mqtt.isConnected) return
        val context = appContext ?: return
        val snapshot = refreshPoolBindings(context)
        val links = snapshot.desktops
        val phoneBindings = snapshot.phones.map { it.first to it.second.receiveWindow }
        val phoneTopics = phoneBindings.flatMapTo(linkedSetOf()) { it.second }
        val rendezvousTopics = PhoneContactCard.activeRendezvousTopics(context)
        inboundBindings.replace(links.map { it.desktopId to it.routes.receiveWindow } + phoneBindings, rendezvousTopics)
        if (BuildConfig.DEBUG) {
            Log.d(
                TAG,
                "MQTT phone subscriptions local=${GalaxySSICrypto.localGalaxySSIId()} " +
                    "mailboxes=${phoneTopics.map { it.take(10) }.sorted()} " +
                    "rendezvous=${rendezvousTopics.size}"
            )
        }
        val extraAttempts = listOf(phoneTopics, rendezvousTopics).count { it.isNotEmpty() }
        val generation = subscriptionRecoveryState.begin(maxOf(1, links.size + extraAttempts))
        AndroidAgentRecoveryWake.connectionChanged(context, false)
        subscriptionCoordinator.reconcile(mqtt, links, phoneTopics, rendezvousTopics, generation)
        if (links.isEmpty() && extraAttempts == 0) {
            completeSubscriptionAttempt(generation, succeeded = true)
        }
    }

    private fun completeSubscriptionAttempt(generation: Int, succeeded: Boolean) {
        when (subscriptionRecoveryState.complete(generation, succeeded)) {
            MqttSubscriptionAttemptOutcome.STALE,
            MqttSubscriptionAttemptOutcome.PENDING -> Unit
            MqttSubscriptionAttemptOutcome.READY -> {
                cancelSubscriptionRetry()
                outboxDispatchExecutor.execute {
                    appContext?.let { AndroidAgentRecoveryWake.connectionChanged(it, isRequestReplyReady()) }
                    appContext?.let(::requestMissingSignalSessions)
                    replayApprovedPhoneContactDecisionsOnce()
                }
                Log.i(TAG, "Subscribed to rotating opaque relationship mailboxes")
            }
            MqttSubscriptionAttemptOutcome.RETRY -> {
                setSecureReady(isRequestReplyReady())
                scheduleSubscriptionRetry()
            }
        }
    }

    private fun replayApprovedPhoneContactDecisionsOnce() {
        if (!approvedPhoneDecisionReplayScheduled.compareAndSet(false, true)) return
        val context = appContext ?: return
        retryHandler.post {
            AppStore.approvedIncomingPhoneContactIds(context).forEach { contactId ->
                publishPhoneContactDecision(contactId, approved = true)
            }
        }
    }

    private fun scheduleSubscriptionRetry() {
        if (!connected || !subscriptionRetryScheduled.compareAndSet(false, true)) return
        retryHandler.postDelayed(subscriptionRetryRunnable, SUBSCRIPTION_RETRY_DELAY_MILLIS)
    }

    private fun cancelSubscriptionRetry() {
        retryHandler.removeCallbacks(subscriptionRetryRunnable)
        subscriptionRetryScheduled.set(false)
    }

    private fun invalidateSubscriptions() {
        subscriptionRecoveryState.invalidate()
        appContext?.let { AndroidAgentRecoveryWake.connectionChanged(it, false) }
        cancelSubscriptionRetry()
        retryHandler.removeCallbacks(topicRotationRefreshRunnable)
    }

    private fun scheduleTopicRotationRefresh() {
        retryHandler.removeCallbacks(topicRotationRefreshRunnable)
        if (connected) {
            val context = appContext
            val rendezvousDelay = context?.let {
                PhoneContactCard.nextRendezvousRefreshDelayMillis(it)
            }
            val delayMillis = listOfNotNull(
                GalaxySSILinkProtocol.topicRefreshDelayMillis(),
                rendezvousDelay
            ).minOrNull() ?: GalaxySSILinkProtocol.topicRefreshDelayMillis()
            retryHandler.postDelayed(
                topicRotationRefreshRunnable,
                delayMillis
            )
        }
    }

    private fun onTransportConnected(context: Context) {
        if (!setConnected(true)) return
        setSecureReady(false)
        cancelSubscriptionRetry()
        subscribe()
        scheduleTopicRotationRefresh()
        flushPendingPairingClaim()
        flushPendingOpaquePackets()
        if (initialOutboxRecoveryPrepared.compareAndSet(false, true)) {
            GalaxySSILinkDeliveryStore.makePendingImmediatelyRetryable(context)
        }
        scheduleOutboxRetries()
        scheduleConnectorStatusRequest()
        retryHandler.postDelayed(
            {
                requestConnectorStatuses(context)
            },
            800L
        )
    }

    private fun setConnected(value: Boolean): Boolean {
        if (connected == value) return false
        connected = value
        appContext?.let { AndroidAgentRecoveryWake.connectionChanged(it, isRequestReplyReady()) }
        listeners.forEach { it.onConnectionChanged(value) }
        return true
    }

    private fun setSecureReady(value: Boolean) {
        val ready = value && isRequestReplyReady()
        if (secureReady == ready) return
        secureReady = ready
        appContext?.let { AndroidAgentRecoveryWake.connectionChanged(it, ready) }
        if (ready) appContext?.let { AndroidAgentRecoveryWake.request(it) }
        listeners.forEach { it.onSecureChannelChanged(ready) }
    }
}
