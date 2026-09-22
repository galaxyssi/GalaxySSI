package com.galaxyssi.watch

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.galaxyssi.chat.GalaxySSICrypto as Crypto
import com.galaxyssi.chat.GalaxySSILinkProtocol as Link
import com.galaxyssi.chat.WatchLinkTransport
import org.eclipse.paho.client.mqttv3.*
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class WatchApplication : com.galaxyssi.chat.GalaxySSIApplication() {
    val repository by lazy { WatchRepository(this) }
    private var foregroundActivity: android.app.Activity? = null
    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(object : android.app.Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: android.app.Activity) { foregroundActivity = activity }
            override fun onActivityPaused(activity: android.app.Activity) { if (foregroundActivity === activity) foregroundActivity = null }
            override fun onActivityCreated(a: android.app.Activity, b: android.os.Bundle?) = Unit
            override fun onActivityStarted(a: android.app.Activity) = Unit
            override fun onActivityStopped(a: android.app.Activity) = Unit
            override fun onActivitySaveInstanceState(a: android.app.Activity, b: android.os.Bundle) = Unit
            override fun onActivityDestroyed(a: android.app.Activity) = Unit
        })
    }
    fun openContactRequest(id: String): Boolean {
        val activity = foregroundActivity ?: return false
        activity.startActivity(android.content.Intent(activity, WatchContactsActivity::class.java)
            .putExtra("peer", id).putExtra("request", true)
            .addFlags(android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP or android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP))
        return true
    }
}

/** A single serial worker owns Signal session mutations and transport state. */
class WatchRepository(private val context: Context) {
    val store = WatchStore(context)
    val conversationVisibility = WatchConversationVisibility()
    private val worker = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val apiState = Executors.newSingleThreadExecutor()
    private val apiWorker = Executors.newFixedThreadPool(2)
    private val uiStorage = Executors.newSingleThreadExecutor()
    private val api = WatchApi()
    private val apiCalls = java.util.concurrent.ConcurrentHashMap<String, WatchApiOperation>()
    private val listeners = CopyOnWriteArraySet<() -> Unit>()
    val contacts = com.galaxyssi.chat.WatchContacts(context, ::changed) { person, text, request ->
        main.post {
            if (!request || !(context.applicationContext as WatchApplication).openContactRequest(person.id))
                WatchContactNotifications.show(context, person, text, request)
        }
    }
    fun contactAction(action: com.galaxyssi.chat.WatchContacts.() -> Unit, done: (Boolean) -> Unit = {}) {
        worker.execute {
            val success = runCatching { contacts.action(); connect(); mqtt?.refresh(); mqtt?.let(contacts::tick) }
                .onFailure { android.util.Log.w("WatchContacts", "Contact action failed", it) }.isSuccess
            main.post { done(success) }; changed()
        }
    }
    private var mqtt: WatchLinkTransport? = null
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
    private val recovery by lazy { WatchRemoteRecovery(context,
        publish = { desktop, payload -> worker.submit<Boolean> {
            Link.serverLink(context, desktop)?.let { sendEphemeral(it, payload) } ?: false
        }.get() },
        accept = { desktop, payload -> worker.submit { applyPayload(desktop, payload) }.get() },
        current = store::task) }

