package com.galaxyssi.chat.voice.asr.local

import java.nio.ShortBuffer

internal object Float16Codec {
    fun encode(value: Float): Short {
        val bits = value.toRawBits()
        val sign = (bits ushr 16) and 0x8000
        var mantissa = bits and 0x007fffff
        val exponent = (bits ushr 23) and 0xff

        if (exponent == 0xff) {
            return (sign or if (mantissa == 0) 0x7c00 else 0x7e00).toShort()
        }

        val halfExponent = exponent - 127 + 15
        if (halfExponent >= 0x1f) return (sign or 0x7c00).toShort()
        if (halfExponent <= 0) {
            if (halfExponent < -10) return sign.toShort()
            mantissa = mantissa or 0x00800000
            val shift = 14 - halfExponent
            var halfMantissa = mantissa ushr shift
            val roundBit = 1 shl (shift - 1)
            if ((mantissa and roundBit) != 0 && ((mantissa and (roundBit - 1)) != 0 || (halfMantissa and 1) != 0)) {
                halfMantissa += 1
            }
            return (sign or halfMantissa).toShort()
        }

        var result = sign or (halfExponent shl 10) or (mantissa ushr 13)
        if ((mantissa and 0x00001000) != 0 && ((mantissa and 0x00000fff) != 0 || (result and 1) != 0)) {
            result += 1
        }
        return result.toShort()
    }

    fun decode(value: Short): Float {
        val half = value.toInt() and 0xffff
        val sign = (half and 0x8000) shl 16
        val exponent = (half ushr 10) and 0x1f
        val mantissa = half and 0x03ff
        val bits = when (exponent) {
            0 -> {
                if (mantissa == 0) {
                    sign
                } else {
                    var normalized = mantissa
                    var shift = 0
                    while ((normalized and 0x0400) == 0) {
                        normalized = normalized shl 1
                        shift += 1
                    }
                    normalized = normalized and 0x03ff
                    sign or ((127 - 14 - shift) shl 23) or (normalized shl 13)
                }
            }
            0x1f -> sign or 0x7f800000.toInt() or (mantissa shl 13)
            else -> sign or ((exponent - 15 + 127) shl 23) or (mantissa shl 13)
        }
        return Float.fromBits(bits)
    }

    fun argmax(
        logits: ShortBuffer,
        vocabularySize: Int,
        suppressedTokens: Set<Int> = emptySet(),
        timestampStartToken: Int? = null
    ): Int {
        require(vocabularySize in 1..logits.capacity())
        var bestToken = -1
        var bestValue = Float.NEGATIVE_INFINITY
        for (token in 0 until vocabularySize) {
            if (token in suppressedTokens || (timestampStartToken != null && token >= timestampStartToken)) continue
            val value = decode(logits.get(token))
            if (!value.isNaN() && (bestToken < 0 || value > bestValue)) {
                bestToken = token
                bestValue = value
            }
        }
        check(bestToken >= 0) { "Every decoder token was suppressed" }
        return bestToken
    }
}
