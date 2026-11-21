package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasPericyteCoverageAssignment : HealthAtlasCellLesson {
    const val ID = "cell-pericyte"
    const val LOCATION = 0
    const val WRAP = 1
    const val INTERFACE = 2
    const val COOPERATION = 3

    override val owners = setOf(ID)
    override val title = string.health_atlas_pericyte_coverage_title
    override val scope = string.health_atlas_pericyte_coverage_scope
    override val choice = string.health_atlas_pericyte_coverage_choice
    val chapterIds = listOf("outside-the-lumen", "partial-wrap", "shared-interface", "wall-cooperation")
    override val chapters = listOf(
        string.health_atlas_pericyte_coverage_location to string.health_atlas_pericyte_coverage_location_caption,
        string.health_atlas_pericyte_coverage_wrap to string.health_atlas_pericyte_coverage_wrap_caption,
        string.health_atlas_pericyte_coverage_interface to string.health_atlas_pericyte_coverage_interface_caption,
        string.health_atlas_pericyte_coverage_cooperation to string.health_atlas_pericyte_coverage_cooperation_caption,
    )
    override val references = listOf(
        string.health_atlas_pericyte_coverage_ref_shape to "https://pmc.ncbi.nlm.nih.gov/articles/PMC7604512/",
        string.health_atlas_pericyte_coverage_ref_interface to "https://doi.org/10.1016/j.kint.2016.07.035",
        string.health_atlas_pericyte_coverage_ref_cooperation to "https://pubmed.ncbi.nlm.nih.gov/19822899/",
    )
    override val durationMs = 16_000L
    const val entryChapter = LOCATION
}
