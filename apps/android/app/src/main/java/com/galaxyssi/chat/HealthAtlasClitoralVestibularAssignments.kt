package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.chat.R.string

internal object HealthAtlasClitoralSensoryAssignment {
    const val KEY = "CLITORAL_SENSORY_PATH"
    const val OWNER = "clitoris"
    const val VIEW_KEY = "clitoral-cutaway"
    const val CUTAWAY = 0
    const val ENDINGS = 1
    const val DORSAL_ROUTE = 2
    const val SACRAL_ENTRY = 3
    const val durationMs = 20_000L

    private const val anatomy = "https://pubmed.ncbi.nlm.nih.gov/15879834/"
    val owners = setOf(OWNER)
    val title = string.health_atlas_clitoral_sensory_title
    val scope = string.health_atlas_clitoral_sensory_scope
    val choice = string.health_atlas_clitoral_sensory_choice
    val chapters = listOf(
        string.health_atlas_clitoral_sensory_cutaway to string.health_atlas_clitoral_sensory_cutaway_caption,
        string.health_atlas_clitoral_sensory_endings to string.health_atlas_clitoral_sensory_endings_caption,
        string.health_atlas_clitoral_sensory_dorsal_route to string.health_atlas_clitoral_sensory_dorsal_route_caption,
        string.health_atlas_clitoral_sensory_sacral_entry to string.health_atlas_clitoral_sensory_sacral_entry_caption,
    )
    val references = listOf(
        string.health_atlas_clitoral_sensory_ref_anatomy to anatomy,
        string.health_atlas_clitoral_sensory_ref_nerve to "https://pmc.ncbi.nlm.nih.gov/articles/PMC11452485/",
        string.health_atlas_clitoral_sensory_ref_route to "https://pubmed.ncbi.nlm.nih.gov/18817954/",
        string.health_atlas_clitoral_sensory_ref_sacral to "https://pmc.ncbi.nlm.nih.gov/articles/PMC4965354/",
    )
    val plate = HealthAtlasPlate(
        R.drawable.health_atlas_clitoral_cutaway, OWNER, string.health_atlas_clitoral_sensory_cutaway,
        emptyList(), anatomy, VIEW_KEY, features = listOf(
            clitoralVestibularFeature("clitoral-body", 176, 83, string.health_atlas_clitoral_sensory_body,
                string.health_atlas_clitoral_sensory_body_detail),
            clitoralVestibularFeature("clitoral-glans", 181, 120, string.health_atlas_clitoral_sensory_glans,
                string.health_atlas_clitoral_sensory_glans_detail),
            clitoralVestibularFeature("clitoral-crura", 104, 174, string.health_atlas_clitoral_sensory_crura,
                string.health_atlas_clitoral_sensory_crura_detail),
            clitoralVestibularFeature("vestibular-bulbs", 215, 187, string.health_atlas_clitoral_sensory_bulbs,
                string.health_atlas_clitoral_sensory_bulbs_detail),
        ), splitCallouts = true,
    )

    fun createArt(context: Context, story: HealthAtlasFunctionStory) = HealthAtlasClitoralSensoryStoryView(context, story)
}

internal object HealthAtlasVestibularGlandAssignment {
    const val KEY = "VESTIBULAR_GLAND_SECRETION"
    const val OWNER = "greater-vestibular-glands"
    const val VIEW_KEY = "greater-vestibular-gland-ducts"
    const val MAP = 0
    const val ACINI = 1
    const val COLLECTION = 2
    const val OUTLET = 3
    const val durationMs = 20_000L

    private const val anatomy = "https://pmc.ncbi.nlm.nih.gov/articles/PMC9544139/"
    val owners = setOf(OWNER)
    val title = string.health_atlas_vestibular_gland_title
    val scope = string.health_atlas_vestibular_gland_scope
    val choice = string.health_atlas_vestibular_gland_choice
    val chapters = listOf(
        string.health_atlas_vestibular_gland_map to string.health_atlas_vestibular_gland_map_caption,
        string.health_atlas_vestibular_gland_acini to string.health_atlas_vestibular_gland_acini_caption,
        string.health_atlas_vestibular_gland_collection to string.health_atlas_vestibular_gland_collection_caption,
        string.health_atlas_vestibular_gland_outlet to string.health_atlas_vestibular_gland_outlet_caption,
    )
    val references = listOf(
        string.health_atlas_vestibular_gland_ref_anatomy to anatomy,
        string.health_atlas_vestibular_gland_ref_histology to "https://sti.bmj.com/content/43/3/150.full.pdf",
    )
    val plate = HealthAtlasPlate(
        R.drawable.health_atlas_greater_vestibular_gland_ducts, OWNER, string.health_atlas_vestibular_gland_map,
        emptyList(), anatomy, VIEW_KEY, features = listOf(
            clitoralVestibularFeature("vestibular-urethral-opening", 180, 82, string.health_atlas_vestibular_gland_urethral,
                string.health_atlas_vestibular_gland_urethral_detail),
            clitoralVestibularFeature("vestibular-glands-paired", 94, 195, string.health_atlas_vestibular_gland_pair,
                string.health_atlas_vestibular_gland_pair_detail),
            clitoralVestibularFeature("vestibular-gland-duct", 244, 188, string.health_atlas_vestibular_gland_duct,
                string.health_atlas_vestibular_gland_duct_detail),
            clitoralVestibularFeature("vestibular-gland-outlet", 146, 173, string.health_atlas_vestibular_gland_pores,
                string.health_atlas_vestibular_gland_pores_detail),
        ), splitCallouts = true,
    )

    fun createArt(context: Context, story: HealthAtlasFunctionStory) = HealthAtlasVestibularGlandStoryView(context, story)
}

private fun clitoralVestibularFeature(id: String, x: Int, y: Int, title: Int, detail: Int) =
    HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)
