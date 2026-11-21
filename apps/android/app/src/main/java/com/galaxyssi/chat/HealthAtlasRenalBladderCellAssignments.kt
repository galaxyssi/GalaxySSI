package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.chat.R.string

internal object HealthAtlasDistalTubularCellAssignment : HealthAtlasCellLesson {
    const val KEY = "DISTAL_TUBULAR_EXCHANGE"
    const val OWNER = "cell-distal-tubular-cell"
    const val ART_TAG = "atlas-function-distal-tubular-exchange-art"
    const val SIDES = 0
    const val NCC_ENTRY = 1
    const val PUMP_EXCHANGE = 2
    const val CHLORIDE_EXIT = 3
    const val NET_SALT = 4
    override val durationMs = 20_000L

    override val owners = setOf(OWNER)
    override val title = string.health_atlas_distal_exchange_title
    override val scope = string.health_atlas_distal_exchange_scope
    override val choice = string.health_atlas_distal_exchange_choice
    val chapterIds = listOf("two-membrane-sides", "ncc-entry", "pump-exchange", "chloride-exit", "net-salt")
    override val chapters = listOf(
        string.health_atlas_distal_exchange_sides to string.health_atlas_distal_exchange_sides_caption,
        string.health_atlas_distal_exchange_ncc to string.health_atlas_distal_exchange_ncc_caption,
        string.health_atlas_distal_exchange_pump to string.health_atlas_distal_exchange_pump_caption,
        string.health_atlas_distal_exchange_chloride to string.health_atlas_distal_exchange_chloride_caption,
        string.health_atlas_distal_exchange_net to string.health_atlas_distal_exchange_net_caption,
    )
    override val references = listOf(
        string.health_atlas_distal_exchange_ref_human to "https://pubmed.ncbi.nlm.nih.gov/11912242/",
        string.health_atlas_distal_exchange_ref_transport to "https://doi.org/10.2215/CJN.05920613",
    )

    fun createArt(context: Context, story: HealthAtlasFunctionStory) = HealthAtlasDistalTubularStoryView(context, story)
}

internal object HealthAtlasUrothelialCellAssignment : HealthAtlasCellLesson {
    const val KEY = "UROTHELIAL_BARRIER_GEOMETRY"
    const val OWNER = "cell-urothelial-cell"
    const val ART_TAG = "atlas-function-urothelial-barrier-geometry-art"
    const val FOLDED = 0
    const val UNFOLD = 1
    const val SEALED = 2
    const val REFOLD = 3
    override val durationMs = 16_000L

    override val owners = setOf(OWNER)
    override val title = string.health_atlas_urothelial_geometry_title
    override val scope = string.health_atlas_urothelial_geometry_scope
    override val choice = string.health_atlas_urothelial_geometry_choice
    val chapterIds = listOf("relaxed-folds", "unfolding", "intact-barrier", "refolding")
    override val chapters = listOf(
        string.health_atlas_urothelial_geometry_folded to string.health_atlas_urothelial_geometry_folded_caption,
        string.health_atlas_urothelial_geometry_unfold to string.health_atlas_urothelial_geometry_unfold_caption,
        string.health_atlas_urothelial_geometry_sealed to string.health_atlas_urothelial_geometry_sealed_caption,
        string.health_atlas_urothelial_geometry_refold to string.health_atlas_urothelial_geometry_refold_caption,
    )
    override val references = listOf(
        string.health_atlas_urothelial_geometry_ref_histology to
            "https://tales.nmc.unibas.ch/en/histology-12/epithel-allgemeine-histologie-38/transitional-epithelium-urinary-bladder-221",
        string.health_atlas_urothelial_geometry_ref_junction to "https://pubmed.ncbi.nlm.nih.gov/31166831/",
    )

    fun createArt(context: Context, story: HealthAtlasFunctionStory) = HealthAtlasUrothelialStoryView(context, story)
}
