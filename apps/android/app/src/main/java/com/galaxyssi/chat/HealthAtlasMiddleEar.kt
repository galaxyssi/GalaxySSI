package com.galaxyssi.chat

import kotlin.math.log10

/** Lossless, frequency-independent teaching approximation, not measured hearing or acoustic power gain. */
internal data class HealthAtlasMiddleEar(val membraneAreaMm2: Double = 55.0,
    val footplateAreaMm2: Double = 3.2, val leverRatio: Double = 1.3) {
    init {
        require(membraneAreaMm2.isFinite() && membraneAreaMm2 in 35.0..75.0)
        require(footplateAreaMm2.isFinite() && footplateAreaMm2 in 2.0..5.0)
        require(leverRatio.isFinite() && leverRatio in 1.0..1.6)
    }

    val areaRatio get() = membraneAreaMm2 / footplateAreaMm2
    val pressureRatio get() = areaRatio * leverRatio
    val pressureGainDb get() = 20 * log10(pressureRatio)
    val volumeVelocityRatio get() = 1 / pressureRatio

    companion object {
        const val SOURCE = "https://pmc.ncbi.nlm.nih.gov/articles/PMC4570511/"
        const val MEASUREMENT_SOURCE = "https://pubmed.ncbi.nlm.nih.gov/28079680/"
        const val ANATOMY_SOURCE = "https://www.nidcd.nih.gov/health/how-do-we-hear"
    }
}
