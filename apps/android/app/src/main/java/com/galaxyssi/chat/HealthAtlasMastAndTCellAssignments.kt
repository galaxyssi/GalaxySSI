package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.chat.R.string

/** Bind the matching enum entry, choice title and art factory in HealthAtlasFunctionStory. */
internal object HealthAtlasMastAndTCellAssignments {
    internal class Assignment(
        val key: String,
        owner: String,
        override val title: Int,
        override val scope: Int,
        override val choice: Int,
        override val chapters: List<Pair<Int, Int>>,
        override val references: List<Pair<Int, String>>,
        val createArt: (Context, HealthAtlasFunctionStory) -> HealthAtlasFunctionArt,
    ) : HealthAtlasCellLesson {
        override val owners = setOf(owner)
        override val durationMs = 20_000L
        override val showStructurePreview = true
    }

    private const val T_CELL_ANATOMY =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-3-the-adaptive-immune-response-t-lymphocytes-and-their-functional-types"

    val mast = Assignment(
        "MAST_CELL_GRANULE_RELEASE", "cell-mast-cell",
        string.health_atlas_mast_story_title, string.health_atlas_mast_story_scope, string.health_atlas_mast_story_choice,
        listOf(
            string.health_atlas_mast_story_sites to string.health_atlas_mast_story_sites_caption,
            string.health_atlas_mast_story_storage to string.health_atlas_mast_story_storage_caption,
            string.health_atlas_mast_story_release to string.health_atlas_mast_story_release_caption,
            string.health_atlas_mast_story_spread to string.health_atlas_mast_story_spread_caption,
        ),
        listOf(
            string.health_atlas_mast_story_ref_skin to "https://jcp.bmj.com/content/58/3/285",
            string.health_atlas_mast_story_ref_sites to "https://doi.org/10.1084/jem.20230570",
            string.health_atlas_mast_story_ref_release to "https://www.ncbi.nlm.nih.gov/books/NBK27112/",
        ),
        ::HealthAtlasMastCellStoryView,
    )

    val helper = Assignment(
        "HELPER_T_COORDINATION", "cell-helper-t-cell",
        string.health_atlas_helper_t_story_title, string.health_atlas_helper_t_story_scope,
        string.health_atlas_helper_t_story_choice,
        listOf(
            string.health_atlas_helper_t_story_cue to string.health_atlas_helper_t_story_cue_caption,
            string.health_atlas_helper_t_story_send to string.health_atlas_helper_t_story_send_caption,
            string.health_atlas_helper_t_story_reach to string.health_atlas_helper_t_story_reach_caption,
            string.health_atlas_helper_t_story_coordinate to string.health_atlas_helper_t_story_coordinate_caption,
        ),
        listOf(string.health_atlas_helper_t_story_ref to T_CELL_ANATOMY),
        ::HealthAtlasHelperTCellStoryView,
    )

    val cytotoxic = Assignment(
        "CYTOTOXIC_T_CONTACT", "cell-cytotoxic-t-cell",
        string.health_atlas_cytotoxic_t_story_title, string.health_atlas_cytotoxic_t_story_scope,
        string.health_atlas_cytotoxic_t_story_choice,
        listOf(
            string.health_atlas_cytotoxic_t_story_approach to string.health_atlas_cytotoxic_t_story_approach_caption,
            string.health_atlas_cytotoxic_t_story_contact to string.health_atlas_cytotoxic_t_story_contact_caption,
            string.health_atlas_cytotoxic_t_story_change to string.health_atlas_cytotoxic_t_story_change_caption,
            string.health_atlas_cytotoxic_t_story_separate to string.health_atlas_cytotoxic_t_story_separate_caption,
        ),
        listOf(
            string.health_atlas_cytotoxic_t_story_ref to T_CELL_ANATOMY,
            string.health_atlas_cytotoxic_t_story_ref_human to "https://www.ncbi.nlm.nih.gov/books/NBK539801/",
        ),
        ::HealthAtlasCytotoxicTCellStoryView,
    )

    val regulatory = Assignment(
        "REGULATORY_T_MODERATION", "cell-regulatory-t-cell",
        string.health_atlas_regulatory_t_story_title, string.health_atlas_regulatory_t_story_scope,
        string.health_atlas_regulatory_t_story_choice,
        listOf(
            string.health_atlas_regulatory_t_story_active to string.health_atlas_regulatory_t_story_active_caption,
            string.health_atlas_regulatory_t_story_join to string.health_atlas_regulatory_t_story_join_caption,
            string.health_atlas_regulatory_t_story_moderate to string.health_atlas_regulatory_t_story_moderate_caption,
            string.health_atlas_regulatory_t_story_balance to string.health_atlas_regulatory_t_story_balance_caption,
        ),
        listOf(string.health_atlas_regulatory_t_story_ref to T_CELL_ANATOMY),
        ::HealthAtlasRegulatoryTCellStoryView,
    )
}
