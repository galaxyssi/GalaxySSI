package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasLangerhansSentinelAssignment : HealthAtlasCellLesson {
    const val ID = "cell-langerhans-cell"
    const val LOCATION = 0
    const val SAMPLING = 1
    const val PRESENTATION = 2
    const val COMMUNICATION = 3

    override val owners = setOf(ID)
    override val title = string.health_atlas_langerhans_sentinel_title
    override val scope = string.health_atlas_langerhans_sentinel_scope
    override val choice = string.health_atlas_langerhans_sentinel_choice
    val chapterIds = listOf("epidermal-home", "dendrite-sampling", "surface-display", "local-immune-contact")
    override val chapters = listOf(
        string.health_atlas_langerhans_sentinel_location to string.health_atlas_langerhans_sentinel_location_caption,
        string.health_atlas_langerhans_sentinel_sampling to string.health_atlas_langerhans_sentinel_sampling_caption,
        string.health_atlas_langerhans_sentinel_presentation to string.health_atlas_langerhans_sentinel_presentation_caption,
        string.health_atlas_langerhans_sentinel_communication to string.health_atlas_langerhans_sentinel_communication_caption,
    )
    override val references = listOf(
        string.health_atlas_langerhans_sentinel_ref_location to "https://pubmed.ncbi.nlm.nih.gov/33958758/",
        string.health_atlas_langerhans_sentinel_ref_sampling to "https://pubmed.ncbi.nlm.nih.gov/16439974/",
        string.health_atlas_langerhans_sentinel_ref_communication to "https://pubmed.ncbi.nlm.nih.gov/22560445/",
    )
    override val durationMs = 16_000L
    const val entryChapter = LOCATION
}
