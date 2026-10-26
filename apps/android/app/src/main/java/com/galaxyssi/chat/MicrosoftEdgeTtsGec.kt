/*
 * Sec-MS-GEC v2 adaptation of edge-tts drm.py, LGPL-3.0.
 * Copyright (c) rany <rany@riseup.net> and edge-tts contributors.
 * Kotlin adaptation Copyright (c) 2026 GalaxySSI contributors.
 * See assets/licenses/edge-tts-NOTICE.txt and the accompanying license texts.
 */
package com.galaxyssi.chat

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale

/** Edge's wire checksum, not a general-purpose cryptographic hash. */
internal object MicrosoftEdgeTtsGec {
    fun generate(epochSeconds: Long, clientToken: String): String {
        val ticks = Math.multiplyExact(
            Math.floorDiv(Math.addExact(epochSeconds, 11_644_473_600L), 300L),
            3_000_000_000L
        )
        val data = "$ticks$clientToken".toByteArray(Charsets.US_ASCII)
        val digest = digest(data)
        return "${hex(checksum(data, digest))}-${hex(digest)}"
    }

    private fun digest(data: ByteArray): ByteArray {
        require(data.size >= 7)
        val schedule = IntArray(64)
        schedule[14] = ((data[0].toInt() and 255) shl 16) or
            ((data[1].toInt() and 255) shl 8) or (data[2].toInt() and 255)
        schedule[15] = ByteBuffer.wrap(data, 3, 4).int
        for (i in 16 until 30) {
            var value = INITIAL_SCHEDULE[i - 16]
            if (i - 2 >= 14) value += sigma1(schedule[i - 2]) xor (if (i == 16) 0x000B92C0 else 0)
            if (i - 7 >= 14) value += schedule[i - 7]
            if (i - 15 >= 14) value += sigma0(schedule[i - 15]) xor (if (i == 29) 0x059C0B80 else 0)
            schedule[i] = value
        }
        schedule[30] = sigma1(schedule[28]) + schedule[23] + sigma0(schedule[15]) +
            schedule[14] + ADJUSTMENT - ROUND_CONSTANTS[14]
        expand(schedule, 31)
        var state = rounds(INITIAL_STATE, schedule, 14).mapIndexed { i, value -> INITIAL[i] + value }.toIntArray()

        val length = 57 + data.size
        val padded = ByteBuffer.allocate(data.size - 7 + 1 + Math.floorMod(55 - length, 64) + 8)
            .put(data, 7, data.size - 7).put(0x80.toByte())
        padded.position(padded.capacity() - 8)
        padded.putLong(length.toLong() * 8).rewind()
        while (padded.hasRemaining()) {
            repeat(16) { schedule[it] = padded.int }
            expand(schedule)
            val working = rounds(state, schedule)
            state = IntArray(8) { state[it] + working[it] }
        }
        return ByteBuffer.allocate(32).apply { state.forEach { putInt(it) } }.array()
    }

    private fun expand(schedule: IntArray, from: Int = 16) {
        for (i in from until 64) {
            schedule[i] = sigma1(schedule[i - 2]) + schedule[i - 7] +
                sigma0(schedule[i - 15]) + schedule[i - 16]
        }
    }

    private fun rounds(state: IntArray, schedule: IntArray, from: Int = 0): IntArray {
        var a = state[0]; var b = state[1]; var c = state[2]; var d = state[3]
        var e = state[4]; var f = state[5]; var g = state[6]; var h = state[7]
        // Int arithmetic deliberately wraps at 32 bits, matching the wire algorithm.
        for (i in from until 64) {
            val constant = if (from == 14 && i == 14) ADJUSTMENT else ROUND_CONSTANTS[i]
            val t1 = h + (ror(e, 6) xor ror(e, 11) xor ror(e, 25)) +
                (g xor (e and (f xor g))) + constant + schedule[i]
            val t2 = (ror(a, 2) xor ror(a, 13) xor ror(a, 22)) +
                ((a and b) or (c and (a or b)))
            h = g; g = f; f = e; e = d + t1
            d = c; c = b; b = a; a = t1 + t2
        }
        return intArrayOf(a, b, c, d, e, f, g, h)
    }

