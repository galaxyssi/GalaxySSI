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
                            val time: Long, val state: String, val audioId: String = "", val duration: Long = 0)

/** UI snapshots are memory-only reads. All mutations run on WatchRepository's serial worker. */
class WatchContacts(private val context: Context, private val changed: () -> Unit,
                    private val incoming: (WatchPerson, String, Boolean) -> Unit) {
    private val records = AgentEncryptedDatabase(context, "watch_contacts")
    private val history = AgentEncryptedDatabase(context, "watch_peer_messages")
    private val outbox = AgentEncryptedDatabase(context, "watch_peer_outbox")
    private val controls = AgentEncryptedDatabase(context, "watch_peer_controls")
    private val audio = WatchPeerAudio(context, ::queuePayload)
    fun audioBytes(peer: String, id: String) = audio.read(peer, id)
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
                if (payload.optString("type") == "peer_message") saveMessage(fromPayload(entry.getString("peer"), payload, true, "queued"))
            }
        }
        syncDesktops(); notifyChanged()
    }
    fun isDesktop(id: String) = people[id]?.optBoolean("desktop") == true
    fun syncDesktops() {
        val links = GalaxySSILinkProtocol.allServerLinks(context).filter { it.paired }
        people.filterValues { it.optBoolean("desktop") }.forEach { (id, record) ->
            if (links.none { it.desktopId == id } && record.optString("status") != "deleted") {
                outbox.removeAll(outbox.entries().filter { JSONObject(it.second).optString("peer") == id }.map { it.first })
                messages.filter { it.peer == id && it.outgoing && it.state == "queued" }.forEach { saveMessage(it.copy(state = "failed")) }
                savePerson(id, JSONObject(record.toString()).put("status", "deleted").put("unread", 0))
            }
        }
        links.forEach { link ->
            val old = people[link.desktopId]
            if (old?.optBoolean("desktop") == true && old.optString("status") == "approved" &&
                old.getJSONObject("card").optString("name") == link.desktopName &&
                old.getJSONObject("card").optString("identity_fingerprint") == link.desktopFingerprint) return@forEach
            val record = old?.let { JSONObject(it.toString()) } ?: JSONObject().put("unread", 0).put("muted", false)
            savePerson(link.desktopId, record.put("desktop", true).put("status", "approved")
                .put("card", JSONObject().put("galaxyssi_id", link.desktopId).put("name", link.desktopName)
                    .put("identity_fingerprint", link.desktopFingerprint)))
        }
    }
    fun people(): List<WatchPerson> = people.values.filter { it.optString("status") in setOf("pending", "requesting", "approved") }
        .map(::person).sortedWith(compareByDescending<WatchPerson> { it.unread > 0 }.thenBy { it.name })
    fun person(id: String): WatchPerson? = people[id]?.let(::person)
    fun messages(id: String) = messages.filter { it.peer == id }
    fun hasRoutes() = people.values.any { it.optString("status") != "deleted" } || rendezvousTopics().isNotEmpty()
    internal fun rendezvousTopics() = PhoneContactCard.activeRendezvousTopics(context)
    internal fun session(topic: String) = PhoneContactCard.sessionForTopic(context, topic)
    fun isPeer(id: String) = people.containsKey(id) && !isDesktop(id)
    internal fun approved(id: String) = people[id]?.optString("status") == "approved" &&
        (!isDesktop(id) || GalaxySSILinkProtocol.serverLink(context, id)?.paired == true)
    internal fun links(): List<GalaxySSILinkProtocol.ServerLink> = people.values.filter { !it.optBoolean("desktop") && it.optString("status") != "deleted" }.mapNotNull { record ->
        runCatching {
            val card = record.getJSONObject("card")
            val routes = GalaxySSILinkProtocol.Routes(record.getString("route"), record.getString("secret"),
                GalaxySSICrypto.localIdentitySha256(), card.getString("identity_fingerprint"))
            val id = card.getString("galaxyssi_id")
            GalaxySSILinkProtocol.ServerLink(id, card.getString("name"), routes.remoteFingerprint, id, routes, true)
        }.getOrNull()
    }
    internal fun link(id: String) = if (isDesktop(id)) GalaxySSILinkProtocol.serverLink(context, id)?.takeIf { it.paired }
        else links().firstOrNull { it.desktopId == id }
    fun createQr(force: Boolean = false): String {
        if (force) qr = null
        val card = qr?.takeIf { PhoneContactCard.isQrOfferValid(it) &&
            session(it.getString("pairing_topic"))?.optString("claimed_fingerprint").isNullOrBlank() }
            ?: PhoneContactCard.createQr(context, WatchContactProfile.current(context)).also { qr = it }
        return PhoneContactCard.compactQr(card).toString()
    }

    fun requestFriend(contents: String) {
        val card = PhoneContactCard.normalizeQr(JSONObject(contents)) ?: error("Invalid invitation")
        require(PhoneContactCard.isQrOfferValid(card))
        val id = card.getString("galaxyssi_id")
        require(id != GalaxySSICrypto.localGalaxySSIId())
        val routes = GalaxySSICrypto.derivePhoneRelationshipRoutes(card.getString("identity_public_key"),
            card.getString("identity_fingerprint")) ?: error("Invalid identity")
        val existing = people[id]
        require(existing == null || existing.getJSONObject("card").getString("identity_fingerprint") == routes.remoteFingerprint)
        if (existing?.optString("status") == "approved") return
        savePerson(id, JSONObject().put("card", card).put("route", routes.clientRouteId)
            .put("secret", routes.linkSecret).put("status", "requesting").put("unread", 0).put("muted", false))
        val payload = PhoneContactCard.controlPayload(PhoneContactCard.REQUEST_TYPE, id,
            PhoneContactCard.identityCard(context), card.getString("pairing_token"))
        controls.writeString("$id:${PhoneContactCard.REQUEST_TYPE}", JSONObject().put("peer", id).put("payload", payload)
            .put("pairing_topic", card.getString("pairing_topic")).put("pairing_secret", card.getString("pairing_secret")).toString())
        lastControl = 0
    }
    fun inspectInvitation(contents: String): WatchPerson? = runCatching {
        val card = PhoneContactCard.normalizeQr(JSONObject(contents)) ?: return null
        require(PhoneContactCard.isQrOfferValid(card) && card.getString("galaxyssi_id") != GalaxySSICrypto.localGalaxySSIId())
        WatchPerson(card.getString("galaxyssi_id"), card.getString("name"), "invitation", false, 0, card.getString("identity_fingerprint"))
    }.getOrNull()

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
        if (type == PhoneContactCard.REQUEST_TYPE && record.optString("status") in setOf("deleted", "rejected", "requesting"))
            record.put("status", "pending")
        savePerson(id, record)
        if (refresh) reencrypt(id)
        when (type) {
            PhoneContactCard.APPROVAL_TYPE, PhoneContactCard.REJECTION_TYPE -> {
                if (record.optString("status") == "requesting") {
                    controls.remove("$id:${PhoneContactCard.REQUEST_TYPE}")
                    savePerson(id, record.put("status", if (type == PhoneContactCard.APPROVAL_TYPE) "approved" else "rejected"))
                }
            }
            PhoneContactCard.REQUEST_TYPE -> { replyToClaim(id); if (record.optString("status") == "pending" && existing?.optString("status") != "pending") incoming(person(record), "", true) }
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
        val payload = outgoing(id, routes.clientRouteId, content)
        queuePayload(id, payload)
        saveMessage(fromPayload(id, payload, true, "queued"))
    }
    fun sendVoice(id: String, bytes: ByteArray, duration: Long) {
        require(approved(id))
        val payload = outgoing(id, checkNotNull(link(id)).routes.clientRouteId, "")
            .put("message_kind", "voice").put("duration_ms", duration)
        val descriptor = audio.prepare(id, payload, bytes, duration)
        payload.put("attachments", org.json.JSONArray().put(descriptor))
        queuePayload(id, payload)
        saveMessage(fromPayload(id, payload, true, "queued"))
    }
    private fun outgoing(id: String, route: String, content: String) = if (isDesktop(id))
        WatchPeerProtocol.outgoingDesktop(GalaxySSICrypto.localGalaxySSIId(), id, route, content)
        else WatchPeerProtocol.outgoing(GalaxySSICrypto.localGalaxySSIId(), id, route, content)
    private fun queuePayload(id: String, source: JSONObject) {
        val payload = JSONObject(source.toString())
        if (payload.optString("type") != "peer_message") payload.put("message_id", UUID.randomUUID().toString())
        val envelope = GalaxySSILinkProtocol.makeEnvelope(payload, GalaxySSICrypto.localGalaxySSIId(), id)
        val wire = (if (isDesktop(id)) GalaxySSICrypto.encryptPayloadForDesktop(id, envelope)
            else GalaxySSICrypto.encryptPayloadForContact(id, envelope)) ?: error("Contact session unavailable")
        val key = payload.getString("message_id")
        outbox.writeString(key, JSONObject().put("peer", id).put("envelope", envelope).put("wire", wire.toString()).toString())
        lastSend = 0
    }
    fun accept(id: String, payload: JSONObject) {
        require(approved(id))
        if (payload.optString("type") in setOf("input_attachment_manifest", "input_attachment_chunk", "input_attachment_receipt")) {
            audio.accept(id, checkNotNull(link(id)).routes.clientRouteId, payload, isDesktop(id)); notifyChanged(); return
        }
        if (payload.optString("type") != "peer_message") return
        val route = checkNotNull(link(id)).routes.clientRouteId
        require(if (isDesktop(id)) WatchPeerProtocol.validDesktopIncoming(payload, id, route)
            else WatchPeerProtocol.validIncoming(payload, id, GalaxySSICrypto.localGalaxySSIId(), route))
        val key = payload.getString("message_id")
        controls.remove("$id:${PhoneContactCard.APPROVAL_TYPE}")
        if (messages.any { it.id == key && it.peer == id }) return
        val text = payload.optString("content").take(24_000)
        // Attachments are represented explicitly until the phone media viewer is ported.
        val display = if (payload.optJSONArray("attachments")?.length()?.let { it > 0 } == true)
            text + if (text.isBlank()) "[attachment]" else "\n[attachment]" else text
        saveMessage(fromPayload(id, payload, false, "received"))
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
                val request = payload.optString("type") == PhoneContactCard.REQUEST_TYPE
                transport.bootstrap(if (request) entry.getString("pairing_topic") else link.routes.up,
                    GalaxySSILinkProtocol.sealWirePacket(payload.toString(), if (request) entry.getString("pairing_secret") else link.routes.linkSecret), link.routes.receiveWindow.toSet())
            }
        }
        if (now - lastSend >= 10_000) {
            lastSend = now
            outbox.entries().forEach { (key, raw) ->
                val entry = JSONObject(raw); val id = entry.getString("peer")
                if (!approved(id)) return@forEach
                val envelope = entry.getJSONObject("envelope")
                val wrongRoute = isDesktop(id) && !WatchPeerProtocol.matchesDesktopRoute(
                    envelope.getJSONObject("payload"), checkNotNull(link(id)).routes.clientRouteId)
                if (wrongRoute || envelope.optLong("expires_at") < now) {
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
        history.removeAll(keys); outbox.removeAll(outbox.entries().filter { JSONObject(it.second).optString("peer") == id }.map { it.first }); audio.clear(id)
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
            .put("outgoing", value.outgoing).put("time", value.time).put("state", value.state)
            .put("audio", value.audioId).put("duration", value.duration).toString())
        messages = (messages.filterNot { it.id == value.id } + value).sortedBy { it.time }; notifyChanged()
    }
    private fun person(record: JSONObject) = WatchPerson(record.getJSONObject("card").getString("galaxyssi_id"),
        record.getJSONObject("card").getString("name"), record.getString("status"), record.optBoolean("muted"), record.optInt("unread"), record.getJSONObject("card").optString("identity_fingerprint"))
    private fun message(value: JSONObject) = WatchPeerMessage(value.getString("id"), value.getString("peer"),
        value.getString("text"), value.getBoolean("outgoing"), value.getLong("time"), value.getString("state"), value.optString("audio"), value.optLong("duration"))
    private fun fromPayload(peer: String, payload: JSONObject, outgoing: Boolean, state: String): WatchPeerMessage {
        val attachments = payload.optJSONArray("attachments")
        val voice = (0 until (attachments?.length() ?: 0)).mapNotNull { attachments?.optJSONObject(it) }
            .firstOrNull { it.optString("mime_type").startsWith("audio/") && it.optString("transfer_id").matches(Regex("[a-f0-9]{64}")) }
        return WatchPeerMessage(payload.getString("message_id"), peer,
            payload.optString("content").ifBlank { if (voice == null && (attachments?.length() ?: 0) > 0) "[attachment]" else "" },
            outgoing, if (outgoing) payload.getLong("time") else System.currentTimeMillis(), state,
            voice?.optString("transfer_id").orEmpty(), payload.optLong("duration_ms", voice?.optLong("duration_ms") ?: 0).coerceIn(0, 3_600_000))
    }
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
    fun matchesDesktopRoute(payload: JSONObject, route: String) =
        payload.optString("client_route_id") == route && payload.optString("conversation_id") == "peer:$route"
    fun outgoingDesktop(local: String, desktop: String, route: String, content: String) =
        outgoing(local, desktop, route, content).put("contact_id", desktop).put("desktop_id", desktop)
            .put("sender", "self").put("conversation_id", "peer:$route")
    fun validDesktopIncoming(payload: JSONObject, desktop: String, route: String) =
        payload.optString("type") == "peer_message" && payload.optString("sender") == "other" &&
            payload.optString("contact_id") == desktop && payload.optString("desktop_id") == desktop &&
            payload.optString("client_route_id") == route && payload.optString("conversation_id") == "peer:$route" &&
            runCatching { UUID.fromString(payload.optString("message_id")) }.isSuccess &&
            payload.optString("content").length <= 24_000
    fun validIncoming(payload: JSONObject, remote: String, local: String, route: String) =
        payload.optString("type") == "peer_message" && payload.optString("sender") == remote &&
            payload.optString("contact_id") == remote && payload.optString("client_route_id") == route &&
            payload.optString("conversation_id") == conversation(local, remote) &&
            runCatching { UUID.fromString(payload.optString("message_id")) }.isSuccess &&
            payload.optString("content").length <= 24_000
}
