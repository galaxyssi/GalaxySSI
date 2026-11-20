package com.galaxyssi.chat

import kotlin.math.abs
import kotlin.math.roundToInt

/** One equivalent thin lens in air, not a model of an individual eye or a prescription. */
internal data class HealthAtlasEyeOptics(val distanceMetres: Double = 1.0, val powerDiopters: Double = 59.82) {
    init {
        require(distanceMetres.isFinite() && distanceMetres in 0.25..6.0)
        require(powerDiopters.isFinite() && powerDiopters in 55.0..65.0)
    }

    val imageDistanceMm get() = 1000.0 / (powerDiopters - 1.0 / distanceMetres)
    val offsetMm get() = imageDistanceMm - RETINAL_PLANE_MM
    val targetPowerDiopters get() = 1000.0 / RETINAL_PLANE_MM + 1.0 / distanceMetres
    val targetPowerSteps get() = (targetPowerDiopters * 100).roundToInt()
    val focusSide get() = when {
        abs(offsetMm) < .005 -> FocusSide.AT_PLANE
        offsetMm < 0 -> FocusSide.IN_FRONT
        else -> FocusSide.BEHIND
    }

    // Signed height relative to the axis. The final 100 mm before the lens is drawn on a separate scale.
    fun rayHeight(axialMm: Double, heightAtLensMm: Double): Double = heightAtLensMm * if (axialMm < 0)
        (1 + axialMm / (1000 * distanceMetres)) else (1 - axialMm / imageDistanceMm)

    enum class FocusSide { IN_FRONT, AT_PLANE, BEHIND }

    companion object {
        const val RETINAL_PLANE_MM = 17.0
        const val SOURCE = "https://openstax.org/books/university-physics-volume-3/pages/2-5-the-eye"
        const val ANATOMY_SOURCE = "https://www.nei.nih.gov/eye-health-information/healthy-vision/nei-for-kids/about-eye"
    }
}
