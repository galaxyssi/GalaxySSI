package com.galaxyssi.chat

import java.security.MessageDigest

internal data class GalaxySSIIdenticonPattern(
    val cells: List<Boolean>,
    val color: Int
) {
    init {
        require(cells.size == GRID_SIZE * GRID_SIZE)
    }

    fun isFilled(row: Int, column: Int): Boolean = cells[row * GRID_SIZE + column]

    companion object {
        const val GRID_SIZE = 5
    }
}

internal object GalaxySSIIdenticon {
    private val palette = intArrayOf(
        0xFFD4BE28.toInt(),
        0xFF2F81F7.toInt(),
        0xFF1F9D78.toInt(),
        0xFFE05252.toInt(),
        0xFF8B5CF6.toInt(),
        0xFFDB7C26.toInt(),
        0xFF167D9A.toInt(),
        0xFFB4428C.toInt()
    )

    fun fromIdentityFingerprint(fingerprint: String): GalaxySSIIdenticonPattern {
        val normalized = fingerprint.trim().lowercase().ifBlank { "galaxyssi-local-identity" }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(normalized.toByteArray(Charsets.UTF_8))
        val cells = MutableList(GalaxySSIIdenticonPattern.GRID_SIZE * GalaxySSIIdenticonPattern.GRID_SIZE) { false }

        for (row in 0 until GalaxySSIIdenticonPattern.GRID_SIZE) {
            for (sourceColumn in 0..2) {
                val sourceIndex = row * 3 + sourceColumn
                val filled = digestBit(digest, sourceIndex)
                cells[row * GalaxySSIIdenticonPattern.GRID_SIZE + sourceColumn] = filled
                cells[row * GalaxySSIIdenticonPattern.GRID_SIZE + (4 - sourceColumn)] = filled
            }
        }

        return GalaxySSIIdenticonPattern(
            cells = cells,
            color = palette[(digest[2].toInt() and 0xFF) % palette.size]
        )
    }

    private fun digestBit(digest: ByteArray, bitIndex: Int): Boolean {
        val byte = digest[bitIndex / 8].toInt() and 0xFF
        return byte and (1 shl (bitIndex % 8)) != 0
    }
}
