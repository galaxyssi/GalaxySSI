package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.watch.WatchDeviceName
import org.json.JSONObject
import java.util.UUID

internal object WatchContactProfile {
    fun current(context: Context): JSONObject = JSONObject()
        .put("name", WatchDeviceName.current(context))
        .put("device_id", "watch_${GalaxySSICrypto.localIdentitySha256().take(16)}")
}

data class WatchPerson(val id: String, val name: String, val status: String, val muted: Boolean, val unread: Int, val fingerprint: String = "")
data class WatchPeerMessage(val id: String, val peer: String, val text: String, val outgoing: Boolean,
                            val time: Long, val state: String)

/** UI snapshots are memory-only reads. All mutations run on WatchRepository's serial worker. */
class WatchContacts(private val context: Context, private val changed: () -> Unit,
                    private val incoming: (WatchPerson, String, Boolean) -> Unit) {
    private val records = AgentEncryptedDatabase(context, "watch_contacts")
    private val history = AgentEncryptedDatabase(context, "watch_peer_messages")
    private val outbox = AgentEncryptedDatabase(context, "watch_peer_outbox")
    private val controls = AgentEncryptedDatabase(context, "watch_peer_controls")
    @Volatile private var people = emptyMap<String, JSONObject>()
    @Volatile private var messages = emptyList<WatchPeerMessage>()
    @Volatile var visiblePeer = ""
    @Volatile var revision = 0L
        private set
    private var lastControl = 0L
    private var lastSend = 0L
    private var qr: JSONObject? = null

    fun load() {
        people = records.entries().associate { it.first to JSONObject(it.second) }
        messages = history.entries().map { message(JSONObject(it.second)) }.sortedBy { it.time }
        outbox.entries().forEach { (id, raw) ->
            if (messages.none { it.id == id }) {
                val entry = JSONObject(raw); val payload = entry.getJSONObject("envelope").getJSONObject("payload")
                saveMessage(WatchPeerMessage(id, entry.getString("peer"), payload.getString("content"), true, payload.getLong("time"), "queued"))
            }
        }
        notifyChanged()
    }
    fun people(): List<WatchPerson> = people.values.filter { it.optString("status") in setOf("pending", "approved") }
        .map(::person).sortedWith(compareByDescending<WatchPerson> { it.unread > 0 }.thenBy { it.name })
    fun person(id: String): WatchPerson? = people[id]?.let(::person)
    fun messages(id: String) = messages.filter { it.peer == id }
    fun hasRoutes() = people.values.any { it.optString("status") != "deleted" } || rendezvousTopics().isNotEmpty()
    internal fun rendezvousTopics() = PhoneContactCard.activeRendezvousTopics(context)
    internal fun session(topic: String) = PhoneContactCard.sessionForTopic(context, topic)
    fun isPeer(id: String) = people.containsKey(id)
    internal fun approved(id: String) = people[id]?.optString("status") == "approved"
    internal fun links(): List<GalaxySSILinkProtocol.ServerLink> = people.values.filter { it.optString("status") != "deleted" }.mapNotNull { record ->
        runCatching {
            val card = record.getJSONObject("card")
            val routes = GalaxySSILinkProtocol.Routes(record.getString("route"), record.getString("secret"),
                GalaxySSICrypto.localIdentitySha256(), card.getString("identity_fingerprint"))
            val id = card.getString("galaxyssi_id")
            GalaxySSILinkProtocol.ServerLink(id, card.getString("name"), routes.remoteFingerprint, id, routes, true)
        }.getOrNull()
    }
    internal fun link(id: String) = links().firstOrNull { it.desktopId == id }
    fun createQr(force: Boolean = false): String {
        if (force) qr = null
        val card = qr?.takeIf { PhoneContactCard.isQrOfferValid(it) &&
            session(it.getString("pairing_topic"))?.optString("claimed_fingerprint").isNullOrBlank() }
            ?: PhoneContactCard.createQr(context, WatchContactProfile.current(context)).also { qr = it }
        return PhoneContactCard.compactQr(card).toString()
    }

    fun control(topic: String, payload: JSONObject) {
        val type = payload.optString("type")
        require(PhoneContactCard.isControlType(type) && PhoneContactCard.isFreshControlPayload(payload))
        require(PhoneContactCard.isAddressedToLocalIdentity(payload, GalaxySSICrypto.localGalaxySSIId()))
        val card = PhoneContactCard.cardFromControlPayload(payload) ?: error("Invalid contact identity")
        val id = card.getString("galaxyssi_id")
        require(payload.optString("from") == id && id != GalaxySSICrypto.localGalaxySSIId())
        require(GalaxySSICrypto.verifyPublicIdentitySignature(card.getString("identity_public_key"),
            card.getString("identity_fingerprint"), PhoneContactCard.canonicalBytes(card), card.getString("signature")))
        val existing = people[id]
        val routes = GalaxySSICrypto.derivePhoneRelationshipRoutes(card.getString("identity_public_key"),
            card.getString("identity_fingerprint")) ?: error("Invalid contact routes")
        if (type == PhoneContactCard.REQUEST_TYPE) {
            val session = session(topic) ?: error("Expired QR")
            require(payload.optString("pairing_token") == session.getString("token"))
            val claim = PhoneContactCard.claimSession(context, topic, payload.getString("pairing_token"),
                card.getString("identity_fingerprint")) ?: error("QR already claimed")
            if (claim.alreadyClaimed && existing != null) { replyToClaim(id); return }
        } else {
            require(existing != null && topic in routes.receiveWindow)
            require(existing.getJSONObject("card").getString("identity_fingerprint") == routes.remoteFingerprint)
            require(existing.getString("secret") == routes.linkSecret)
        }
        // Repeated claims must still recover the bundle/decision if a broker dropped it.
        if (!PhoneContactCard.acceptControlMessage(context, payload)) {
            if (type == PhoneContactCard.REQUEST_TYPE && existing != null) replyToClaim(id)
            return
        }
        if (existing?.optString("status") == "deleted" && type != PhoneContactCard.REQUEST_TYPE) return
        val refresh = type == PhoneContactCard.BUNDLE_REFRESH_TYPE || type == PhoneContactCard.BUNDLE_RESPONSE_TYPE
        if (refresh || !GalaxySSICrypto.hasPeerSession(context, id)) {
            require(GalaxySSICrypto.processPeerBundle(card.getJSONObject("signal_bundle"), id,
                card.getString("identity_fingerprint"), replaceExisting = refresh))
        }
        val record = existing?.let { JSONObject(it.toString()) } ?: JSONObject()
            .put("status", "pending").put("unread", 0).put("muted", false)
        record.put("card", card).put("route", routes.clientRouteId).put("secret", routes.linkSecret)
        // Only the local user's approval may authorize an incoming request.
        if (type == PhoneContactCard.REQUEST_TYPE && record.optString("status") in setOf("deleted", "rejected"))
            record.put("status", "pending")
        savePerson(id, record)
        if (refresh) reencrypt(id)
        when (type) {
            PhoneContactCard.REQUEST_TYPE -> { replyToClaim(id); if (existing == null) incoming(person(record), "", true) }
            PhoneContactCard.BUNDLE_REFRESH_TYPE -> queueControl(id, PhoneContactCard.BUNDLE_RESPONSE_TYPE)
        }
    }

    private fun replyToClaim(id: String) {
        queueControl(id, PhoneContactCard.BUNDLE_RESPONSE_TYPE)
        when (people[id]?.optString("status")) {
            "approved" -> queueControl(id, PhoneContactCard.APPROVAL_TYPE)
            "rejected" -> queueControl(id, PhoneContactCard.REJECTION_TYPE)
        }
    }
    fun decide(id: String, approve: Boolean) {
        val record = people[id]?.takeIf { it.optString("status") == "pending" } ?: return
        // A newer local decision supersedes a previously queued opposite decision.
        controls.remove("$id:${if (approve) PhoneContactCard.REJECTION_TYPE else PhoneContactCard.APPROVAL_TYPE}")
        // Persist the outbound decision before changing the visible local state.
        queueControl(id, if (approve) PhoneContactCard.APPROVAL_TYPE else PhoneContactCard.REJECTION_TYPE)
        savePerson(id, JSONObject(record.toString()).put("status", if (approve) "approved" else "rejected"))
    }
    private fun queueControl(id: String, type: String) {
        val previous = controls.readString("$id:$type", "")
        if (previous.isNotBlank() && PhoneContactCard.isFreshControlPayload(JSONObject(previous).getJSONObject("payload"))) {
            lastControl = 0; return
        }
        val value = PhoneContactCard.controlPayload(type, id, PhoneContactCard.identityCard(context))
        controls.writeString("$id:$type", JSONObject().put("peer", id).put("payload", value).toString())
        lastControl = 0
    }
    fun requestRecovery(id: String) {
        val key = "$id:${PhoneContactCard.BUNDLE_REFRESH_TYPE}"
        val current = controls.readString(key, "")
        if (current.isNotEmpty() && System.currentTimeMillis() - JSONObject(current).getJSONObject("payload").optLong("time") < 60_000) return
        queueControl(id, PhoneContactCard.BUNDLE_REFRESH_TYPE)
    }
    private fun reencrypt(id: String) {
        outbox.entries().forEach { (key, raw) ->
            val entry = JSONObject(raw)
            if (entry.optString("peer") == id) {
                val wire = GalaxySSICrypto.encryptPayloadForContact(id, entry.getJSONObject("envelope")) ?: return@forEach
                outbox.writeString(key, entry.put("wire", wire.toString()).toString())
            }
        }
    }
    fun send(id: String, text: String) {
        require(approved(id))
        val content = text.trim()
        require(content.isNotEmpty() && content.length <= 24_000)
        val routes = checkNotNull(link(id)).routes
        val payload = WatchPeerProtocol.outgoing(GalaxySSICrypto.localGalaxySSIId(), id, routes.clientRouteId, content)
        val envelope = GalaxySSILinkProtocol.makeEnvelope(payload, GalaxySSICrypto.localGalaxySSIId(), id)
        val wire = GalaxySSICrypto.encryptPayloadForContact(id, envelope) ?: error("Contact session unavailable")
        val key = payload.getString("message_id")
        outbox.writeString(key, JSONObject().put("peer", id).put("envelope", envelope).put("wire", wire.toString()).toString())
        saveMessage(WatchPeerMessage(key, id, content, true, payload.getLong("time"), "queued"))
        lastSend = 0
    }
    fun accept(id: String, payload: JSONObject) {
        require(approved(id))
        if (payload.optString("type") != "peer_message") return
        require(WatchPeerProtocol.validIncoming(payload, id, GalaxySSICrypto.localGalaxySSIId(), checkNotNull(link(id)).routes.clientRouteId))
        val key = payload.getString("message_id")
        controls.remove("$id:${PhoneContactCard.APPROVAL_TYPE}")
        if (messages.any { it.id == key && it.peer == id }) return
        val text = payload.optString("content").take(24_000)
        // Attachments are represented explicitly until the phone media viewer is ported.
        val display = if (payload.optJSONArray("attachments")?.length()?.let { it > 0 } == true)
            text + if (text.isBlank()) "[attachment]" else "\n[attachment]" else text
        saveMessage(WatchPeerMessage(key, id, display, false, System.currentTimeMillis(), "received"))
        val record = JSONObject(people.getValue(id).toString())
        if (visiblePeer != id) record.put("unread", record.optInt("unread") + 1)
        savePerson(id, record)
        if (visiblePeer != id && !record.optBoolean("muted")) incoming(person(record), display, false)
    }
    fun stored(id: String, key: String, hash: String) {
        val raw = outbox.readString(key, "").takeIf { it.isNotEmpty() } ?: return
        val entry = JSONObject(raw)
        if (entry.optString("peer") != id || MqttDeliveryEnvelope.contentHash(JSONObject(entry.getString("wire"))) != hash) return
        outbox.remove(key)
        controls.remove("$id:${PhoneContactCard.APPROVAL_TYPE}")
        messages.firstOrNull { it.id == key && it.peer == id }?.let { saveMessage(it.copy(state = "delivered")) }
    }
    fun tick(transport: WatchLinkTransport) {
        val now = System.currentTimeMillis()
        if (now - lastControl >= 10_000) {
            lastControl = now
            controls.entries().forEach { (key, raw) ->
                val entry = JSONObject(raw); val payload = entry.getJSONObject("payload")
                if (!PhoneContactCard.isFreshControlPayload(payload)) {
                    controls.remove(key)
                    val id = entry.getString("peer")
                    val type = payload.optString("type")
                    if ((type == PhoneContactCard.APPROVAL_TYPE && approved(id)) ||
                        (type == PhoneContactCard.REJECTION_TYPE && people[id]?.optString("status") == "rejected")) queueControl(id, type)
                    return@forEach
                }
                val link = link(entry.getString("peer")) ?: return@forEach
                transport.bootstrap(link.routes.up, GalaxySSILinkProtocol.sealWirePacket(payload.toString(), link.routes.linkSecret), link.routes.receiveWindow.toSet())
            }
        }
        if (now - lastSend >= 10_000) {
            lastSend = now
            outbox.entries().forEach { (key, raw) ->
                val entry = JSONObject(raw); val id = entry.getString("peer")
                if (!approved(id)) return@forEach
                if (entry.getJSONObject("envelope").optLong("expires_at") < now) {
                    outbox.remove(key)
                    messages.firstOrNull { it.id == key }?.let { saveMessage(it.copy(state = "failed")) }
                } else link(id)?.let { transport.publish(it, key, entry.getString("wire"), "peer_message") }
            }
        }
    }
    fun markRead(id: String) {
        people[id]?.takeIf { it.optInt("unread") > 0 }?.let { savePerson(id, JSONObject(it.toString()).put("unread", 0)) }
    }
    fun mute(id: String, value: Boolean) { people[id]?.let { savePerson(id, JSONObject(it.toString()).put("muted", value)) } }
    fun clear(id: String) {
        val keys = messages.filter { it.peer == id }.map { it.id }
        history.removeAll(keys); outbox.removeAll(keys)
        messages = messages.filterNot { it.peer == id }; markRead(id); notifyChanged()
    }
    fun delete(id: String) {
        clear(id)
        people[id]?.let { savePerson(id, JSONObject(it.toString()).put("status", "deleted")) }
        controls.removeAll(controls.entries().filter { JSONObject(it.second).optString("peer") == id }.map { it.first })
        GalaxySSICrypto.clearPeerTrust(context, id)
    }
    private fun savePerson(id: String, value: JSONObject) {
        records.writeString(id, value.toString()); people = people + (id to value); notifyChanged()
    }
    private fun saveMessage(value: WatchPeerMessage) {
        history.writeString(value.id, JSONObject().put("id", value.id).put("peer", value.peer).put("text", value.text)
            .put("outgoing", value.outgoing).put("time", value.time).put("state", value.state).toString())
        messages = (messages.filterNot { it.id == value.id } + value).sortedBy { it.time }; notifyChanged()
    }
    private fun person(record: JSONObject) = WatchPerson(record.getJSONObject("card").getString("galaxyssi_id"),
        record.getJSONObject("card").getString("name"), record.getString("status"), record.optBoolean("muted"), record.optInt("unread"), record.getJSONObject("card").optString("identity_fingerprint"))
    private fun message(value: JSONObject) = WatchPeerMessage(value.getString("id"), value.getString("peer"),
        value.getString("text"), value.getBoolean("outgoing"), value.getLong("time"), value.getString("state"))
    private fun notifyChanged() { revision++; changed() }
}

/** The phone's peer-message fields and authenticated conversation binding. */
object WatchPeerProtocol {
    fun conversation(local: String, remote: String) = listOf(local, remote).sorted().joinToString(":", "peer:")
    fun outgoing(local: String, remote: String, route: String, content: String): JSONObject {
        val now = System.currentTimeMillis()
        return JSONObject().put("type", "peer_message").put("message_id", UUID.randomUUID().toString())
            .put("source_message_id", now.toString()).put("client_message_id", now).put("content", content)
            .put("message_kind", "text").put("contact_id", local).put("desktop_id", "")
            .put("client_route_id", route).put("conversation_id", conversation(local, remote))
            .put("task_id", "peer:$now").put("turn_id", "peer-turn:$now").put("sender", local)
            .put("peer_chat", true).put("time", now)
    }
    fun validIncoming(payload: JSONObject, remote: String, local: String, route: String) =
        payload.optString("type") == "peer_message" && payload.optString("sender") == remote &&
            payload.optString("contact_id") == remote && payload.optString("client_route_id") == route &&
            payload.optString("conversation_id") == conversation(local, remote) &&
            runCatching { UUID.fromString(payload.optString("message_id")) }.isSuccess &&
            payload.optString("content").length <= 24_000
}
