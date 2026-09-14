package com.galaxyssi.watch

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.galaxyssi.chat.GalaxySSICrypto as Crypto
import com.galaxyssi.chat.GalaxySSILinkProtocol as Link
import com.galaxyssi.chat.WatchWireChunks
import org.eclipse.paho.client.mqttv3.*
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class WatchApplication : Application() {
    val repository by lazy { WatchRepository(this) }
}

/** A single serial worker owns Signal session mutations and transport state. */
class WatchRepository(private val context: Context) {
    val store = WatchStore(context)
    val conversationVisibility = WatchConversationVisibility()
    private val worker = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val apiWorker = Executors.newFixedThreadPool(2)
    private val api = WatchApi()
    private val apiCalls = java.util.concurrent.ConcurrentHashMap<String, WatchApiOperation>()
    private val listeners = CopyOnWriteArraySet<() -> Unit>()
    private val chunks = WatchWireChunks()
    private var mqtt: MqttAsyncClient? = null
    private var subscribed = emptySet<String>()
    private var pendingPairing: JSONObject? = null
    private var lastPairing = 0L
    private var lastStatus = 0L
    private var visible = false
    private var monitoring = false
    private var hiddenAt = 0L
    @Volatile var connection = ConnectionState.DISCONNECTED
        private set
    @Volatile var errorResource = 0
        private set
    private val seen = java.util.concurrent.ConcurrentHashMap<String, Long>()

    init {
        worker.execute {
            runCatching {
                com.galaxyssi.chat.WatchSignalUpgrade.prepare(context)
                Crypto.initialize(context)
                // HTTP operations are never automatically replayed after process
                // death, since a provider may have accepted and billed the request.
                store.tasks().filter { it.desktopId == "api" && !it.state.terminal }.forEach {
                    store.save(it.copy(state = TaskState.FAILED, progress = context.getString(R.string.api_interrupted)))
                }
                store.inbox.entries().forEach { (key, raw) ->
                    val entry = JSONObject(raw)
                    if (!entry.optBoolean("applied")) entry.optJSONObject("payload")?.let {
                        applyPayload(entry.getString("desktop"), it, live = false)
                        store.inbox.writeString(key, entry.put("applied", true).toString())
                    }
                }
            }.onFailure { errorResource = R.string.storage_error; changed() }
        }
        worker.scheduleWithFixedDelay({
            runCatching { tick() }.onFailure { connection = ConnectionState.ERROR; changed() }
        }, 1, 10, TimeUnit.SECONDS)
    }

    fun listen(listener: () -> Unit) { listeners.add(listener) }
    fun unlisten(listener: () -> Unit) { listeners.remove(listener) }
    private fun changed() { main.post { listeners.forEach { it() } } }
    fun foreground(value: Boolean) { worker.execute { visible = value; hiddenAt = System.currentTimeMillis(); tick() } }
    fun monitor(value: Boolean) { worker.execute { monitoring = value; tick() } }
    fun links(): List<Link.ServerLink> = Link.allServerLinks(context)
    fun online(desktop: String): Boolean = connection == ConnectionState.BROKER_CONNECTED &&
        System.currentTimeMillis() - (seen[desktop] ?: 0) < 90_000
    fun refresh() = worker.execute { lastStatus = 0; errorResource = 0; tick(); changed() }
    fun activeTasks(): Boolean = store.tasks().any { !it.state.terminal }

    private fun tick() {
        if (!visible && !monitoring && System.currentTimeMillis() - hiddenAt > 15_000) {
            mqtt?.let { if (it.isConnected) it.disconnect().waitForCompletion(3000) }
            connection = ConnectionState.DISCONNECTED
            seen.clear()
            subscribed = emptySet()
            return
        }
        if (!visible && !monitoring) return
        if (links().isEmpty() && pendingPairing == null) return
        connect()
        if (mqtt?.isConnected != true) return
        subscribe()
        pendingPairing?.let { qr ->
            if (!Link.validatePairingQr(qr)) { pendingPairing = null; errorResource = R.string.pairing_expired; changed() }
            else if (System.currentTimeMillis() - lastPairing > 20_000) claim(qr)
        }
        if (System.currentTimeMillis() - lastStatus > 30_000) {
            lastStatus = System.currentTimeMillis()
            links().filter { it.paired }.forEach {
                sendEphemeral(it, JSONObject().put("type", "connector_status_request")
                    .put("contact_id", "system").put("desktop_id", it.desktopId)
                    .put("request_capability_manifest", true).put("capability_manifest_version", 0))
            }
        }
        flush()
        changed()
    }

