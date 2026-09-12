package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject
import java.util.UUID

/** Route metadata shares the durable Link inbox database, never an Activity or a broker connection. */
internal class MqttRouteState(private val database: AgentEncryptedDatabase) {
    constructor(context: Context) : this(GalaxySSILinkDeliveryStore.transportMetadataDatabase(context.applicationContext))
    enum class Result { NEW, DUPLICATE, STALE, CONFLICT }

    fun issueLocalResume(peer: String, sender: String, receiver: String, receiveBrokers: Set<String>,
                         nowMs: Long, packetBytes: Int = MqttBrokerCatalog.PACKET_BYTES): MqttRouteAdvertisement {
        val key = key(peer, "local")
        return database.indexedTransaction {
            val stored = database.readString(key, "")
            check(stored.isNotEmpty() || !database.contains(key)) { "Route epoch storage is unreadable" }
            val previous = if (stored.isEmpty()) 0L else stored.toLong()
            check(previous >= 0) { "Invalid stored route epoch" }
            check(previous < MqttRouteAdvertisement.MAX_EPOCH) { "Route epoch exhausted" }
            val advertisement = MqttRouteAdvertisement(sender, receiver, previous + 1,
                UUID.randomUUID().toString().replace("-", ""), nowMs, nowMs + MqttBrokerCatalog.RESUME_TTL_MS,
                receiveBrokers.toSet(), packetBytes)
            MqttRouteAdvertisement.parseVerified(advertisement.toWire(), sender, receiver, nowMs)
            database.writeString(key, advertisement.epoch.toString())
            advertisement
        }
    }

    fun recordVerifiedResume(peer: String, advertisement: MqttRouteAdvertisement, nowMs: Long): Result {
        MqttRouteAdvertisement.parseVerified(advertisement.toWire(), advertisement.sender, advertisement.receiver, nowMs)
        val key = key(peer, "remote")
        return database.indexedTransaction {
            val stored = database.readString(key, "")
            check(stored.isNotEmpty() || !database.contains(key)) { "Remote route watermark is unreadable" }
            val previous = stored.takeIf(String::isNotEmpty)?.let(::JSONObject)
            val digest = advertisement.digest()
            when {
                previous != null && advertisement.epoch < previous.getLong("route_epoch") -> Result.STALE
                previous != null && advertisement.epoch == previous.getLong("route_epoch") -> {
                    if (digest == previous.getString("digest")) Result.DUPLICATE else Result.CONFLICT
                }
                else -> {
                    database.writeString(key, JSONObject().put("route_epoch", advertisement.epoch)
                        .put("digest", digest).put("advertisement", advertisement.toWire()).toString())
                    Result.NEW
                }
            }
        }
    }

    fun loadVerifiedResume(peer: String, sender: String, receiver: String, nowMs: Long): MqttRouteAdvertisement? {
        val raw = database.readString(key(peer, "remote"), "")
        if (raw.isEmpty()) return null
        return runCatching { MqttRouteAdvertisement.parseVerified(JSONObject(raw).getJSONObject("advertisement"),
            sender, receiver, nowMs) }.getOrNull()
    }

    fun forgetRoute(peer: String) {
        database.removeAll(listOf(key(peer, "local"), key(peer, "remote")))
    }

    private fun key(peer: String, direction: String): String {
        require(peer.isNotBlank() && peer.length <= 512)
        return "multipath:$direction:${MqttRouteAdvertisement.sha256(peer)}"
    }
}
