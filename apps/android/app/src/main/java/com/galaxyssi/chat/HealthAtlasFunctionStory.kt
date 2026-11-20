package com.galaxyssi.chat

/** Visual chapters are independent of the catalogue's four-step physiology simulations. */
internal object HealthAtlasFunctionStory {
    const val SOURCE = "https://pubmed.ncbi.nlm.nih.gov/19188436/"
    const val PATHWAY_SOURCE = "https://pmc.ncbi.nlm.nih.gov/articles/PMC507006/"
    const val DURATION_MS = 15_000L
    private val owners = setOf("tissue-skeletal-muscle", "cell-adipocyte")
    val chapters = listOf(
        R.string.health_atlas_uptake_bind to R.string.health_atlas_uptake_bind_caption,
        R.string.health_atlas_uptake_irs to R.string.health_atlas_uptake_irs_caption,
        R.string.health_atlas_uptake_akt to R.string.health_atlas_uptake_akt_caption,
        R.string.health_atlas_uptake_fuse to R.string.health_atlas_uptake_fuse_caption,
        R.string.health_atlas_uptake_transport to R.string.health_atlas_uptake_transport_caption,
    )

    fun supports(id: String?) = id in owners
    fun safePhase(value: Float) = if (value.isFinite()) value.coerceIn(0f, 1f) else 0f
    fun chapter(value: Float) = (safePhase(value) * chapters.size).toInt().coerceAtMost(chapters.lastIndex)
    fun fraction(value: Float) = (safePhase(value) * chapters.size - chapter(value)).coerceIn(0f, 1f)
    fun startOf(chapter: Int) = chapter.coerceIn(chapters.indices) / chapters.size.toFloat()
}
