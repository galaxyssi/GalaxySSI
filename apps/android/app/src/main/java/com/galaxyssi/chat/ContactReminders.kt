package com.galaxyssi.chat

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** Only the authenticated peer transport may call receive(). Never routes through an Agent. */
internal object ContactReminders {
    private val executor = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "contact-reminders").apply { isDaemon = true } }
    private val expirations = mutableMapOf<String, ScheduledFuture<*>>()
    private val main = Handler(Looper.getMainLooper())
    private var store: ContactReminderStore? = null
    val observers = CopyOnWriteArraySet<(ContactReminder) -> Unit>()
    private fun db(context: Context) = store ?: ContactReminderStore(context).also { store = it }
    fun submit(block: () -> Unit) { executor.execute { runCatching(block).onFailure {
        android.util.Log.e("GalaxySSIReminder", "Reminder operation failed", it)
    } } }

    fun send(context: Context, contactId: String, result: (ContactReminder?) -> Unit) = submit {
        val app = context.applicationContext
        val updated = runCatching {
        if (!trusted(app, contactId)) return@runCatching null
        val now = System.currentTimeMillis()
        val value = ContactReminder(UUID.randomUUID().toString(), contactId, true, now,
            now + ContactReminderPolicy.LIFETIME_MS, "sending", ChatHistoryStore.reserveMessageId(app))
        update(app, value)
        val sent = runCatching { wire(app, value, "request") }.getOrDefault(false)
        val updated = value.copy(status = if (sent) "queued" else "failed")
        update(app, updated)
        updated
        }.getOrElse {
            android.util.Log.e("GalaxySSIReminder", "Could not send reminder", it)
            null
        }
        main.post { result(updated) }
    }

    fun receive(context: Context, contactId: String, payload: JSONObject): Boolean {
        if (payload.optString("type") != ContactReminderPolicy.TYPE) return false
        // Copy before leaving the MQTT dispatcher; it may mutate its envelope after return.
        val snapshot = JSONObject(payload.toString())
        submit {
            try { accept(context.applicationContext, contactId, snapshot) }
            catch (error: Exception) {
                GalaxySSIMqttClient.retryIncomingDelivery(snapshot.toString())
                throw error
            }
        }
        return true
    }

    private fun accept(app: Context, contactId: String, payload: JSONObject) {
        if (!trusted(app, contactId)) { complete(app, payload); return }
        val now = System.currentTimeMillis()
        val id = payload.optString("reminder_id")
        val created = payload.optLong("created_at")
        val expires = payload.optLong("expires_at")
        val event = payload.optString("reminder_action")
        if (!ContactReminderPolicy.valid(id, created, expires, now)) { complete(app, payload); return }
        val database = db(app)
        database.prune(now)
        val previous = database.get(id)
        if (previous != null && (previous.contactId != contactId || previous.createdAt != created ||
                previous.expiresAt != expires)) { complete(app, payload); return }
        if (event == "request") {
            if (previous != null) {
                if (!previous.outgoing) wire(app, previous, previous.status.takeIf {
                    it in ContactReminderPolicy.receipts } ?: "received")
                complete(app, payload)
                return
            }
            val allowed = preferences(app).getBoolean("enabled", true)
            val quiet = ContactReminderNotifications.callActive(app)
            val value = ContactReminder(id, contactId, false, created, expires,
                if (!allowed) "disabled" else if (quiet) "quiet" else "received",
                ChatHistoryStore.reserveMessageId(app))
            // Persist before any sound/UI side effect: redelivery must never ring twice.
            update(app, value)
            wire(app, value, value.status)
            if (allowed) main.post { ContactReminderNotifications.show(app, value) }
        } else if (event == "cancelled" && previous == null) {
            database.put(ContactReminder(id, contactId, false, created, expires, "cancelled"))
        } else if (previous != null && ((previous.outgoing && event in ContactReminderPolicy.receipts) ||
                (!previous.outgoing && event == "cancelled"))) {
            update(app, previous.copy(status = ContactReminderPolicy.next(previous.status, event, previous.outgoing)))
        }
        complete(app, payload)
    }

    fun act(context: Context, id: String, action: String) = submit {
        val app = context.applicationContext
        val old = db(app).get(id) ?: return@submit
        if (old.terminal) return@submit
        if (old.outgoing && action != "cancelled") return@submit
        if (!old.outgoing && action !in setOf("muted", "acknowledged", "dismissed")) return@submit
        val status = if (System.currentTimeMillis() >= old.expiresAt) "expired" else
            ContactReminderPolicy.next(old.status, action, old.outgoing)
        val value = old.copy(status = status)
        update(app, value)
        if (status != "expired" && trusted(app, old.contactId)) wire(app, value, action)
    }

    fun load(context: Context, id: String, callback: (ContactReminder?) -> Unit) = submit {
        val app = context.applicationContext
        var value = db(app).get(id)
        if (value != null && !value.terminal &&
            (System.currentTimeMillis() >= value.expiresAt || !trusted(app, value.contactId))) {
            value = value.copy(status = "expired")
            update(app, value)
        }
        val loaded = value
        main.post { callback(loaded) }
    }

    private fun update(app: Context, value: ContactReminder) {
        db(app).put(value)
        armExpiry(app, value)
        history(app, value)
        main.post {
            if (value.terminal || value.status == "muted") ContactReminderNotifications.cancel(app, value.id)
            observers.forEach { it(value) }
        }
    }

    private fun armExpiry(app: Context, value: ContactReminder) {
        expirations.remove(value.id)?.cancel(false)
        if (value.terminal) return
        expirations[value.id] = executor.schedule({
            expirations.remove(value.id)
            runCatching {
                val current = db(app).get(value.id)
                if (current != null && !current.terminal) update(app, current.copy(status = "expired"))
            }.onFailure { android.util.Log.e("GalaxySSIReminder", "Could not expire reminder", it) }
        }, (value.expiresAt - System.currentTimeMillis()).coerceAtLeast(0L), TimeUnit.MILLISECONDS)
    }

    fun restore(context: Context) = submit {
        val app = context.applicationContext
        val database = db(app)
        database.activeIds().forEach { id -> database.get(id)?.let { value ->
            if (value.expiresAt <= System.currentTimeMillis() || !trusted(app, value.contactId))
                update(app, value.copy(status = "expired"))
            else armExpiry(app, value)
        } }
        database.prune(System.currentTimeMillis())
    }

    private fun history(app: Context, value: ContactReminder) {
        if (value.historyId == 0L) return
        val context = AppLanguage.wrap(app)
        val content = context.getString(if (value.outgoing) R.string.contact_reminder_sent else R.string.contact_reminder_received) +
            "\n" + context.getString(statusText(value.status))
        val row = JSONObject().put("id", value.historyId).put("contactId", value.contactId)
            .put("content", content).put("isMine", value.outgoing).put("isSystem", false)
            .put("timestamp", value.createdAt).put("remoteMessageId", "reminder:${value.id}")
            .put("isRead", value.outgoing || AppForegroundTracker.isConversationVisible(value.contactId))
        ChatHistoryStore.upsertAll(app, listOf(row))
    }

    private fun wire(app: Context, value: ContactReminder, action: String): Boolean {
        GalaxySSIMqttClient.bindApplicationContext(app)
        val target = AppStore.outgoingTopicForContact(app, value.contactId) ?: return false
        val desktop = AppStore.isDesktopDeviceContact(app, value.contactId)
        val payload = JSONObject().put("type", ContactReminderPolicy.TYPE).put("peer_chat", true)
            .put("reminder_id", value.id).put("reminder_action", action)
            .put("created_at", value.createdAt).put("expires_at", value.expiresAt)
            .put("time", System.currentTimeMillis())
            .put("contact_id", if (desktop) AppStore.desktopIdForContact(app, value.contactId) else GalaxySSICrypto.localGalaxySSIId())
        return GalaxySSIMqttClient.publishJsonForTransport(payload, target, value.contactId)
    }

    private fun complete(app: Context, payload: JSONObject) = GalaxySSIMqttClient.completeIncomingDelivery(app, payload.toString())
    private fun trusted(app: Context, id: String): Boolean {
        if (AppStore.isPersonContact(app, id)) return true
        val contact = AppStore.contactById(app, id) ?: return false
        return AppStore.isDesktopDeviceContact(app, id) && !contact.optBoolean("deleted") &&
            GalaxySSILinkProtocol.serverLink(app, AppStore.desktopIdForContact(app, id))?.paired == true
    }
    fun preferences(context: Context) = context.getSharedPreferences("contact-reminder-settings", Context.MODE_PRIVATE)
    fun statusText(status: String): Int = when (status) {
        "acknowledged" -> R.string.contact_reminder_acknowledged
        "dismissed" -> R.string.contact_reminder_dismissed
        "cancelled" -> R.string.contact_reminder_cancelled
        "expired" -> R.string.contact_reminder_expired
        "failed" -> R.string.contact_reminder_failed
        "disabled" -> R.string.contact_reminder_disabled
        "received" -> R.string.contact_reminder_delivered
        "quiet" -> R.string.contact_reminder_quiet
        "muted" -> R.string.contact_reminder_muted
        else -> R.string.contact_reminder_waiting
    }
}