    private fun connect() {
        if (mqtt?.isConnected == true) return
        connection = ConnectionState.CONNECTING; changed()
        val client = mqtt ?: MqttAsyncClient("ssl://broker.emqx.io:8883",
            "watch-${Crypto.localIdentitySha256().take(18)}", MemoryPersistence()).also { mqtt = it }
        client.setCallback(object : MqttCallback {
            override fun connectionLost(cause: Throwable?) {
                worker.execute { subscribed = emptySet(); seen.clear(); connection = ConnectionState.DISCONNECTED; changed() }
            }
            override fun deliveryComplete(token: IMqttDeliveryToken?) = Unit
            override fun messageArrived(topic: String, message: MqttMessage) {
                if (message.payload.size > 1024 * 1024) return
                val bytes = message.payload.copyOf()
                worker.execute { runCatching { incoming(topic, bytes) }.onFailure {
                    errorResource = R.string.message_rejected; changed()
                } }
            }
        })
        try {
            client.connect(MqttConnectOptions().apply {
                isCleanSession = true
                isAutomaticReconnect = false
                connectionTimeout = 8
                keepAliveInterval = 45
                isHttpsHostnameVerificationEnabled = true
            }).waitForCompletion(10_000)
            connection = ConnectionState.BROKER_CONNECTED
            subscribed = emptySet()
        } catch (_: Exception) { connection = ConnectionState.ERROR }
        changed()
    }

    private fun subscribe() {
        val client = mqtt ?: return
        val topics = links().flatMap { it.routes.receiveWindow }.toSet()
        val removed = subscribed - topics
        if (removed.isNotEmpty()) client.unsubscribe(removed.toTypedArray()).waitForCompletion(8000)
        val added = topics - subscribed
        if (added.isNotEmpty()) client.subscribe(added.toTypedArray(), IntArray(added.size) { 1 }).waitForCompletion(8000)
        subscribed = topics
    }

    fun inspectPairing(raw: String): JSONObject {
        require(raw.length <= 32_000)
        val source = JSONObject(raw)
        val qr = Link.normalizePairingQr(source) ?: source
        require(Link.validatePairingQr(qr))
        return qr
    }

    fun pair(qr: JSONObject, done: (Boolean) -> Unit) { worker.execute {
        val result = runCatching {
            Crypto.initialize(context)
            require(Link.validatePairingQr(qr) && Crypto.verifyPcIdentityFromQr(qr.toString()))
            val existing = Link.serverLink(context, qr.getString("desktop_id"))
            Link.ensureServerLink(context, qr, rotateClientRoute = Link.shouldRotateClientRoute(existing, qr))
            pendingPairing = JSONObject(qr.toString()); lastPairing = 0
            errorResource = 0
            tick()
            true
        }.getOrElse { errorResource = R.string.pairing_invalid; false }
        changed(); main.post { done(result) }
    } }

    private fun claim(qr: JSONObject) {
        val link = Link.serverLink(context, qr.getString("desktop_id")) ?: return
        val payload = JSONObject().put("protocol", Link.NAME).put("version", Link.VERSION)
            .put("type", "galaxyssi_pairing_claim").put("pairing_token", qr.getString("pairing_token"))
            .put("from", Crypto.localGalaxySSIId()).put("signal_name", Crypto.localGalaxySSIId())
            .put("signal_device_id", 1).put("client_route_id", link.routes.clientRouteId)
            .put("client_name", "GalaxySSI Watch").put("device_name", Build.MODEL)
            .put("platform", "android").put("device_category", "watch")
            .put("client_device_id", Crypto.localGalaxySSIId()).put("device_model", Build.MODEL)
            .put("device_manufacturer", Build.MANUFACTURER).put("platform_version", Build.VERSION.RELEASE)
            .put("identity_fingerprint", Crypto.localIdentitySha256())
            .put("identity_public_key", Crypto.localIdentityPublicKey())
            .put("signal_bundle", Crypto.localSignalBundleJson())
            .put("requested_access_profile", Link.ACCESS_RESTRICTED).put("time", System.currentTimeMillis())
        mqtt!!.publish(qr.getString("pairing_topic"), Link.encryptPairingClaim(payload, qr).toByteArray(), 1, false)
            .waitForCompletion(8000)
        lastPairing = System.currentTimeMillis()
    }

