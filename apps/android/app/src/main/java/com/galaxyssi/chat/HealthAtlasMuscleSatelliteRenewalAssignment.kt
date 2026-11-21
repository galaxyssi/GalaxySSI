package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.chat.R.string

internal object HealthAtlasMuscleSatelliteRenewalAssignment : HealthAtlasCellLesson {
    const val KEY = "MUSCLE_SATELLITE_RENEWAL"
    const val OWNER = "cell-muscle-satellite-cell"
    const val ART_TAG = "atlas-function-muscle-satellite-renewal-art"
    const val NICHE = 0
    const val ACTIVATION = 1
    const val DIVISION = 2
    const val RENEWAL = 3
    const val FUSION = 4
    const val entryChapter = NICHE
    override val durationMs = 20_000L
    override val showStructurePreview = true

    override val owners = setOf(OWNER)
    override val title = string.health_atlas_muscle_satellite_renewal_title
    override val scope = string.health_atlas_muscle_satellite_renewal_scope
    override val choice = string.health_atlas_muscle_satellite_renewal_choice
    val chapterIds = listOf("resting-niche", "activation", "division", "self-renewal", "fiber-fusion")
    override val chapters = listOf(
        string.health_atlas_muscle_satellite_renewal_niche to
            string.health_atlas_muscle_satellite_renewal_niche_caption,
        string.health_atlas_muscle_satellite_renewal_activation to
            string.health_atlas_muscle_satellite_renewal_activation_caption,
        string.health_atlas_muscle_satellite_renewal_division to
            string.health_atlas_muscle_satellite_renewal_division_caption,
        string.health_atlas_muscle_satellite_renewal_renewal to
            string.health_atlas_muscle_satellite_renewal_renewal_caption,
        string.health_atlas_muscle_satellite_renewal_fusion to
            string.health_atlas_muscle_satellite_renewal_fusion_caption,
    )
    override val references = listOf(
        string.health_atlas_muscle_satellite_renewal_ref_niche to "https://pmc.ncbi.nlm.nih.gov/articles/PMC2225012/",
        string.health_atlas_muscle_satellite_renewal_ref_renewal to "https://pubmed.ncbi.nlm.nih.gov/15277541/",
        string.health_atlas_muscle_satellite_renewal_ref_fusion to "https://pubmed.ncbi.nlm.nih.gov/915534/",
    )

    fun createArt(context: Context, story: HealthAtlasFunctionStory): HealthAtlasFunctionArt =
        HealthAtlasMuscleSatelliteRenewalStoryView(context, story)
}