    init {
        apiState.execute {
            runCatching {
                // HTTP operations are never automatically replayed after process
                // death, since a provider may have accepted and billed the request.
                store.tasks().filter { (it.desktopId == "api" || it.localOperation == "location") && !it.state.terminal }.forEach {
                    store.save(it.copy(state = TaskState.FAILED, progress = context.getString(R.string.api_interrupted)))
                }
                changed()
            }.onFailure { errorResource = R.string.storage_error; changed() }
        }
        worker.execute {
            runCatching {
                store.tasks()
                changed()
                com.galaxyssi.chat.WatchSignalUpgrade.prepare(context)
                Crypto.initialize(context)
                contacts.load()
                store.inbox.entries().forEach { (key, raw) ->
                    val entry = JSONObject(raw)
                    entry.optJSONObject("payload")?.let {
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

    fun saveDraft(value: String) { uiStorage.execute { store.draft = value } }
    fun saveActiveTask(id: String) { uiStorage.execute { store.activeTask = id } }
    fun markConversationRead(turns: List<WatchTask>, current: WatchTask) {
        uiStorage.execute {
            WatchNotifications.dismissConversation(context, turns, current)
            val previous = store.cachedReadRevision
            store.markRead(turns)
            if (previous != store.cachedReadRevision) changed()
        }
    }
    internal fun awaitUiStorage() { uiStorage.submit {}.get(10, TimeUnit.SECONDS) }

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
    internal fun transportDiagnostics() = mqtt?.diagnostics().orEmpty()

    private fun tick() {
        if (!visible && !monitoring && System.currentTimeMillis() - hiddenAt > 15_000) {
            mqtt?.close(); mqtt = null
            connection = ConnectionState.DISCONNECTED
            seen.clear()
            subscribed = emptySet()
            return
        }
        if (!visible && !monitoring) return
        if (links().isEmpty() && pendingPairing == null && !contacts.hasRoutes()) return
        connect()
        if (mqtt?.isConnected != true) return
        subscribe()
        mqtt?.refresh()
        mqtt?.let(contacts::tick)
        pendingPairing?.let { qr ->
            if (!Link.validatePairingQr(qr)) { pendingPairing = null; errorResource = R.string.pairing_expired; changed() }
            else if (System.currentTimeMillis() - lastPairing > 20_000) claim(qr)
        }
        if (System.currentTimeMillis() - lastStatus > 30_000) {
            var requested = false
            links().filter { it.paired }.forEach {
                if (sendEphemeral(it, JSONObject().put("type", "connector_status_request")
                    .put("contact_id", "system").put("desktop_id", it.desktopId)
                    .put("request_capability_manifest", true).put("capability_manifest_version", 0))) requested = true
            }
            if (requested) lastStatus = System.currentTimeMillis()
        }
        flush()
        recovery.refresh(store.tasks().filter { task -> links().any { it.desktopId == task.desktopId && mqtt?.ready(it) == true } })
        changed()
    }

    private fun connect() {
        if (mqtt != null) return
        connection = ConnectionState.CONNECTING; changed()
        val transport = WatchLinkTransport(context,
            onState = { connected -> worker.execute {
                connection = if (connected) ConnectionState.BROKER_CONNECTED else ConnectionState.DISCONNECTED
                if (!connected) seen.clear()
                changed()
            } },
            onControl = { desktop, payload -> worker.submit { pairingControl(desktop, payload) }.get() },
            onPayload = { desktop, payload -> worker.submit {
                if (contacts.isPeer(desktop)) contacts.accept(desktop, payload) else applyPayload(desktop, payload)
            }.get() },
            onStored = { desktop, id, hash -> worker.execute {
                if (contacts.isPeer(desktop)) contacts.stored(desktop, id, hash) else received(desktop, id, hash)
            } },
            onReady = { worker.execute { runCatching { tick() }; changed() } }, contacts = contacts,
            onContactControl = { topic, payload -> worker.submit {
                if (topic == "recovery") contacts.requestRecovery(payload.getString("peer")) else contacts.control(topic, payload)
                mqtt?.refresh(); mqtt?.let(contacts::tick)
            }.get() })
        mqtt = transport
        transport.start()
    }

    private fun subscribe() {
        val topics = links().flatMap { it.routes.receiveWindow }.toSet()
        if (subscribed != topics) { mqtt?.refresh(); subscribed = topics }
    }

    private fun received(desktop: String, id: String, hash: String) {
        val raw = store.outbox.readString(id, "")
        if (raw.isBlank()) return
        val entry = JSONObject(raw)
        val link = Link.serverLink(context, desktop) ?: return
        if (entry.optString("desktop") != desktop || entry.optString("client_route_id") != link.routes.clientRouteId ||
            mqtt?.hash(entry.getString("wire")) != hash) return
        store.outbox.remove(id)
        store.task(entry.optString("task"))?.let {
            if (it.state in setOf(TaskState.QUEUED, TaskState.SENT)) store.save(it.copy(state = TaskState.ACCEPTED))
        }
        seen[desktop] = System.currentTimeMillis(); changed()
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
                contacts.load()
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
            .also { WatchDeviceName.addPairingFields(it, WatchDeviceName.current(context)) }
            .put("platform", "android").put("device_category", "watch")
            .put("client_device_id", Crypto.localGalaxySSIId()).put("device_model", Build.MODEL)
            .put("device_manufacturer", Build.MANUFACTURER).put("platform_version", Build.VERSION.RELEASE)
            .put("identity_fingerprint", Crypto.localIdentitySha256())
            .put("identity_public_key", Crypto.localIdentityPublicKey())
            .put("signal_bundle", Crypto.localSignalBundleJson())
            .put("requested_access_profile", Link.ACCESS_RESTRICTED).put("time", System.currentTimeMillis())
        if (mqtt!!.bootstrap(qr.getString("pairing_topic"), Link.encryptPairingClaim(payload, qr), link.routes.receiveWindow))
            lastPairing = System.currentTimeMillis()
    }

    fun send(prompt: String, previous: WatchTask?, done: (WatchTask?) -> Unit) {
        if (WatchLocationIntent.matches(prompt)) { sendLocation(prompt, previous, done); return }
        if (previous?.desktopId == "watch-location") { send(prompt, null, done); return }
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

    private fun sendLocation(prompt: String, previous: WatchTask?, done: (WatchTask?) -> Unit) {
        apiState.execute {
            val profile = store.apiProfile
            val desktop = previous?.desktopId ?: if (store.apiPreferred && profile != null) "api" else "watch-location"
            val task = WatchTask.create(desktop, previous?.routeId ?: profile?.id ?: "local",
                previous?.agentId ?: profile?.model ?: "Location", prompt, previous?.conversationId ?: UUID.randomUUID().toString())
                .copy(state = TaskState.RUNNING, localOperation = "location", progress = context.getString(R.string.location_locating))
            val operation = WatchApiOperation()
            apiCalls[task.id] = operation; store.save(task); saveDraft(""); main.post { done(task) }; changed()
            apiWorker.execute {
                val outcome = runCatching { WatchLocation(context).answer(operation) { value ->
                    apiState.execute { store.task(task.id)?.takeIf { !it.state.terminal }?.let { store.save(it.copy(progress = value)); changed() } }
                } }
                apiState.execute {
                    apiCalls.remove(task.id)
                    val latest = store.task(task.id) ?: return@execute
                    if (!latest.state.terminal) {
                        val result = outcome.fold(
                            onSuccess = { latest.copy(state = TaskState.COMPLETED, reply = it.reply, location = it.fix.json()) },
                            onFailure = { latest.copy(state = TaskState.FAILED, progress = context.getString((it as? ApiFailure)?.reason ?: R.string.location_unavailable)) })
                        store.save(result); changed(); main.post { WatchNotifications.completed(context, result) }
                    }
                }
            }
        }
    }

    private fun sendApi(prompt: String, previous: WatchTask?, done: (WatchTask?) -> Unit) {
        apiState.execute {
            val started = runCatching {
                val profile = store.apiProfile ?: error("Missing API settings")
                require(previous == null || previous.routeId == profile.id)
                require(apiCalls.size < 2)
                val task = WatchTask.create("api", profile.id, profile.model, prompt,
                    previous?.conversationId ?: UUID.randomUUID().toString()).copy(state = TaskState.RUNNING)
                val useWeb = store.webSearch
                val history = store.tasks()
                val call = WatchApiOperation()
                store.save(if (useWeb) task.copy(progress = context.getString(R.string.web_planning)) else task); saveDraft(""); apiCalls[task.id] = call
                main.post { done(task) }; changed()
                apiWorker.execute {
                    val outcome = runCatching {
                        if (useWeb) WatchWebLookup(context, api).answer(profile, task, history, call) { progress ->
                            apiState.execute {
                                store.task(task.id)?.takeIf { !it.state.terminal }?.let {
                                    store.save(it.copy(progress = progress)); changed()
                                }
                            }
                        } else api.execute(call.attach(api.request(profile, task, history)))
                    }
                    apiState.execute {
                        apiCalls.remove(task.id)
                        val latest = store.task(task.id) ?: return@execute
                        if (!latest.state.terminal) {
                            val result = outcome.fold(
                                onSuccess = { latest.copy(state = TaskState.COMPLETED, reply = it) },
                                onFailure = {
                                    android.util.Log.w("WatchApi", "turn_failed type=${it.javaClass.simpleName}")
                                    val reason = (it as? ApiFailure)?.reason ?: when (it) {
                                        is java.net.SocketTimeoutException -> R.string.api_timeout_error
                                        is java.io.IOException -> R.string.api_network_error
                                        else -> R.string.api_request_error
                                    }
                                    latest.copy(state = TaskState.FAILED,
                                        progress = context.getString(reason) + latest.progress.takeIf { p -> p.isNotBlank() }?.let { p -> "\n$p" }.orEmpty())
                                })
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
            if (!client.ready(link) || System.currentTimeMillis() < entry.optLong("next")) return@forEach
            val attempts = entry.optInt("attempts") + 1
            if (!client.publish(link, id, entry.getString("wire"), entry.optString("type"))) return@forEach
            entry.put("attempts", attempts).put("next", System.currentTimeMillis() + minOf(120_000L, 5000L * (1L shl minOf(attempts, 5))))
            store.outbox.writeString(id, entry.toString())
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

    fun cancel(task: WatchTask) { (if (task.desktopId == "api" || task.localOperation == "location") apiState else worker).execute {
        runCatching {
            val current = store.task(task.id) ?: return@runCatching
            if (current.state.terminal || current.state == TaskState.STOP_REQUESTED) return@runCatching
            if (current.desktopId == "api" || current.localOperation == "location") {
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
                .put("task_id", current.remoteTaskId.ifBlank { current.id })
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
        runCatching { mqtt?.refresh(); subscribe() }; changed()
    } }

    private fun pairingControl(desktop: String, raw: JSONObject) {
        val link = Link.serverLink(context, desktop) ?: return
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
            mqtt?.refresh(); lastStatus = 0; changed(); return
        }
    }

    private fun applyPayload(desktop: String, payload: JSONObject, live: Boolean = true) {
        if (live) seen[desktop] = System.currentTimeMillis()
        if (recovery.receive(desktop, payload)) return
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
            store.tasks().firstOrNull { it.matches(desktop, payload) }?.let { old ->
                val updated = old.reduce(desktop, payload)
                if (old != updated) {
                    store.save(updated); store.outbox.remove(old.messageId)
                    if (updated.state.terminal && updated.reply.isNotBlank()) {
                        com.galaxyssi.chat.AgentResultReceipt.from(payload, desktop)?.let { receipt ->
                            Link.serverLink(context, desktop)?.let { link ->
                                queue(link, receipt.payload().put("message_id", receipt.id))
                            }
                        }
                    }
                    if (live && !old.state.terminal && updated.state.terminal) main.post { WatchNotifications.completed(context, updated) }
                }
            }
        }
        changed()
    }

    private fun sendEphemeral(link: Link.ServerLink, payload: JSONObject): Boolean {
        val client = mqtt ?: return false
        if (!client.isConnected || !client.ready(link)) return false
        val envelope = Link.makeEnvelope(payload, Crypto.localGalaxySSIId(), link.desktopId)
        val encrypted = Crypto.encryptPayloadForDesktop(link.desktopId, envelope) ?: return false
        return client.publish(link, envelope.getString("message_id"), encrypted.toString(), payload.optString("type"))
    }
}