    fun send(prompt: String, previous: WatchTask?, done: (WatchTask?) -> Unit) {
        if (previous?.desktopId == "api" || (previous == null && store.apiPreferred)) {
            sendApi(prompt, previous, done); return
        }
        worker.execute {
        var stagedTask: WatchTask? = null
        val result = runCatching {
            val desktop = previous?.desktopId ?: store.selectedDesktop
            val link = Link.serverLink(context, desktop) ?: error("No route")
            require(link.paired && Link.isCryptographicallyReady(context, link))
            val agent = previous?.agentId ?: store.selectedAgent
            require(store.agents(desktop).any { it.id == agent })
            require(store.tasks().count { !it.state.terminal } < 20)
            val task = WatchTask.create(desktop, link.routes.clientRouteId, agent, prompt,
                previous?.conversationId ?: UUID.randomUUID().toString())
            // Persist the stable identity before any network side effect.
            store.save(task)
            stagedTask = task
            queue(link, task.request(Locale.getDefault().toLanguageTag()), task.id)
            store.draft = ""
            runCatching { tick() }
            task
        }.getOrElse {
            stagedTask?.let { staged ->
                if (!store.outbox.contains(staged.messageId)) store.save(staged.copy(state = TaskState.FAILED))
            }
            errorResource = R.string.send_failed; null
        }
        changed(); main.post { done(result) }
    } }

    private fun sendApi(prompt: String, previous: WatchTask?, done: (WatchTask?) -> Unit) {
        worker.execute {
            val started = runCatching {
                val profile = store.apiProfile ?: error("Missing API settings")
                require(previous == null || previous.routeId == profile.id)
                require(apiCalls.size < 2)
                val task = WatchTask.create("api", profile.id, profile.model, prompt,
                    previous?.conversationId ?: UUID.randomUUID().toString()).copy(state = TaskState.RUNNING)
                val useWeb = store.webSearch
                val history = store.tasks()
                val call = WatchApiOperation()
                store.save(if (useWeb) task.copy(progress = context.getString(R.string.web_searching)) else task); store.draft = ""; apiCalls[task.id] = call
                main.post { done(task) }; changed()
                apiWorker.execute {
                    val outcome = runCatching {
                        val evidence = if (useWeb) WatchWebSearch().search(prompt, call) else null
                        call.checkActive()
                        if (evidence != null) worker.execute {
                            store.task(task.id)?.takeIf { !it.state.terminal }?.let {
                                store.save(it.copy(progress = context.getString(R.string.web_answering, evidence.hits.size)))
                                changed()
                            }
                        }
                        val reply = api.execute(call.attach(api.request(profile, task, history, evidence?.json())))
                        if (evidence == null) reply else reply + "\n\n" +
                            context.getString(R.string.web_sources, evidence.retrievedAt) + "\n" + evidence.sources()
                    }
                    worker.execute {
                        apiCalls.remove(task.id)
                        val latest = store.task(task.id) ?: return@execute
                        if (!latest.state.terminal) {
                            val result = outcome.fold(
                                onSuccess = { latest.copy(state = TaskState.COMPLETED, reply = it) },
                                onFailure = { latest.copy(state = TaskState.FAILED,
                                    progress = context.getString((it as? ApiFailure)?.reason ?: R.string.api_request_error)) })
                            store.save(result)
                            main.post { WatchNotifications.completed(context, result) }
                            changed()
                        }
                    }
                }
            }
            if (started.isFailure) { errorResource = R.string.api_invalid; changed(); main.post { done(null) } }
        }
    }

    private fun queue(link: Link.ServerLink, payload: JSONObject, taskId: String = "") {
        val envelope = Link.makeEnvelope(payload, Crypto.localGalaxySSIId(), link.desktopId)
        val encrypted = Crypto.encryptPayloadForDesktop(link.desktopId, envelope) ?: error("No secure session")
        store.outbox.writeString(envelope.getString("message_id"), JSONObject()
            .put("desktop", link.desktopId).put("client_route_id", link.routes.clientRouteId)
            .put("wire", encrypted.toString()).put("task", taskId).put("type", payload.optString("type"))
            .put("expires", envelope.getLong("expires_at")).put("attempts", 0).put("next", 0).toString())
    }