    private fun checksum(data: ByteArray, digest: ByteArray): ByteArray {
        val keys = ByteBuffer.wrap(digest).order(ByteOrder.LITTLE_ENDIAN)
        val keyA = keys.int or 1
        val keyB = keys.int or 1
        val factors = intArrayOf(keyA * 0x82893933.toInt(), keyB * 0x82893933.toInt())
        val buffer = ByteBuffer.allocate(((data.size + 1 + 7) / 8) * 8).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put(0.toByte()).put(data).rewind()
        val count = CS_COEFFICIENTS.size + buffer.capacity() / 4
        val terms = IntArray(count)
        val offsets = IntArray(count)
        CS_COEFFICIENTS.indices.forEach { i ->
            terms[i] = CS_COEFFICIENTS[i] * factors[i % 2]
            offsets[i] = CS_OFFSETS[i]
        }
        var index = 0
        while (buffer.hasRemaining()) {
            val word = buffer.int
            val i = CS_COEFFICIENTS.size + index
            terms[i] = word * (if (index % 2 == 0) keyA else keyB)
            offsets[i] = rol16(word) * (if (index % 2 == 0) 0xEF0569FB.toInt() else 0xC31713DB.toInt())
            if (index == 0) {
                terms[i] += 0xF2F90B1A.toInt() * factors[0]
                offsets[i] += 0x0B1A0000
            }
            index++
        }
        var swapAcc = 0
        var swapLast = 0
        var state = 0
        var acc = 0
        for (i in 0 until count step 2) {
            val x = terms[i]
            val y = terms[i + 1]
            var q = rol16(offsets[i] + x) * 0x76F50F34
            swapAcc += rol16(q) * 0xC3EFEA97.toInt() + q
            q = rol16(offsets[i + 1] + y) * 0x1881CE3C
            swapLast = rol16(q) * 0x35BD1EC9 + q
            swapAcc += swapLast
            state = rol16(state * keyA + x) * 0xCF98B111.toInt()
            state = rol16(state) * 0x87085B9F.toInt()
            state = rol16(state) * 0x12CEB96D
            state = rol16(state) * 0x257E1D83
            acc += state
            var t = rol16(state * keyB + y) * 0xA27416F5.toInt()
            t = rol16(t) * 0xD38396FF.toInt()
            state = rol16(rol16(t) * 0x7C932B89) * 0xBFA49F69.toInt()
            acc += state
        }
        return ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
            .putInt(swapLast xor state).putInt(swapAcc xor acc).array()
    }

    private fun ror(value: Int, bits: Int) = Integer.rotateRight(value, bits)
    private fun rol16(value: Int) = Integer.rotateLeft(value, 16)
    private fun sigma0(value: Int) = ror(value, 7) xor ror(value, 18) xor (value ushr 3)
    private fun sigma1(value: Int) = ror(value, 17) xor ror(value, 19) xor (value ushr 10)
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02X".format(Locale.ROOT, it.toInt() and 255) }
    private fun words(vararg values: Long) = IntArray(values.size) { values[it].toInt() }
    private val ADJUSTMENT = 0xC9DC06A7.toInt()
    private val INITIAL = words(0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19)
    private val INITIAL_STATE = words(0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A, 0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2)
    private val INITIAL_SCHEDULE = words(
        0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA, 0xA622EE8C, 0xD1DD9491, 0xC0DD25A0,
        0xF9E70AB6, 0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33, 0xD258B060, 0x72766564
    )
    private val ROUND_CONSTANTS = words(
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
    )
    private val CS_COEFFICIENTS = words(
        0xE82E91B1, 0x44DE24C6, 0x3BEB65BC, 0xC89C5933, 0x8D1EC211, 0x314EF5D5, 0xE92491B1,
        0xF0A5B9D5, 0x06064CF3, 0xDA79FA60, 0xBED20560, 0x89F9C9F8, 0x35FA38C6, 0xCB49E3C6
    )
    private val CS_OFFSETS = words(
        0xB32700D0, 0x88DFF51D, 0x29514038, 0xB328CBDF, 0xD405B4D5, 0x26E55F3C, 0x607801C6,
        0x82B2C1FB, 0xFA51A3DA, 0x207CC464, 0x3C3C74F3, 0xD2D14B61, 0xBB04A2C1, 0xC5626167
    )
}
