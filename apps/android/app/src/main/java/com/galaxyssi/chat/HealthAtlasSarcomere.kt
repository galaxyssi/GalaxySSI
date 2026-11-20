package com.galaxyssi.chat

/** Fixed relative teaching geometry; coordinates are drawing units and not patient measurements. */
internal data class HealthAtlasSarcomere(val stage: Int) {
    init { require(stage in 0..3) }

    val zDistance = if (stage == 2) 180 else 250
    val relativeLengthPercent = zDistance * 100 / 250
    val thinLength = 86
    val thickLength = 136
    val leftZ = (360 - zDistance) / 2
    val rightZ = leftZ + zDistance
    val leftThick = (360 - thickLength) / 2
    val rightThick = leftThick + thickLength
    val overlap = leftZ + thinLength - leftThick

    companion object { const val OWNER = "cell-skeletal-myocyte" }
}
