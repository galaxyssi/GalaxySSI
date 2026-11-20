package com.galaxyssi.chat

import kotlin.math.pow

internal enum class HealthAtlasResearchTopic(val title: Int) {
    PHYSIOLOGY(R.string.health_atlas_physiology),
    DRUGS(R.string.health_atlas_drugs),
    AGING(R.string.health_atlas_aging),
}

internal object HealthAtlasResearchSources {
    const val PHARMACOLOGY = "https://openstax.org/books/pharmacology/pages/2-2-pharmacokinetics-and-pharmacodynamics"
    const val KINETICS = "https://pharmacologyeducation.org/clinical-pharmacokinetics/"
    const val AGING = "https://pubmed.ncbi.nlm.nih.gov/36599349/"
    fun forTopic(topic: HealthAtlasResearchTopic, mechanism: HealthAtlasMechanism): List<String> = when (topic) {
        HealthAtlasResearchTopic.PHYSIOLOGY -> listOf(mechanism.source)
        HealthAtlasResearchTopic.DRUGS -> listOf(PHARMACOLOGY, KINETICS)
        HealthAtlasResearchTopic.AGING -> listOf(AGING, mechanism.source)
    }
}

/** Normalized, single-compartment first-order elimination; no drug or patient parameters. */
internal data class HealthAtlasElimination(val halfLifeHours: Int = 4, val elapsedHours: Int = 8) {
    init { require(halfLifeHours in 1..24 && elapsedHours in 0..48) }
    fun percentAt(hours: Double): Double {
        require(hours.isFinite() && hours in 0.0..48.0)
        return 100.0 * 0.5.pow(hours / halfLifeHours)
    }
    val percent get() = percentAt(elapsedHours.toDouble())
}
