package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.chat.R.string

internal enum class HealthAtlasEndocrineCellAssignments(
    val storyKey: String,
    val owner: String,
    val artTag: String,
    override val title: Int,
    override val scope: Int,
    override val chapters: List<Pair<Int, Int>>,
    override val references: List<Pair<Int, String>>,
    override val durationMs: Long,
) : HealthAtlasCellLesson {
    DELTA(
        "PANCREATIC_DELTA_MODULATION", "cell-pancreatic-delta-cell", "atlas-function-pancreatic-delta-art",
        string.health_atlas_delta_local_title, string.health_atlas_delta_local_scope,
        listOf(
            string.health_atlas_delta_local_find to string.health_atlas_delta_local_find_caption,
            string.health_atlas_delta_local_spread to string.health_atlas_delta_local_spread_caption,
            string.health_atlas_delta_local_dampen to string.health_atlas_delta_local_dampen_caption,
            string.health_atlas_delta_local_tune to string.health_atlas_delta_local_tune_caption,
        ),
        listOf(
            string.health_atlas_delta_local_ref_islet to "https://www.pnas.org/doi/10.1073/pnas.0510790103",
            string.health_atlas_delta_local_ref_effect to "https://pubmed.ncbi.nlm.nih.gov/24559918/",
        ),
        16_000L,
    ),
    PP(
        "PANCREATIC_PP_SIGNAL", "cell-pancreatic-pp-cell", "atlas-function-pancreatic-pp-art",
        string.health_atlas_pp_signal_title, string.health_atlas_pp_signal_scope,
        listOf(
            string.health_atlas_pp_signal_find to string.health_atlas_pp_signal_find_caption,
            string.health_atlas_pp_signal_meal to string.health_atlas_pp_signal_meal_caption,
            string.health_atlas_pp_signal_travel to string.health_atlas_pp_signal_travel_caption,
            string.health_atlas_pp_signal_context to string.health_atlas_pp_signal_context_caption,
        ),
        listOf(
            string.health_atlas_pp_signal_ref_distribution to "https://pmc.ncbi.nlm.nih.gov/articles/PMC3561199/",
            string.health_atlas_pp_signal_ref_meal to "https://pubmed.ncbi.nlm.nih.gov/828120/",
            string.health_atlas_pp_signal_ref_digestive to "https://pubmed.ncbi.nlm.nih.gov/82783/",
        ),
        16_000L,
    ),
    C_CELL(
        "THYROID_CALCITONIN", "cell-thyroid-parafollicular-cell", "atlas-function-thyroid-calcitonin-art",
        string.health_atlas_c_cell_title, string.health_atlas_c_cell_scope,
        listOf(
            string.health_atlas_c_cell_find to string.health_atlas_c_cell_find_caption,
            string.health_atlas_c_cell_release to string.health_atlas_c_cell_release_caption,
            string.health_atlas_c_cell_bone to string.health_atlas_c_cell_bone_caption,
            string.health_atlas_c_cell_context to string.health_atlas_c_cell_context_caption,
        ),
        listOf(
            string.health_atlas_c_cell_ref_histology to "https://histology.oit.duke.edu/NormalBody/Endocrine/Endocrine.html",
            string.health_atlas_c_cell_ref_minerals to "https://www.ncbi.nlm.nih.gov/books/NBK279023/",
        ),
        16_000L,
    ),
    CORTEX(
        "ADRENAL_CORTEX_OUTPUT", "cell-adrenocortical-cell", "atlas-function-adrenal-cortex-art",
        string.health_atlas_cortex_output_title, string.health_atlas_cortex_output_scope,
        listOf(
            string.health_atlas_cortex_output_find to string.health_atlas_cortex_output_find_caption,
            string.health_atlas_cortex_output_outer to string.health_atlas_cortex_output_outer_caption,
            string.health_atlas_cortex_output_middle to string.health_atlas_cortex_output_middle_caption,
            string.health_atlas_cortex_output_inner to string.health_atlas_cortex_output_inner_caption,
            string.health_atlas_cortex_output_blood to string.health_atlas_cortex_output_blood_caption,
        ),
        listOf(
            string.health_atlas_cortex_output_ref_histology to "https://histology.oit.duke.edu/NormalBody/Endocrine/Endocrine.html",
            string.health_atlas_cortex_output_ref_hormones to "https://www.ncbi.nlm.nih.gov/books/NBK278945/",
        ),
        20_000L,
    );

    override val owners = setOf(owner)
    override val showStructurePreview = true

    fun createArt(context: Context, story: HealthAtlasFunctionStory): HealthAtlasFunctionArt = when (this) {
        DELTA -> HealthAtlasPancreaticDeltaStoryView(context, story)
        PP -> HealthAtlasPancreaticPpStoryView(context, story)
        C_CELL -> HealthAtlasThyroidCalcitoninStoryView(context, story)
        CORTEX -> HealthAtlasAdrenalCortexStoryView(context, story)
    }
}
