package com.galaxyssi.chat

import android.os.SystemClock
import com.galaxyssi.chat.metrics.AgentTransportTiming

internal data class PendingPairingClaim(
    val desktopId: String,
    val topic: String,
    val wirePayload: String,
    val queuedAtMillis: Long
)

internal data class OutboundFragmentTransfer(
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
