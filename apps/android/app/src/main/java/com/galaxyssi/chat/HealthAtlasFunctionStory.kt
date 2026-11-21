package com.galaxyssi.chat

import android.content.Context

/** Visual chapters are independent of the catalogue's quantitative simulations. */
internal enum class HealthAtlasFunctionStory(
    private val owners: Set<String>,
    val title: Int,
    val scope: Int,
    val chapters: List<Pair<Int, Int>>,
    val references: List<Pair<Int, String>>,
    val durationMs: Long,
) {
    GLUCOSE(
        setOf("tissue-skeletal-muscle", "cell-adipocyte"),
        R.string.health_atlas_uptake_title,
        R.string.health_atlas_uptake_scope,
        listOf(
            R.string.health_atlas_uptake_bind to R.string.health_atlas_uptake_bind_caption,
            R.string.health_atlas_uptake_irs to R.string.health_atlas_uptake_irs_caption,
            R.string.health_atlas_uptake_akt to R.string.health_atlas_uptake_akt_caption,
            R.string.health_atlas_uptake_fuse to R.string.health_atlas_uptake_fuse_caption,
            R.string.health_atlas_uptake_transport to R.string.health_atlas_uptake_transport_caption,
        ),
        listOf(
            R.string.health_atlas_uptake_reference to "https://pubmed.ncbi.nlm.nih.gov/19188436/",
            R.string.health_atlas_uptake_pathway_reference to "https://pmc.ncbi.nlm.nih.gov/articles/PMC507006/",
        ),
        15_000L,
    ),
    HEARTBEAT(
        setOf("heart", "cardio", "atria", "ventricles", "heart-valves", "left-atrium", "right-atrium",
            "left-ventricle", "right-ventricle", "tricuspid-valve", "mitral-valve", "pulmonary-valve", "aortic-valve"),
        R.string.health_atlas_beat_title,
        R.string.health_atlas_beat_scope,
        HealthAtlasBeatStage.entries.map { it.title to it.caption },
        listOf(
            R.string.health_atlas_beat_cycle_reference to HealthAtlasHeartSection.CYCLE_SOURCE,
            R.string.health_atlas_beat_flow_reference to "https://www.nhlbi.nih.gov/health/heart/blood-flow",
        ),
        17_500L,
    ),
    BREATHING(
        setOf("respiratory", "trachea", "bronchi", "bronchioles", "lungs", "diaphragm",
            "alveoli", "respiratory-membrane", "pulmonary-capillaries"),
        R.string.health_atlas_breathe_title,
        R.string.health_atlas_breathe_scope,
        HealthAtlasBreathingStage.entries.map { it.title to it.caption },
        listOf(
            R.string.health_atlas_breathe_air_source to "https://www.nhlbi.nih.gov/health/lungs/breathing-benefits",
            R.string.health_atlas_breathe_gas_source to HealthAtlasGasExchange.SOURCE,
        ),
        18_000L,
    ),
    DIGESTION(
        setOf("digestive", "oral-cavity", "tongue", "pharynx", "esophagus", "stomach", "small-intestine",
            "duodenum", "jejunum", "ileum", "salivary-glands", "pancreas", "pancreatic-duct",
            "gallbladder", "biliary-tract", "cell-enterocyte"),
        R.string.health_atlas_meal_title,
        R.string.health_atlas_meal_scope,
        HealthAtlasDigestionStage.meal.map { it.title to it.caption },
        listOf(
            R.string.health_atlas_meal_main_source to "https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works",
            R.string.health_atlas_meal_absorb_source to
                "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-7-chemical-digestion-and-absorption-a-closer-look",
        ),
        20_000L,
    ),
    COLON(
        setOf("large-intestine", "cecum", "colon", "rectum", "anal-canal"),
        R.string.health_atlas_colon_story_title,
        R.string.health_atlas_meal_scope,
        HealthAtlasDigestionStage.colon.map { it.title to it.caption },
        listOf(
            R.string.health_atlas_meal_main_source to "https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works",
            R.string.health_atlas_colon_story_source to
                "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-5-the-small-and-large-intestines",
        ),
        18_000L,
    ),
    HEARING(
        setOf("ear", "external-ear", "middle-ear", "inner-ear", "cochlea", "cell-inner-ear-hair-cell"),
        R.string.health_atlas_hear_title,
        R.string.health_atlas_hear_scope,
        HealthAtlasSoundStage.entries.map { it.title to it.caption },
        listOf(
            R.string.health_atlas_hear_path_source to "https://www.nidcd.nih.gov/health/how-do-we-hear",
            R.string.health_atlas_hear_cells_source to "https://pmc.ncbi.nlm.nih.gov/articles/PMC1413628/",
        ),
        19_000L,
    ),
    NEPHRON(
        setOf("urinary", "kidneys", "nephron", "glomerulus", "bowmans-capsule", "renal-tubules",
            "proximal-tubule", "nephron-loop", "distal-tubule", "collecting-ducts"),
        R.string.health_atlas_nephron_story_title,
        R.string.health_atlas_nephron_story_scope,
        HealthAtlasNephronStage.entries.map { it.title to it.caption },
        listOf(
            R.string.health_atlas_nephron_story_kidney_source to "https://www.niddk.nih.gov/health-information/kidney-disease/kidneys-how-they-work",
            R.string.health_atlas_nephron_story_tubule_source to
                "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-6-tubular-reabsorption",
        ),
        18_000L,
    ),
    VISION(
        setOf("eye", "cornea", "lens", "retina", "cell-retinal-bipolar-cell", "cell-retinal-ganglion-cell"),
        R.string.health_atlas_vision_story_title,
        R.string.health_atlas_vision_story_scope,
        HealthAtlasVisionStage.pathway.map { it.title to it.caption },
        listOf(
            R.string.health_atlas_vision_story_nei_source to "https://www.nei.nih.gov/eye-health-information/healthy-vision/how-eyes-work",
            R.string.health_atlas_vision_story_signal_source to
                "https://openstax.org/books/anatomy-and-physiology-2e/pages/14-1-sensory-perception",
        ),
        19_000L,
    ),
    LIGHT_ADAPTATION(
        setOf("cell-rod-photoreceptor", "cell-cone-photoreceptor"),
        R.string.health_atlas_vision_story_adapt_title,
        R.string.health_atlas_vision_story_adapt_scope,
        HealthAtlasVisionStage.adaptation.map { it.title to it.caption },
        listOf(
            R.string.health_atlas_vision_story_mix_source to "https://pubmed.ncbi.nlm.nih.gov/23325348/",
            R.string.health_atlas_vision_story_dark_source to "https://pubmed.ncbi.nlm.nih.gov/11060133/",
        ),
        18_000L,
    ),
    MUSCLE_MOTION(
        setOf("muscle", "biceps-brachii", "triceps-brachii", "tendons", "cell-skeletal-myocyte"),
        R.string.health_atlas_motion_story_title,
        R.string.health_atlas_motion_story_scope,
        listOf(
            R.string.health_atlas_motion_signal to R.string.health_atlas_motion_signal_caption,
            R.string.health_atlas_motion_calcium to R.string.health_atlas_motion_calcium_caption,
            R.string.health_atlas_motion_slide to R.string.health_atlas_motion_slide_caption,
            R.string.health_atlas_motion_pull to R.string.health_atlas_motion_pull_caption,
            R.string.health_atlas_motion_release to R.string.health_atlas_motion_release_caption,
        ),
        listOf(
            R.string.health_atlas_motion_fiber_source to
                "https://openstax.org/books/anatomy-and-physiology-2e/pages/10-3-muscle-fiber-contraction-and-relaxation",
            R.string.health_atlas_motion_lever_source to
                "https://openstax.org/books/anatomy-and-physiology-2e/pages/11-1-interactions-of-skeletal-muscles-their-fascicle-arrangement-and-their-lever-systems",
        ),
        20_000L,
    ),
    BONE_REMODELING(
        setOf("skeletal", "limb-bones", "hand-bones", "foot-bones", "humerus", "radius", "ulna",
            "tissue-compact-bone", "cell-osteoblast", "cell-osteocyte", "cell-osteoclast"),
        R.string.health_atlas_bone_story_title,
        R.string.health_atlas_bone_story_scope,
        listOf(
            R.string.health_atlas_bone_sense to R.string.health_atlas_bone_sense_caption,
            R.string.health_atlas_bone_remove to R.string.health_atlas_bone_remove_caption,
            R.string.health_atlas_bone_prepare to R.string.health_atlas_bone_prepare_caption,
            R.string.health_atlas_bone_fill to R.string.health_atlas_bone_fill_caption,
            R.string.health_atlas_bone_mineral to R.string.health_atlas_bone_mineral_caption,
        ),
        listOf(
            R.string.health_atlas_bone_formation_source to "https://www.ncbi.nlm.nih.gov/books/NBK279149/",
            R.string.health_atlas_bone_reversal_source to "https://pubmed.ncbi.nlm.nih.gov/28177141/",
        ),
        18_000L,
    ),
    LYMPH_RETURN(
        setOf("lymphatic-vessels", "lymph-nodes", "thoracic-duct", "cell-lymphatic-endothelial-cell"),
        R.string.health_atlas_lymph_flow_title,
        R.string.health_atlas_lymph_flow_scope,
        listOf(
            R.string.health_atlas_lymph_flow_tissue to R.string.health_atlas_lymph_flow_tissue_caption,
            R.string.health_atlas_lymph_flow_entry to R.string.health_atlas_lymph_flow_entry_caption,
            R.string.health_atlas_lymph_flow_pump to R.string.health_atlas_lymph_flow_pump_caption,
            R.string.health_atlas_lymph_flow_node to R.string.health_atlas_lymph_flow_node_caption,
            R.string.health_atlas_lymph_flow_return to R.string.health_atlas_lymph_flow_return_caption,
        ),
        listOf(
            R.string.health_atlas_lymph_flow_anatomy to HealthAtlasLymphOrgans.SOURCE,
            R.string.health_atlas_lymph_flow_entry_source to "https://pubmed.ncbi.nlm.nih.gov/17846148/",
        ),
        20_000L,
    ),
    ANTIBODY_RESPONSE(
        setOf("immune", "cell-b-cell", "cell-plasma-cell"),
        R.string.health_atlas_antibody_story_title,
        R.string.health_atlas_antibody_story_scope,
        listOf(
            R.string.health_atlas_antibody_story_recognize to R.string.health_atlas_antibody_story_recognize_caption,
            R.string.health_atlas_antibody_story_help to R.string.health_atlas_antibody_story_help_caption,
            R.string.health_atlas_antibody_story_expand to R.string.health_atlas_antibody_story_expand_caption,
            R.string.health_atlas_antibody_story_specialize to R.string.health_atlas_antibody_story_specialize_caption,
            R.string.health_atlas_antibody_story_release to R.string.health_atlas_antibody_story_release_caption,
        ),
        listOf(
            R.string.health_atlas_antibody_story_source to
                "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-4-the-adaptive-immune-response-b-lymphocytes-and-antibodies",
            R.string.health_atlas_antibody_story_helper_source to "https://pmc.ncbi.nlm.nih.gov/articles/PMC5030190/",
        ),
        20_000L,
    ),
    INSULIN_SECRETION(
        setOf("endocrine", "pancreatic-islets", "cell-pancreatic-beta-cell"),
        R.string.health_atlas_insulin_story_title,
        R.string.health_atlas_insulin_story_scope,
        listOf(
            R.string.health_atlas_insulin_story_glucose to R.string.health_atlas_insulin_story_glucose_caption,
            R.string.health_atlas_insulin_story_potassium to R.string.health_atlas_insulin_story_potassium_caption,
            R.string.health_atlas_insulin_story_calcium to R.string.health_atlas_insulin_story_calcium_caption,
            R.string.health_atlas_insulin_story_fusion to R.string.health_atlas_insulin_story_fusion_caption,
            R.string.health_atlas_insulin_story_blood to R.string.health_atlas_insulin_story_blood_caption,
        ),
        listOf(
            R.string.health_atlas_insulin_story_glucose_source to "https://pubmed.ncbi.nlm.nih.gov/38775784/",
            R.string.health_atlas_insulin_story_channel_source to "https://pubmed.ncbi.nlm.nih.gov/7821725/",
            R.string.health_atlas_insulin_story_secretion_source to "https://pubmed.ncbi.nlm.nih.gov/18390794/",
        ),
        20_000L,
    );

    val choiceTitle get() = when (this) {
        GLUCOSE -> R.string.health_atlas_lesson_uptake
        MUSCLE_MOTION -> R.string.health_atlas_lesson_contraction
        DIGESTION -> R.string.health_atlas_lesson_digestion
        LYMPH_RETURN -> R.string.health_atlas_lesson_lymph
        ANTIBODY_RESPONSE -> R.string.health_atlas_lesson_antibodies
        INSULIN_SECRETION -> R.string.health_atlas_lesson_insulin
        else -> title
    }

    val relatedLesson get() = when (this) {
        INSULIN_SECRETION -> "tissue-skeletal-muscle" to GLUCOSE
        GLUCOSE -> "cell-pancreatic-beta-cell" to INSULIN_SECRETION
        else -> null
    }

    fun chapter(value: Float) = (safePhase(value) * chapters.size).toInt().coerceAtMost(chapters.lastIndex)
    fun fraction(value: Float) = (safePhase(value) * chapters.size - chapter(value)).coerceIn(0f, 1f)
    fun startOf(chapter: Int) = chapter.coerceIn(chapters.indices) / chapters.size.toFloat()
    fun createArt(context: Context): HealthAtlasFunctionArt = when (this) {
        GLUCOSE -> HealthAtlasUptakeView(context)
        HEARTBEAT -> HealthAtlasHeartbeatView(context)
        BREATHING -> HealthAtlasBreathingView(context)
        HEARING -> HealthAtlasHearingStoryView(context)
        NEPHRON -> HealthAtlasNephronStoryView(context)
        DIGESTION, COLON -> HealthAtlasDigestiveStoryView(context, this)
        VISION, LIGHT_ADAPTATION -> HealthAtlasVisionStoryView(context, this)
        MUSCLE_MOTION, BONE_REMODELING -> HealthAtlasMovementStoryView(context, this)
        LYMPH_RETURN, ANTIBODY_RESPONSE -> HealthAtlasLymphImmuneStoryView(context, this)
        INSULIN_SECRETION -> HealthAtlasInsulinStoryView(context)
    }

    companion object {
        fun forId(id: String?) = if (id == null) null else entries.firstOrNull { id in it.owners }

        fun choicesForId(id: String?): List<HealthAtlasFunctionStory> {
            val primary = forId(id) ?: return emptyList()
            val additional = when (id) {
                "pancreas" -> INSULIN_SECRETION
                "tissue-skeletal-muscle" -> MUSCLE_MOTION
                "immune" -> LYMPH_RETURN
                else -> null
            }
            return listOfNotNull(primary, additional)
        }

        fun safePhase(value: Float) = if (value.isFinite()) value.coerceIn(0f, 1f) else 0f
    }
}
