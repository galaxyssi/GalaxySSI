package com.galaxyssi.watch

import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.os.SystemClock
import com.galaxyssi.chat.NearbyContactProtocol as P
import java.nio.ByteBuffer

internal object WatchNearbyOffer {
    @Volatile private var value: Pair<String, Long>? = null
    fun open(offer: String) { value = offer to (SystemClock.elapsedRealtime() + 120_000) }
    fun close() { value = null }
    fun current(): String? = value?.takeIf { SystemClock.elapsedRealtime() < it.second }?.first
}

class WatchContactNfcService : HostApduService() {
    private var selected = false
    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        val offer = WatchNearbyOffer.current() ?: return byteArrayOf(0x69, 0x85.toByte())
        if (commandApdu.contentEquals(P.SELECT)) { selected = true; return P.OK }
        if (!selected || commandApdu.size != 9 || !commandApdu.copyOfRange(0, 5).contentEquals(byteArrayOf(0x80.toByte(), 0x10, 0, 0, 4)))
            return byteArrayOf(0x6d, 0)
        return runCatching { P.chunk(offer.toByteArray(Charsets.UTF_8), ByteBuffer.wrap(commandApdu, 5, 4).int) + P.OK }
            .getOrDefault(byteArrayOf(0x6a, 0x86.toByte()))
    }
    override fun onDeactivated(reason: Int) { selected = false }
}
