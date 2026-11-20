package com.galaxyssi.chat

import kotlin.math.PI
import kotlin.math.pow

/** Fully developed steady flow in one ideal rigid circular tube, not a patient vessel estimate. */
internal data class HealthAtlasVesselFlow(val pressureMmHg: Double = 10.0, val radiusMm: Double = .1,
    val lengthMm: Double = 50.0, val viscosityMilliPascalSeconds: Double = 3.5) {
    init {
        require(pressureMmHg.isFinite() && pressureMmHg in 0.0..20.0)
        require(radiusMm.isFinite() && radiusMm in 0.05..0.2)
        require(lengthMm.isFinite() && lengthMm in 20.0..100.0)
        require(viscosityMilliPascalSeconds.isFinite() && viscosityMilliPascalSeconds in 2.0..6.0)
    }
    private val radiusMetres get() = radiusMm / 1000.0
    private val lengthMetres get() = lengthMm / 1000.0
    private val viscosityPascalSeconds get() = viscosityMilliPascalSeconds / 1000.0
    private val resistanceSI get() = 8 * viscosityPascalSeconds * lengthMetres / (PI * radiusMetres.pow(4))
    val flowCubicMetresPerSecond get() = pressureMmHg * PASCALS_PER_MMHG / resistanceSI
    val flowMlPerMinute get() = flowCubicMetresPerSecond * 60_000_000.0
    // Calculate resistance independently of flow, including the zero-pressure case.
    val resistanceMmHgMinutesPerMl get() = resistanceSI / (PASCALS_PER_MMHG * 60_000_000.0)
    val meanSpeedMmPerSecond get() = flowCubicMetresPerSecond / (PI * radiusMetres.pow(2)) * 1000.0
    val centreSpeedMmPerSecond get() = 2 * meanSpeedMmPerSecond
    val wallShearPascals get() = pressureMmHg * PASCALS_PER_MMHG * radiusMetres / (2 * lengthMetres)
    fun speedMmPerSecond(relativeRadius: Double): Double {
        require(relativeRadius.isFinite() && relativeRadius in -1.0..1.0)
        return centreSpeedMmPerSecond * (1 - relativeRadius * relativeRadius)
    }
    companion object {
        const val PASCALS_PER_MMHG = 133.3224
        const val SOURCE = "https://openstax.org/books/college-physics-2e/pages/12-4-viscosity-and-laminar-flow-poiseuilles-law"
        const val PROFILE_SOURCE = "https://ocw.mit.edu/courses/2-25-advanced-fluid-mechanics-fall-2013/1a114d602956fa0dd328155f9b45f93d_MIT2_25F13_Couet_and_Pois.pdf"
        const val UNIT_SOURCE = "https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b9"
    }
}
