package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasVulvarProtectionAssignment {
    const val VULVA_ID = "vulva"
    const val MAJORA_ID = "labia-majora"
    const val MINORA_ID = "labia-minora"
    const val OVERVIEW = 0
    const val OUTER = 1
    const val INNER = 2
    const val VARIATION = 3
    const val BOUNDARY = 4
    const val durationMs = 20_000L

    val owners = setOf(VULVA_ID, MAJORA_ID, MINORA_ID)
    val title = string.health_atlas_vulvar_protection_title
    val scope = string.health_atlas_vulvar_protection_scope
    val choice = string.health_atlas_vulvar_protection_choice
    val chapterIds = listOf("layers-of-the-vulva", "outer-fold-covering", "inner-fold-border",
        "fold-shape-variation", "external-boundaries")
    val chapters = listOf(
        string.health_atlas_vulvar_protection_overview to string.health_atlas_vulvar_protection_overview_caption,
        string.health_atlas_vulvar_protection_outer to string.health_atlas_vulvar_protection_outer_caption,
        string.health_atlas_vulvar_protection_inner to string.health_atlas_vulvar_protection_inner_caption,
        string.health_atlas_vulvar_protection_variation to string.health_atlas_vulvar_protection_variation_caption,
        string.health_atlas_vulvar_protection_boundary to string.health_atlas_vulvar_protection_boundary_caption,
    )
    val references = listOf(
        string.health_atlas_vulvar_protection_ref_anatomy to HealthAtlasVulvarProtectionPlates.ANATOMY_SOURCE,
        string.health_atlas_vulvar_protection_ref_variation to "https://pubmed.ncbi.nlm.nih.gov/15842291/",
    )

    fun entryChapter(id: String) = when (id) {
        MAJORA_ID -> OUTER
        MINORA_ID -> INNER
        else -> OVERVIEW
    }
}