    private fun flush() {
        val client = mqtt ?: return
        if (!client.isConnected) return
        store.outbox.entries().take(24).forEach { (id, raw) ->
            val entry = JSONObject(raw)
            val link = Link.serverLink(context, entry.getString("desktop"))
            if (link == null || !link.paired || link.routes.clientRouteId != entry.optString("client_route_id") ||
                System.currentTimeMillis() >= entry.optLong("expires")) {
                store.outbox.remove(id)
                store.task(entry.optString("task"))?.let { if (!it.state.terminal) store.save(it.copy(state = TaskState.FAILED)) }
                return@forEach
            }
            if (entry.optInt("attempts") >= 6 || System.currentTimeMillis() < entry.optLong("next")) return@forEach
            val attempts = entry.optInt("attempts") + 1
            entry.put("attempts", attempts).put("next", System.currentTimeMillis() + minOf(120_000L, 5000L * (1L shl attempts)))
            store.outbox.writeString(id, entry.toString())
            val wire = Link.sealWirePacket(entry.getString("wire"), link.routes.linkSecret)
            client.publish(link.routes.up, wire.toByteArray(), 1, false).waitForCompletion(8000)
            store.task(entry.optString("task"))?.let {
                if (entry.optString("type") == "text" && it.state == TaskState.QUEUED) store.save(it.copy(state = TaskState.SENT))
            }
        }
    }

    fun retry(task: WatchTask) { worker.execute {
        val raw = store.outbox.readString(task.messageId, "")
        if (raw.isNotBlank()) store.outbox.writeString(task.messageId, JSONObject(raw).put("attempts", 0).put("next", 0).toString())
        runCatching { tick() }; changed()
    } }

    fun cancel(task: WatchTask) { worker.execute {
        runCatching {
            val current = store.task(task.id) ?: return@runCatching
            if (current.state.terminal || current.state == TaskState.STOP_REQUESTED) return@runCatching
            if (current.desktopId == "api") {
                apiCalls.remove(current.id)?.cancel()
                store.save(current.copy(state = TaskState.CANCELLED, progress = context.getString(R.string.api_cancelled)))
                return@runCatching
            }
            if (current.state == TaskState.QUEUED) {
                val queued = store.outbox.readString(current.messageId, "")
                if (queued.isNotBlank() && JSONObject(queued).optInt("attempts") == 0) {
                    store.outbox.remove(current.messageId)
                    store.save(current.copy(state = TaskState.CANCELLED))
                    return@runCatching
                }
            }
            val link = Link.serverLink(context, current.desktopId) ?: return@runCatching
            require(link.routes.clientRouteId == current.routeId)
            val request = current.request(Locale.getDefault().toLanguageTag())
                .put("type", "agent_task_cancel").put("message_id", UUID.randomUUID().toString()).removeContent()
            queue(link, request, current.id)
            store.save(current.copy(state = TaskState.STOP_REQUESTED))
            tick()
        }.onFailure { errorResource = R.string.send_failed }
        changed()
    } }

    private fun JSONObject.removeContent(): JSONObject { remove("content"); return this }

    fun forget(desktop: String) { worker.execute {
        Link.removeServer(context, desktop); Crypto.clearDesktopTrust(context, desktop)
        store.forgetAgents(desktop); seen.remove(desktop)
        if (store.selectedDesktop == desktop) { store.selectedDesktop = ""; store.selectedAgent = "" }
        store.tasks().filter { it.desktopId == desktop && !it.state.terminal }.forEach { store.save(it.copy(state = TaskState.FAILED)) }
        runCatching { subscribe() }; changed()
    } }

    private fun incoming(topic: String, bytes: ByteArray) {
        val link = links().firstOrNull { topic in it.routes.receiveWindow } ?: return
        val raw = JSONObject(Link.openWirePacket(bytes, link.routes.linkSecret))
        if (raw.optString("type") == "pairing_confirmed") {
            require(raw.optString("protocol") == Link.NAME && raw.optInt("version") == Link.VERSION)
            require(raw.optString("desktop_id") == link.desktopId && raw.optString("client_route_id") == link.routes.clientRouteId)
            require(raw.optString("desktop_fingerprint") == link.desktopFingerprint)
            require(Crypto.verifiedDesktopFingerprint(link.desktopId) == link.desktopFingerprint)
            // A repeated confirmation must never reset a live ratchet.
            if (!link.paired || !Crypto.hasDesktopSession(context, link.desktopId)) {
                require(Crypto.processPcBundleForDesktop(link.desktopId, raw.getJSONObject("signal_bundle"), link.desktopFingerprint))
                Link.markPaired(context, link.desktopId, raw.optJSONObject("pairing_access"))
            }
            pendingPairing = null
            seen[link.desktopId] = System.currentTimeMillis()
            raw.optJSONArray("connector_agents")?.let { store.saveAgents(link.desktopId, it) }
            if (store.selectedDesktop.isBlank()) store.selectedDesktop = link.desktopId
            lastStatus = 0; changed(); return
        }
        require(raw.optString("from") == link.desktopId && raw.optString("to") == Crypto.localGalaxySSIId())
        val wire = chunks.accept(link.desktopId, raw) ?: return
        require(wire.optString("from") == link.desktopId && wire.optString("to") == Crypto.localGalaxySSIId())
        require(wire.optString("scheme") == "signal" && Link.isCryptographicallyReady(context, link))
        val digest = MessageDigest.getInstance("SHA-256").digest((link.desktopId + wire.getString("body")).toByteArray())
            .joinToString("") { "%02x".format(it) }
        val cached = store.inbox.readString(digest, "")
        if (cached.isNotBlank()) {
            val entry = JSONObject(cached)
            entry.optJSONObject("payload")?.let {
                if (!entry.optBoolean("applied")) applyPayload(link.desktopId, it)
                store.inbox.writeString(digest, entry.put("applied", true).toString())
                receipt(link, it)
            }
            return
        }
        val envelope = Crypto.decryptEnvelope(wire) ?: return
        require(envelope.optString("source_id") == link.desktopId && envelope.optString("target_id") == Crypto.localGalaxySSIId())
        val payload = Link.unwrapEnvelope(envelope) ?: return
        val entry = JSONObject().put("desktop", link.desktopId).put("payload", payload).put("time", System.currentTimeMillis())
        store.inbox.writeString(digest, entry.toString())
        applyPayload(link.desktopId, payload)
        store.inbox.writeString(digest, entry.put("applied", true).toString())
        receipt(link, payload)
        val keys = store.inbox.oldestKeys("", 2100)
        if (keys.size > 2000) store.inbox.removeAll(keys.take(keys.size - 2000))
    }

    private fun applyPayload(desktop: String, payload: JSONObject, live: Boolean = true) {
        if (live) seen[desktop] = System.currentTimeMillis()
        payload.optJSONArray("connector_agents")?.let { store.saveAgents(desktop, it) }
        if (payload.optString("type") == "pairing_revoked") { forget(desktop); return }
        if (payload.optString("type") == "delivery_ack") {
            val id = payload.optString("transport_message_id")
            val raw = store.outbox.readString(id, "")
            if (raw.isNotBlank() && payload.optString("delivery_status") == "accepted") {
                val queued = JSONObject(raw)
                if (queued.optString("desktop") == desktop) {
                    store.outbox.remove(id)
                    store.task(queued.optString("task"))?.let {
                        if (it.state in setOf(TaskState.QUEUED, TaskState.SENT)) store.save(it.copy(state = TaskState.ACCEPTED))
                    }
                }
            }
        } else {
            store.task(payload.optString("task_id"))?.let { old ->
                val updated = old.reduce(desktop, payload)
                if (old != updated) {
                    store.save(updated); store.outbox.remove(old.messageId)
                    if (live && !old.state.terminal && updated.state.terminal) main.post { WatchNotifications.completed(context, updated) }
                }
            }
        }
        changed()
    }

    private fun receipt(link: Link.ServerLink, payload: JSONObject) {
        if (payload.optString("type") == "delivery_ack") return
        sendEphemeral(link, JSONObject().put("type", "delivery_ack")
            .put("transport_message_id", payload.getString("message_id"))
            .put("source_message_id", payload.getString("message_id")).put("delivery_status", "accepted"))
    }

    private fun sendEphemeral(link: Link.ServerLink, payload: JSONObject) {
        val client = mqtt ?: return
        if (!client.isConnected) return
        val envelope = Link.makeEnvelope(payload, Crypto.localGalaxySSIId(), link.desktopId)
        val encrypted = Crypto.encryptPayloadForDesktop(link.desktopId, envelope) ?: return
        client.publish(link.routes.up, Link.sealWirePacket(encrypted.toString(), link.routes.linkSecret).toByteArray(), 1, false)
    }
}
