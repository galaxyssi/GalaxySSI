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
    val showStructurePreview: Boolean = false,
) {
    GLUCOSE(
        setOf("tissue-skeletal-muscle", "tissue-white-adipose", "cell-adipocyte"),
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
            R.string.health_atlas_uptake_pathway_reference to "https://pmc.ncbi.nlm.nih.gov/articles/PMC1899973/",
        ),
        15_000L,
    ),
    HEARTBEAT(
        setOf("heart", "cardio", "atria", "ventricles", "heart-valves", "left-atrium", "right-atrium",
            "left-ventricle", "right-ventricle", "tricuspid-valve", "mitral-valve", "pulmonary-valve", "aortic-valve",
            "tissue-cardiac-muscle", "aorta", "pulmonary-trunk"),
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
            "alveoli", "respiratory-membrane", "pulmonary-capillaries", "tissue-alveolar-epithelium", "cell-type-i-pneumocyte"),
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
        setOf("gut", "digestive", "oral-cavity", "tongue", "pharynx", "esophagus", "stomach", "small-intestine",
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
            "proximal-tubule", "nephron-loop", "distal-tubule", "collecting-ducts", "tissue-renal-tubular-epithelium",
            "renal-cortex", "renal-medulla", "cell-proximal-tubular-cell", "cell-collecting-duct-principal-cell"),
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
        setOf("sensory", "eye", "cornea", "lens", "retina", "cell-retinal-bipolar-cell", "cell-retinal-ganglion-cell"),
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
        showStructurePreview = true,
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
        showStructurePreview = true,
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
        showStructurePreview = true,
    ),
    GLUCAGON_RESPONSE(
        setOf("cell-pancreatic-alpha-cell", "liver", "cell-hepatocyte"),
        R.string.health_atlas_home_glucagon_story_title,
        R.string.health_atlas_home_glucagon_story_scope,
        listOf(
            R.string.health_atlas_home_glucagon_story_signal to R.string.health_atlas_home_glucagon_story_signal_caption,
            R.string.health_atlas_home_glucagon_story_release to R.string.health_atlas_home_glucagon_story_release_caption,
            R.string.health_atlas_home_glucagon_story_liver to R.string.health_atlas_home_glucagon_story_liver_caption,
            R.string.health_atlas_home_glucagon_story_glycogen to R.string.health_atlas_home_glucagon_story_glycogen_caption,
            R.string.health_atlas_home_glucagon_story_export to R.string.health_atlas_home_glucagon_story_export_caption,
        ),
        listOf(
            R.string.health_atlas_home_glucagon_source_alpha to "https://pmc.ncbi.nlm.nih.gov/articles/PMC13147482/",
            R.string.health_atlas_home_glucagon_source_liver to "https://pubmed.ncbi.nlm.nih.gov/7859939/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    SWEAT_COOLING(
        setOf("skin", "sweat-glands", "cell-sweat-gland-secretory-cell"),
        R.string.health_atlas_home_sweat_story_title,
        R.string.health_atlas_home_sweat_story_scope,
        listOf(
            R.string.health_atlas_home_sweat_story_signal to R.string.health_atlas_home_sweat_story_signal_caption,
            R.string.health_atlas_home_sweat_story_fluid to R.string.health_atlas_home_sweat_story_fluid_caption,
            R.string.health_atlas_home_sweat_story_salt to R.string.health_atlas_home_sweat_story_salt_caption,
            R.string.health_atlas_home_sweat_story_surface to R.string.health_atlas_home_sweat_story_surface_caption,
            R.string.health_atlas_home_sweat_story_evaporate to R.string.health_atlas_home_sweat_story_evaporate_caption,
        ),
        listOf(
            R.string.health_atlas_home_sweat_source_fluid to "https://pubmed.ncbi.nlm.nih.gov/29745799/",
            R.string.health_atlas_home_sweat_source_evaporation to "https://pubmed.ncbi.nlm.nih.gov/438022/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    SYNAPTIC_SIGNAL(
        setOf("nervous", "brain", "spinal-cord", "cell-neuron", "tissue-central-nervous"),
        R.string.health_atlas_signal_neuro_title,
        R.string.health_atlas_signal_neuro_scope,
        listOf(
            R.string.health_atlas_signal_neuro_inputs to R.string.health_atlas_signal_neuro_inputs_caption,
            R.string.health_atlas_signal_neuro_travel to R.string.health_atlas_signal_neuro_travel_caption,
            R.string.health_atlas_signal_neuro_calcium to R.string.health_atlas_signal_neuro_calcium_caption,
            R.string.health_atlas_signal_neuro_release to R.string.health_atlas_signal_neuro_release_caption,
            R.string.health_atlas_signal_neuro_response to R.string.health_atlas_signal_neuro_response_caption,
        ),
        listOf(
            R.string.health_atlas_signal_neuro_calcium_source to "https://pubmed.ncbi.nlm.nih.gov/11160426/",
            R.string.health_atlas_signal_neuro_clearance_source to "https://pmc.ncbi.nlm.nih.gov/articles/PMC6725141/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    MYELIN_SIGNAL(
        setOf("spinal-nerves", "peripheral-nerves", "cell-schwann-cell", "cell-oligodendrocyte"),
        R.string.health_atlas_signal_myelin_title,
        R.string.health_atlas_signal_myelin_scope,
        listOf(
            R.string.health_atlas_signal_myelin_central to R.string.health_atlas_signal_myelin_central_caption,
            R.string.health_atlas_signal_myelin_peripheral to R.string.health_atlas_signal_myelin_peripheral_caption,
            R.string.health_atlas_signal_myelin_nodes to R.string.health_atlas_signal_myelin_nodes_caption,
            R.string.health_atlas_signal_myelin_relay to R.string.health_atlas_signal_myelin_relay_caption,
            R.string.health_atlas_signal_myelin_compare to R.string.health_atlas_signal_myelin_compare_caption,
        ),
        listOf(
            R.string.health_atlas_signal_myelin_source to "https://pubmed.ncbi.nlm.nih.gov/18144923/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    THYROID_FEEDBACK(
        setOf("thyroid-gland", "hypothalamus", "pituitary-gland", "cell-thyrotroph", "cell-thyroid-follicular-cell"),
        R.string.health_atlas_signal_thyroid_title,
        R.string.health_atlas_signal_thyroid_scope,
        listOf(
            R.string.health_atlas_signal_thyroid_trh to R.string.health_atlas_signal_thyroid_trh_caption,
            R.string.health_atlas_signal_thyroid_tsh to R.string.health_atlas_signal_thyroid_tsh_caption,
            R.string.health_atlas_signal_thyroid_secrete to R.string.health_atlas_signal_thyroid_secrete_caption,
            R.string.health_atlas_signal_thyroid_convert to R.string.health_atlas_signal_thyroid_convert_caption,
            R.string.health_atlas_signal_thyroid_feedback to R.string.health_atlas_signal_thyroid_feedback_caption,
        ),
        listOf(
            R.string.health_atlas_signal_thyroid_trh_source to "https://pubmed.ncbi.nlm.nih.gov/828584/",
            R.string.health_atlas_signal_thyroid_conversion_source to "https://pubmed.ncbi.nlm.nih.gov/6841556/",
            R.string.health_atlas_signal_thyroid_feedback_source to "https://pubmed.ncbi.nlm.nih.gov/815265/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    EPIDERMAL_BARRIER(
        setOf("skin-organ", "epidermis", "tissue-epidermal", "cell-keratinocyte"),
        R.string.health_atlas_barrier_title,
        R.string.health_atlas_barrier_scope,
        listOf(
            R.string.health_atlas_barrier_birth to R.string.health_atlas_barrier_birth_caption,
            R.string.health_atlas_barrier_flatten to R.string.health_atlas_barrier_flatten_caption,
            R.string.health_atlas_barrier_lipids to R.string.health_atlas_barrier_lipids_caption,
            R.string.health_atlas_barrier_water to R.string.health_atlas_barrier_water_caption,
            R.string.health_atlas_barrier_shed to R.string.health_atlas_barrier_shed_caption,
        ),
        listOf(
            R.string.health_atlas_barrier_source_lipids to "https://pubmed.ncbi.nlm.nih.gov/23345770/",
            R.string.health_atlas_barrier_source_secretion to "https://doi.org/10.1002/ar.1091890404",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    SPERM_TRANSPORT(
        setOf("male", "testes", "epididymis", "vas-deferens", "cell-spermatozoon",
            "cell-sertoli-cell", "cell-spermatogonium", "cell-spermatocyte"),
        R.string.health_atlas_sperm_flow_title,
        R.string.health_atlas_sperm_flow_scope,
        listOf(
            R.string.health_atlas_sperm_flow_form to R.string.health_atlas_sperm_flow_form_caption,
            R.string.health_atlas_sperm_flow_transfer to R.string.health_atlas_sperm_flow_transfer_caption,
            R.string.health_atlas_sperm_flow_mature to R.string.health_atlas_sperm_flow_mature_caption,
            R.string.health_atlas_sperm_flow_store to R.string.health_atlas_sperm_flow_store_caption,
            R.string.health_atlas_sperm_flow_move to R.string.health_atlas_sperm_flow_move_caption,
        ),
        listOf(
            R.string.health_atlas_sperm_flow_source_mature to "https://pubmed.ncbi.nlm.nih.gov/7431338/",
            R.string.health_atlas_sperm_flow_source_storage to "https://pubmed.ncbi.nlm.nih.gov/9739420/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    OVUM_TRANSPORT(
        setOf("female", "ovaries", "uterine-tubes", "cell-oocyte-or-ovum",
            "cell-granulosa-cell", "cell-ciliated-oviduct-cell"),
        R.string.health_atlas_ovum_flow_title,
        R.string.health_atlas_ovum_flow_scope,
        listOf(
            R.string.health_atlas_ovum_flow_grow to R.string.health_atlas_ovum_flow_grow_caption,
            R.string.health_atlas_ovum_flow_release to R.string.health_atlas_ovum_flow_release_caption,
            R.string.health_atlas_ovum_flow_pickup to R.string.health_atlas_ovum_flow_pickup_caption,
            R.string.health_atlas_ovum_flow_cilia to R.string.health_atlas_ovum_flow_cilia_caption,
            R.string.health_atlas_ovum_flow_ampulla to R.string.health_atlas_ovum_flow_ampulla_caption,
        ),
        listOf(
            R.string.health_atlas_ovum_flow_source_release to "https://pubmed.ncbi.nlm.nih.gov/7211967/",
            R.string.health_atlas_ovum_flow_source_human_cilia to "https://pubmed.ncbi.nlm.nih.gov/11870107/",
            R.string.health_atlas_ovum_flow_source_pickup to "https://pubmed.ncbi.nlm.nih.gov/34039711/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    OLFACTION(
        setOf("nose", "nasal-cavity", "olfactory-mucosa", "cell-olfactory-receptor-neuron"),
        R.string.health_atlas_sense_smell_title,
        R.string.health_atlas_sense_smell_scope,
        listOf(
            R.string.health_atlas_sense_smell_air to R.string.health_atlas_sense_smell_air_caption,
            R.string.health_atlas_sense_smell_mucus to R.string.health_atlas_sense_smell_mucus_caption,
            R.string.health_atlas_sense_smell_receptor to R.string.health_atlas_sense_smell_receptor_caption,
            R.string.health_atlas_sense_smell_bulb to R.string.health_atlas_sense_smell_bulb_caption,
            R.string.health_atlas_sense_smell_pattern to R.string.health_atlas_sense_smell_pattern_caption,
        ),
        listOf(
            R.string.health_atlas_sense_smell_ref_tissue to "https://pubmed.ncbi.nlm.nih.gov/21792956/",
            R.string.health_atlas_sense_smell_ref_bulb to "https://www.nature.com/articles/s41467-020-14520-9",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    TASTE_SIGNAL(
        setOf("taste-buds", "cell-taste-receptor-cell"),
        R.string.health_atlas_sense_taste_title,
        R.string.health_atlas_sense_taste_scope,
        listOf(
            R.string.health_atlas_sense_taste_dissolve to R.string.health_atlas_sense_taste_dissolve_caption,
            R.string.health_atlas_sense_taste_pore to R.string.health_atlas_sense_taste_pore_caption,
            R.string.health_atlas_sense_taste_receptor to R.string.health_atlas_sense_taste_receptor_caption,
            R.string.health_atlas_sense_taste_atp to R.string.health_atlas_sense_taste_atp_caption,
            R.string.health_atlas_sense_taste_relay to R.string.health_atlas_sense_taste_relay_caption,
        ),
        listOf(
            R.string.health_atlas_sense_taste_ref_atp to "https://pmc.ncbi.nlm.nih.gov/articles/PMC3600154/",
            R.string.health_atlas_sense_taste_ref_channel to "https://pmc.ncbi.nlm.nih.gov/articles/PMC5934295/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    TOUCH_SIGNAL(
        setOf("cell-merkel-cell"),
        R.string.health_atlas_sense_touch_title,
        R.string.health_atlas_sense_touch_scope,
        listOf(
            R.string.health_atlas_sense_touch_contact to R.string.health_atlas_sense_touch_contact_caption,
            R.string.health_atlas_sense_touch_deform to R.string.health_atlas_sense_touch_deform_caption,
            R.string.health_atlas_sense_touch_channel to R.string.health_atlas_sense_touch_channel_caption,
            R.string.health_atlas_sense_touch_steady to R.string.health_atlas_sense_touch_steady_caption,
            R.string.health_atlas_sense_touch_release to R.string.health_atlas_sense_touch_release_caption,
        ),
        listOf(
            R.string.health_atlas_sense_touch_ref_human to "https://pubmed.ncbi.nlm.nih.gov/27653382/",
            R.string.health_atlas_sense_touch_ref_merkel to "https://www.nature.com/articles/nature13250",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    VESTIBULAR_BALANCE(
        setOf("vestibular-apparatus"),
        R.string.health_atlas_sense_balance_title,
        R.string.health_atlas_sense_balance_scope,
        listOf(
            R.string.health_atlas_sense_balance_map to R.string.health_atlas_sense_balance_map_caption,
            R.string.health_atlas_sense_balance_turn to R.string.health_atlas_sense_balance_turn_caption,
            R.string.health_atlas_sense_balance_cupula to R.string.health_atlas_sense_balance_cupula_caption,
            R.string.health_atlas_sense_balance_tilt to R.string.health_atlas_sense_balance_tilt_caption,
            R.string.health_atlas_sense_balance_gaze to R.string.health_atlas_sense_balance_gaze_caption,
        ),
        listOf(
            R.string.health_atlas_sense_balance_ref_canal to "https://pubmed.ncbi.nlm.nih.gov/11710461/",
            R.string.health_atlas_sense_balance_ref_otolith to "https://pubmed.ncbi.nlm.nih.gov/12867670/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    RPE_VISUAL_CYCLE(
        setOf("cell-retinal-pigment-epithelial-cell"),
        R.string.health_atlas_ocular_pigment_title,
        R.string.health_atlas_ocular_pigment_scope,
        listOf(
            R.string.health_atlas_ocular_pigment_layers to R.string.health_atlas_ocular_pigment_layers_caption,
            R.string.health_atlas_ocular_pigment_light to R.string.health_atlas_ocular_pigment_light_caption,
            R.string.health_atlas_ocular_pigment_outbound to R.string.health_atlas_ocular_pigment_outbound_caption,
            R.string.health_atlas_ocular_pigment_processing to R.string.health_atlas_ocular_pigment_processing_caption,
            R.string.health_atlas_ocular_pigment_return to R.string.health_atlas_ocular_pigment_return_caption,
        ),
        listOf(
            R.string.health_atlas_ocular_pigment_ref_human to "https://pmc.ncbi.nlm.nih.gov/articles/PMC1131412/",
            R.string.health_atlas_ocular_pigment_ref_enzyme to "https://pubmed.ncbi.nlm.nih.gov/9843205/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    DIM_LIGHT_RELAY(
        setOf("cell-retinal-aii-amacrine-cell"),
        R.string.health_atlas_ocular_relay_title,
        R.string.health_atlas_ocular_relay_scope,
        listOf(
            R.string.health_atlas_ocular_relay_rods to R.string.health_atlas_ocular_relay_rods_caption,
            R.string.health_atlas_ocular_relay_bipolar to R.string.health_atlas_ocular_relay_bipolar_caption,
            R.string.health_atlas_ocular_relay_aii to R.string.health_atlas_ocular_relay_aii_caption,
            R.string.health_atlas_ocular_relay_branches to R.string.health_atlas_ocular_relay_branches_caption,
            R.string.health_atlas_ocular_relay_out to R.string.health_atlas_ocular_relay_out_caption,
        ),
        listOf(
            R.string.health_atlas_ocular_relay_ref_circuit to "https://pmc.ncbi.nlm.nih.gov/articles/PMC6133723/",
            R.string.health_atlas_ocular_relay_ref_junction to "https://pmc.ncbi.nlm.nih.gov/articles/PMC2834592/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    CORNEAL_SURFACE_RENEWAL(
        setOf("cell-corneal-epithelial-cell"),
        R.string.health_atlas_ocular_cornea_title,
        R.string.health_atlas_ocular_cornea_scope,
        listOf(
            R.string.health_atlas_ocular_cornea_barrier to R.string.health_atlas_ocular_cornea_barrier_caption,
            R.string.health_atlas_ocular_cornea_limbus to R.string.health_atlas_ocular_cornea_limbus_caption,
            R.string.health_atlas_ocular_cornea_migration to R.string.health_atlas_ocular_cornea_migration_caption,
            R.string.health_atlas_ocular_cornea_layers to R.string.health_atlas_ocular_cornea_layers_caption,
            R.string.health_atlas_ocular_cornea_shed to R.string.health_atlas_ocular_cornea_shed_caption,
        ),
        listOf(
            R.string.health_atlas_ocular_cornea_ref_human to "https://pubmed.ncbi.nlm.nih.gov/33865984/",
            R.string.health_atlas_ocular_cornea_ref_lineage to "https://pmc.ncbi.nlm.nih.gov/articles/PMC5639292/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    AIRWAY_CLEARANCE(
        setOf("tissue-respiratory-epithelium", "cell-ciliated-airway-cell", "cell-goblet-cell"),
        R.string.health_atlas_airway_title,
        R.string.health_atlas_airway_scope,
        listOf(
            R.string.health_atlas_airway_catch to R.string.health_atlas_airway_catch_caption,
            R.string.health_atlas_airway_secrete to R.string.health_atlas_airway_secrete_caption,
            R.string.health_atlas_airway_beat to R.string.health_atlas_airway_beat_caption,
            R.string.health_atlas_airway_move to R.string.health_atlas_airway_move_caption,
            R.string.health_atlas_airway_clear to R.string.health_atlas_airway_clear_caption,
        ),
        listOf(
            R.string.health_atlas_airway_ref_layers to "https://pmc.ncbi.nlm.nih.gov/articles/PMC3633213/",
            R.string.health_atlas_airway_ref_motion to "https://pmc.ncbi.nlm.nih.gov/articles/PMC4504973/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    ENDOTHELIAL_EXCHANGE(
        setOf("tissue-vascular-endothelium", "cell-vascular-endothelial-cell", "capillaries"),
        R.string.health_atlas_endothelium_title,
        R.string.health_atlas_endothelium_scope,
        listOf(
            R.string.health_atlas_endothelium_boundary to
                R.string.health_atlas_endothelium_boundary_caption,
            R.string.health_atlas_endothelium_filtration to
                R.string.health_atlas_endothelium_filtration_caption,
            R.string.health_atlas_endothelium_diffusion to
                R.string.health_atlas_endothelium_diffusion_caption,
            R.string.health_atlas_endothelium_retention to
                R.string.health_atlas_endothelium_retention_caption,
            R.string.health_atlas_endothelium_drainage to
                R.string.health_atlas_endothelium_drainage_caption,
        ),
        listOf(
            R.string.health_atlas_endothelium_ref_filtration to "https://pubmed.ncbi.nlm.nih.gov/3498833/",
            R.string.health_atlas_endothelium_ref_diffusion to "https://pubmed.ncbi.nlm.nih.gov/9841533/",
            R.string.health_atlas_endothelium_ref_albumin to "https://pubmed.ncbi.nlm.nih.gov/2224941/",
            R.string.health_atlas_endothelium_ref_lymph to "https://pubmed.ncbi.nlm.nih.gov/11481218/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    PLATELET_HEMOSTASIS(
        setOf("fragment-platelet"),
        R.string.health_atlas_platelet_hemostasis_title,
        R.string.health_atlas_platelet_hemostasis_scope,
        listOf(
            R.string.health_atlas_platelet_gap to
                R.string.health_atlas_platelet_gap_caption,
            R.string.health_atlas_platelet_adhesion to
                R.string.health_atlas_platelet_adhesion_caption,
            R.string.health_atlas_platelet_activation to
                R.string.health_atlas_platelet_activation_caption,
            R.string.health_atlas_platelet_aggregation to
                R.string.health_atlas_platelet_aggregation_caption,
            R.string.health_atlas_platelet_stabilization to
                R.string.health_atlas_platelet_stabilization_caption,
        ),
        listOf(
            R.string.health_atlas_platelet_ref_adhesion to "https://pubmed.ncbi.nlm.nih.gov/9741630/",
            R.string.health_atlas_platelet_ref_activation to "https://pubmed.ncbi.nlm.nih.gov/27625359/",
            R.string.health_atlas_platelet_ref_fibrin to "https://pubmed.ncbi.nlm.nih.gov/33150735/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    CARTILAGE_LOAD(
        setOf("tissue-hyaline-cartilage", "patella"),
        R.string.health_atlas_cartilage_story_title,
        R.string.health_atlas_cartilage_story_scope,
        listOf(
            R.string.health_atlas_cartilage_story_rest to
                R.string.health_atlas_cartilage_story_rest_caption,
            R.string.health_atlas_cartilage_story_press to
                R.string.health_atlas_cartilage_story_press_caption,
            R.string.health_atlas_cartilage_story_hold to
                R.string.health_atlas_cartilage_story_hold_caption,
            R.string.health_atlas_cartilage_story_unload to
                R.string.health_atlas_cartilage_story_unload_caption,
            R.string.health_atlas_cartilage_story_recover to
                R.string.health_atlas_cartilage_story_recover_caption,
        ),
        listOf(
            R.string.health_atlas_cartilage_story_reference_load to "https://pmc.ncbi.nlm.nih.gov/articles/PMC2833094/",
            R.string.health_atlas_cartilage_story_reference_recovery to "https://pubmed.ncbi.nlm.nih.gov/34800716/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    SMOOTH_MUSCLE_WAVE(
        setOf("tissue-smooth-muscle", "cell-smooth-muscle-cell"),
        R.string.health_atlas_smooth_muscle_story_title,
        R.string.health_atlas_smooth_muscle_story_scope,
        listOf(
            R.string.health_atlas_smooth_muscle_story_fill to
                R.string.health_atlas_smooth_muscle_story_fill_caption,
            R.string.health_atlas_smooth_muscle_story_relax to
                R.string.health_atlas_smooth_muscle_story_relax_caption,
            R.string.health_atlas_smooth_muscle_story_contract to
                R.string.health_atlas_smooth_muscle_story_contract_caption,
            R.string.health_atlas_smooth_muscle_story_propel to
                R.string.health_atlas_smooth_muscle_story_propel_caption,
            R.string.health_atlas_smooth_muscle_story_recover to
                R.string.health_atlas_smooth_muscle_story_recover_caption,
        ),
        listOf(
            R.string.health_atlas_smooth_muscle_story_anatomy_source to "https://pubmed.ncbi.nlm.nih.gov/7367760/",
            R.string.health_atlas_smooth_muscle_story_propulsion_source to "https://pmc.ncbi.nlm.nih.gov/articles/PMC1155880/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    TENDON_FORCE_TRANSFER(
        setOf("tissue-dense-regular-connective"),
        R.string.health_atlas_tendon_story_title,
        R.string.health_atlas_tendon_story_scope,
        listOf(
            R.string.health_atlas_tendon_story_link to
                R.string.health_atlas_tendon_story_link_caption,
            R.string.health_atlas_tendon_story_load to
                R.string.health_atlas_tendon_story_load_caption,
            R.string.health_atlas_tendon_story_uncrimp to
                R.string.health_atlas_tendon_story_uncrimp_caption,
            R.string.health_atlas_tendon_story_transfer to
                R.string.health_atlas_tendon_story_transfer_caption,
            R.string.health_atlas_tendon_story_recoil to
                R.string.health_atlas_tendon_story_recoil_caption,
        ),
        listOf(
            R.string.health_atlas_tendon_story_ref_crimp to "https://pubmed.ncbi.nlm.nih.gov/17229278/",
            R.string.health_atlas_tendon_story_ref_loading to "https://pmc.ncbi.nlm.nih.gov/articles/PMC7955091/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    ALVEOLAR_SURFACTANT(
        setOf("cell-type-ii-pneumocyte"),
        R.string.health_atlas_surfactant_title,
        R.string.health_atlas_surfactant_scope,
        listOf(
            R.string.health_atlas_surfactant_locate to
                R.string.health_atlas_surfactant_locate_caption,
            R.string.health_atlas_surfactant_release to
                R.string.health_atlas_surfactant_release_caption,
            R.string.health_atlas_surfactant_spread to
                R.string.health_atlas_surfactant_spread_caption,
            R.string.health_atlas_surfactant_inhale to
                R.string.health_atlas_surfactant_inhale_caption,
            R.string.health_atlas_surfactant_exhale to
                R.string.health_atlas_surfactant_exhale_caption,
        ),
        listOf(
            R.string.health_atlas_surfactant_ref_secretion to "https://pubmed.ncbi.nlm.nih.gov/14704221/",
            R.string.health_atlas_surfactant_ref_film to "https://pubmed.ncbi.nlm.nih.gov/1730014/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    INTESTINAL_ABSORPTION(
        setOf("tissue-intestinal-epithelium"),
        R.string.health_atlas_absorption_story_title,
        R.string.health_atlas_absorption_story_scope,
        listOf(
            R.string.health_atlas_absorption_story_villus to
                R.string.health_atlas_absorption_story_villus_caption,
            R.string.health_atlas_absorption_story_brush_border to
                R.string.health_atlas_absorption_story_brush_border_caption,
            R.string.health_atlas_absorption_story_blood to
                R.string.health_atlas_absorption_story_blood_caption,
            R.string.health_atlas_absorption_story_package to
                R.string.health_atlas_absorption_story_package_caption,
            R.string.health_atlas_absorption_story_lymph to
                R.string.health_atlas_absorption_story_lymph_caption,
        ),
        listOf(
            R.string.health_atlas_absorption_story_soluble_source to "https://pubmed.ncbi.nlm.nih.gov/4852103/",
            R.string.health_atlas_absorption_story_lipid_source to "https://www.jci.org/articles/view/106700",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    KNEE_ARTICULATION(
        setOf("joints", "femur", "tibia", "quadriceps-femoris", "hamstrings"),
        R.string.health_atlas_knee_title,
        R.string.health_atlas_knee_scope,
        listOf(
            R.string.health_atlas_knee_map to R.string.health_atlas_knee_map_caption,
            R.string.health_atlas_knee_bend to R.string.health_atlas_knee_bend_caption,
            R.string.health_atlas_knee_glide to R.string.health_atlas_knee_glide_caption,
            R.string.health_atlas_knee_extend to R.string.health_atlas_knee_extend_caption,
            R.string.health_atlas_knee_return to R.string.health_atlas_knee_return_caption,
        ),
        listOf(
            R.string.health_atlas_knee_ref_imaging to "https://pubmed.ncbi.nlm.nih.gov/23806309/",
            R.string.health_atlas_knee_ref_pull to "https://pubmed.ncbi.nlm.nih.gov/10619099/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    CARDIAC_EXCITATION(
        setOf("cell-cardiomyocyte"),
        R.string.health_atlas_cardiac_title,
        R.string.health_atlas_cardiac_scope,
        listOf(
            R.string.health_atlas_cardiac_pace to R.string.health_atlas_cardiac_pace_caption,
            R.string.health_atlas_cardiac_delay to R.string.health_atlas_cardiac_delay_caption,
            R.string.health_atlas_cardiac_spread to R.string.health_atlas_cardiac_spread_caption,
            R.string.health_atlas_cardiac_shorten to R.string.health_atlas_cardiac_shorten_caption,
            R.string.health_atlas_cardiac_relax to R.string.health_atlas_cardiac_relax_caption,
        ),
        listOf(
            R.string.health_atlas_cardiac_ref_conduction to "https://pubmed.ncbi.nlm.nih.gov/5482907/",
            R.string.health_atlas_cardiac_ref_cell to "https://pubmed.ncbi.nlm.nih.gov/26200878/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    RED_CELL_OXYGEN(
        setOf("blood", "cell-erythrocyte"),
        R.string.health_atlas_red_cell_story_title,
        R.string.health_atlas_red_cell_story_scope,
        listOf(
            R.string.health_atlas_red_cell_story_cell to
                R.string.health_atlas_red_cell_story_cell_caption,
            R.string.health_atlas_red_cell_story_loading to
                R.string.health_atlas_red_cell_story_loading_caption,
            R.string.health_atlas_red_cell_story_transport to
                R.string.health_atlas_red_cell_story_transport_caption,
            R.string.health_atlas_red_cell_story_release to
                R.string.health_atlas_red_cell_story_release_caption,
            R.string.health_atlas_red_cell_story_diffusion to
                R.string.health_atlas_red_cell_story_diffusion_caption,
        ),
        listOf(
            R.string.health_atlas_red_cell_story_ref_binding to "https://doi.org/10.1016/S0021-9258(18)85018-9",
            R.string.health_atlas_red_cell_story_ref_microcirculation to "https://pubmed.ncbi.nlm.nih.gov/32445225/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    SALIVA_SECRETION(
        setOf("parotid-glands", "submandibular-glands", "sublingual-glands", "cell-salivary-acinar-cell"),
        R.string.health_atlas_saliva_story_title,
        R.string.health_atlas_saliva_story_scope,
        listOf(
            R.string.health_atlas_saliva_story_locate to
                R.string.health_atlas_saliva_story_locate_caption,
            R.string.health_atlas_saliva_story_acinus to
                R.string.health_atlas_saliva_story_acinus_caption,
            R.string.health_atlas_saliva_story_release to
                R.string.health_atlas_saliva_story_release_caption,
            R.string.health_atlas_saliva_story_modify to
                R.string.health_atlas_saliva_story_modify_caption,
            R.string.health_atlas_saliva_story_empty to
                R.string.health_atlas_saliva_story_empty_caption,
        ),
        listOf(
            R.string.health_atlas_saliva_story_ref_duct to "https://link.springer.com/article/10.1007/BF00362655",
            R.string.health_atlas_saliva_story_ref_human to "https://pmc.ncbi.nlm.nih.gov/articles/PMC1357582/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    VENOUS_RETURN(
        setOf("veins", "gastrocnemius", "soleus"),
        R.string.health_atlas_venous_return_story_title,
        R.string.health_atlas_venous_return_story_scope,
        listOf(
            R.string.health_atlas_venous_return_story_locate to
                R.string.health_atlas_venous_return_story_locate_caption,
            R.string.health_atlas_venous_return_story_squeeze to
                R.string.health_atlas_venous_return_story_squeeze_caption,
            R.string.health_atlas_venous_return_story_propel to
                R.string.health_atlas_venous_return_story_propel_caption,
            R.string.health_atlas_venous_return_story_limit to
                R.string.health_atlas_venous_return_story_limit_caption,
            R.string.health_atlas_venous_return_story_refill to
                R.string.health_atlas_venous_return_story_refill_caption,
        ),
        listOf(
            R.string.health_atlas_venous_return_story_ref_pump to "https://pubmed.ncbi.nlm.nih.gov/23455014/",
            R.string.health_atlas_venous_return_story_ref_valves to "https://pubmed.ncbi.nlm.nih.gov/14603200/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    HAIR_FOLLICLE_CYCLE(
        setOf("hair", "hair-follicles", "cell-hair-matrix-cell"),
        R.string.health_atlas_hair_cycle_story_title,
        R.string.health_atlas_hair_cycle_story_scope,
        listOf(
            R.string.health_atlas_hair_cycle_story_matrix to
                R.string.health_atlas_hair_cycle_story_matrix_caption,
            R.string.health_atlas_hair_cycle_story_growth to
                R.string.health_atlas_hair_cycle_story_growth_caption,
            R.string.health_atlas_hair_cycle_story_regression to
                R.string.health_atlas_hair_cycle_story_regression_caption,
            R.string.health_atlas_hair_cycle_story_rest to
                R.string.health_atlas_hair_cycle_story_rest_caption,
            R.string.health_atlas_hair_cycle_story_renewal to
                R.string.health_atlas_hair_cycle_story_renewal_caption,
        ),
        listOf(
            R.string.health_atlas_hair_cycle_story_reference_regression to "https://pubmed.ncbi.nlm.nih.gov/9856801/",
            R.string.health_atlas_hair_cycle_story_reference_shedding to "https://pubmed.ncbi.nlm.nih.gov/17908196/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    URINE_ROUTE(
        setOf("renal-pelvis", "ureters", "bladder", "urethra"),
        R.string.health_atlas_urine_route_story_title,
        R.string.health_atlas_urine_route_story_scope,
        listOf(
            R.string.health_atlas_urine_route_story_collect to
                R.string.health_atlas_urine_route_story_collect_caption,
            R.string.health_atlas_urine_route_story_peristalsis to
                R.string.health_atlas_urine_route_story_peristalsis_caption,
            R.string.health_atlas_urine_route_story_junction to
                R.string.health_atlas_urine_route_story_junction_caption,
            R.string.health_atlas_urine_route_story_store to
                R.string.health_atlas_urine_route_story_store_caption,
            R.string.health_atlas_urine_route_story_empty to
                R.string.health_atlas_urine_route_story_empty_caption,
        ),
        listOf(
            R.string.health_atlas_urine_route_story_ref_junction to "https://pure.amsterdamumc.nl/en/publications/functional-anatomy-of-the-human-ureterovesical-junction/",
            R.string.health_atlas_urine_route_story_ref_emptying to "https://pubmed.ncbi.nlm.nih.gov/40899193/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    PLEURAL_COUPLING(
        setOf("pleura"),
        R.string.health_atlas_pleura_story_title,
        R.string.health_atlas_pleura_story_scope,
        listOf(
            R.string.health_atlas_pleura_story_layers to
                R.string.health_atlas_pleura_story_layers_caption,
            R.string.health_atlas_pleura_story_expand to
                R.string.health_atlas_pleura_story_expand_caption,
            R.string.health_atlas_pleura_story_follow to
                R.string.health_atlas_pleura_story_follow_caption,
            R.string.health_atlas_pleura_story_slide to
                R.string.health_atlas_pleura_story_slide_caption,
            R.string.health_atlas_pleura_story_return to
                R.string.health_atlas_pleura_story_return_caption,
        ),
        listOf(
            R.string.health_atlas_pleura_story_ref_sliding to "https://pubmed.ncbi.nlm.nih.gov/15351304/",
            R.string.health_atlas_pleura_story_ref_motion to "https://pmc.ncbi.nlm.nih.gov/articles/PMC9785439/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    PARATHYROID_FEEDBACK(
        setOf("parathyroid-glands", "cell-parathyroid-chief-cell"),
        R.string.health_atlas_calcium_feedback_story_title,
        R.string.health_atlas_calcium_feedback_story_scope,
        listOf(
            R.string.health_atlas_calcium_feedback_story_sense to
                R.string.health_atlas_calcium_feedback_story_sense_caption,
            R.string.health_atlas_calcium_feedback_story_release to
                R.string.health_atlas_calcium_feedback_story_release_caption,
            R.string.health_atlas_calcium_feedback_story_kidney to
                R.string.health_atlas_calcium_feedback_story_kidney_caption,
            R.string.health_atlas_calcium_feedback_story_intestine to
                R.string.health_atlas_calcium_feedback_story_intestine_caption,
            R.string.health_atlas_calcium_feedback_story_recover to
                R.string.health_atlas_calcium_feedback_story_recover_caption,
        ),
        listOf(
            R.string.health_atlas_calcium_feedback_story_ref_sensing to "https://pubmed.ncbi.nlm.nih.gov/7759551/",
            R.string.health_atlas_calcium_feedback_story_ref_vitamin_d to "https://pubmed.ncbi.nlm.nih.gov/4340153/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    MAMMARY_MILK_FLOW(
        setOf("mammary-glands", "cell-mammary-luminal-cell", "cell-myoepithelial-cell"),
        R.string.health_atlas_mammary_story_title,
        R.string.health_atlas_mammary_story_scope,
        listOf(
            R.string.health_atlas_mammary_story_locate to
                R.string.health_atlas_mammary_story_locate_caption,
            R.string.health_atlas_mammary_story_secrete to
                R.string.health_atlas_mammary_story_secrete_caption,
            R.string.health_atlas_mammary_story_accumulate to
                R.string.health_atlas_mammary_story_accumulate_caption,
            R.string.health_atlas_mammary_story_contract to
                R.string.health_atlas_mammary_story_contract_caption,
            R.string.health_atlas_mammary_story_eject to
                R.string.health_atlas_mammary_story_eject_caption,
        ),
        listOf(
            R.string.health_atlas_mammary_story_ref_secretion to "https://pubmed.ncbi.nlm.nih.gov/28179456/",
            R.string.health_atlas_mammary_story_ref_ejection to "https://pmc.ncbi.nlm.nih.gov/articles/PMC7604439/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    NEUTROPHIL_DEFENSE(
        setOf("cell-neutrophil"),
        R.string.health_atlas_process_neutrophil_title, R.string.health_atlas_neutrophil_scope,
        listOf(
            R.string.health_atlas_process_neutrophil_0 to R.string.health_atlas_cell_play_neutrophil_0_caption,
            R.string.health_atlas_process_neutrophil_1 to R.string.health_atlas_cell_play_neutrophil_1_caption,
            R.string.health_atlas_process_neutrophil_2 to R.string.health_atlas_cell_play_neutrophil_2_caption,
            R.string.health_atlas_process_neutrophil_3 to R.string.health_atlas_cell_play_neutrophil_3_caption,
        ),
        listOf(R.string.health_atlas_reference_openstax to
            "https://openstax.org/books/anatomy-and-physiology-2e/pages/18-4-leukocytes-and-platelets"),
        16_000L,
        showStructurePreview = true,
    ),
    EOSINOPHIL_RESPONSE(
        setOf("cell-eosinophil"),
        R.string.health_atlas_process_eosinophil_title, R.string.health_atlas_eosinophil_scope,
        listOf(
            R.string.health_atlas_process_eosinophil_0 to R.string.health_atlas_cell_play_eosinophil_0_caption,
            R.string.health_atlas_process_eosinophil_1 to R.string.health_atlas_cell_play_eosinophil_1_caption,
            R.string.health_atlas_process_eosinophil_2 to R.string.health_atlas_cell_play_eosinophil_2_caption,
            R.string.health_atlas_process_eosinophil_3 to R.string.health_atlas_cell_play_eosinophil_3_caption,
        ),
        listOf(R.string.health_atlas_reference_openstax to
            "https://openstax.org/books/anatomy-and-physiology-2e/pages/18-4-leukocytes-and-platelets"),
        16_000L,
        showStructurePreview = true,
    ),
    BASOPHIL_SIGNALING(
        setOf("cell-basophil"),
        R.string.health_atlas_process_basophil_title, R.string.health_atlas_basophil_scope,
        listOf(
            R.string.health_atlas_process_basophil_0 to R.string.health_atlas_cell_play_basophil_0_caption,
            R.string.health_atlas_process_basophil_1 to R.string.health_atlas_cell_play_basophil_1_caption,
            R.string.health_atlas_process_basophil_2 to R.string.health_atlas_cell_play_basophil_2_caption,
            R.string.health_atlas_process_basophil_3 to R.string.health_atlas_cell_play_basophil_3_caption,
        ),
        listOf(R.string.health_atlas_reference_openstax to
            "https://openstax.org/books/anatomy-and-physiology-2e/pages/18-4-leukocytes-and-platelets"),
        16_000L,
        showStructurePreview = true,
    ),
    MONOCYTE_RECRUITMENT(
        setOf("cell-monocyte"),
        R.string.health_atlas_process_monocyte_title, R.string.health_atlas_monocyte_lesson_scope,
        listOf(
            R.string.health_atlas_process_monocyte_0 to R.string.health_atlas_cell_play_monocyte_0_caption,
            R.string.health_atlas_process_monocyte_1 to R.string.health_atlas_cell_play_monocyte_1_caption,
            R.string.health_atlas_process_monocyte_2 to R.string.health_atlas_cell_play_monocyte_2_caption,
            R.string.health_atlas_process_monocyte_3 to R.string.health_atlas_cell_play_monocyte_3_caption,
        ),
        listOf(R.string.health_atlas_reference_openstax to
            "https://openstax.org/books/anatomy-and-physiology-2e/pages/18-4-leukocytes-and-platelets"),
        16_000L,
        showStructurePreview = true,
    ),
    DENDRITIC_PRESENTATION(
        setOf("cell-dendritic-cell"),
        R.string.health_atlas_process_cell_dendritic_cell_title, R.string.health_atlas_dendritic_lesson_scope,
        listOf(
            R.string.health_atlas_process_cell_dendritic_cell_0 to R.string.health_atlas_cell_play_dendritic_0_caption,
            R.string.health_atlas_process_cell_dendritic_cell_1 to R.string.health_atlas_cell_play_dendritic_1_caption,
            R.string.health_atlas_process_cell_dendritic_cell_2 to R.string.health_atlas_cell_play_dendritic_2_caption,
            R.string.health_atlas_process_cell_dendritic_cell_3 to R.string.health_atlas_cell_play_dendritic_3_caption,
        ),
        listOf(R.string.health_atlas_reference_openstax to
            "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-3-the-adaptive-immune-response-t-lymphocytes-and-their-functional-types"),
        16_000L,
        showStructurePreview = true,
    ),
    T_CELL_RESPONSE(
        setOf("cell-t-cell"),
        R.string.health_atlas_process_t_cell_title, R.string.health_atlas_t_lesson_scope,
        listOf(
            R.string.health_atlas_process_t_cell_0 to R.string.health_atlas_cell_play_t_cell_0_caption,
            R.string.health_atlas_process_t_cell_1 to R.string.health_atlas_cell_play_t_cell_1_caption,
            R.string.health_atlas_process_t_cell_2 to R.string.health_atlas_cell_play_t_cell_2_caption,
            R.string.health_atlas_process_t_cell_3 to R.string.health_atlas_cell_play_t_cell_3_caption,
        ),
        listOf(R.string.health_atlas_reference_openstax to
            "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-3-the-adaptive-immune-response-t-lymphocytes-and-their-functional-types"),
        16_000L,
        showStructurePreview = true,
    ),
    NK_SURVEILLANCE(
        setOf("cell-natural-killer-cell"),
        R.string.health_atlas_process_natural_killer_cell_title, R.string.health_atlas_nk_lesson_scope,
        listOf(
            R.string.health_atlas_process_natural_killer_cell_0 to R.string.health_atlas_cell_play_nk_0_caption,
            R.string.health_atlas_process_natural_killer_cell_1 to R.string.health_atlas_cell_play_nk_1_caption,
            R.string.health_atlas_process_natural_killer_cell_2 to R.string.health_atlas_cell_play_nk_2_caption,
            R.string.health_atlas_process_natural_killer_cell_3 to R.string.health_atlas_cell_play_nk_3_caption,
        ),
        listOf(R.string.health_atlas_reference_openstax to
            "https://openstax.org/books/anatomy-and-physiology-2e/pages/21-2-barrier-defenses-and-the-innate-immune-response"),
        16_000L,
        showStructurePreview = true,
    ),
    PLATELET_FORMATION(
        setOf("cell-megakaryocyte"),
        R.string.health_atlas_process_cell_megakaryocyte_title, R.string.health_atlas_mega_lesson_scope,
        listOf(
            R.string.health_atlas_process_cell_megakaryocyte_0 to R.string.health_atlas_cell_play_megakaryocyte_0_caption,
            R.string.health_atlas_process_cell_megakaryocyte_1 to R.string.health_atlas_cell_play_megakaryocyte_1_caption,
            R.string.health_atlas_process_cell_megakaryocyte_2 to R.string.health_atlas_cell_play_megakaryocyte_2_caption,
            R.string.health_atlas_process_cell_megakaryocyte_3 to R.string.health_atlas_cell_play_megakaryocyte_3_caption,
        ),
        listOf(R.string.health_atlas_reference_openstax to
            "https://openstax.org/books/anatomy-and-physiology-2e/pages/18-4-leukocytes-and-platelets"),
        16_000L,
        showStructurePreview = true,
    ),
    CEREBELLAR_COORDINATION(
        setOf("cerebellum"),
        R.string.health_atlas_cerebellum_story_title,
        R.string.health_atlas_cerebellum_story_scope,
        listOf(
            R.string.health_atlas_cerebellum_story_plan to R.string.health_atlas_cerebellum_story_plan_caption,
            R.string.health_atlas_cerebellum_story_feedback to R.string.health_atlas_cerebellum_story_feedback_caption,
            R.string.health_atlas_cerebellum_story_compare to R.string.health_atlas_cerebellum_story_compare_caption,
            R.string.health_atlas_cerebellum_story_correct to R.string.health_atlas_cerebellum_story_correct_caption,
            R.string.health_atlas_cerebellum_story_recalibrate to R.string.health_atlas_cerebellum_story_recalibrate_caption,
        ),
        listOf(
            R.string.health_atlas_cerebellum_story_ref_estimation to "https://journals.plos.org/plosbiology/article?id=10.1371/journal.pbio.0050316",
            R.string.health_atlas_cerebellum_story_ref_adaptation to "https://pubmed.ncbi.nlm.nih.gov/17507504/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    MELANIN_TRANSFER(
        setOf("cell-melanocyte"),
        R.string.health_atlas_melanin_story_title,
        R.string.health_atlas_melanin_story_scope,
        listOf(
            R.string.health_atlas_melanin_story_neighborhood to
                R.string.health_atlas_melanin_story_neighborhood_caption,
            R.string.health_atlas_melanin_story_packaging to
                R.string.health_atlas_melanin_story_packaging_caption,
            R.string.health_atlas_melanin_story_transport to
                R.string.health_atlas_melanin_story_transport_caption,
            R.string.health_atlas_melanin_story_transfer to
                R.string.health_atlas_melanin_story_transfer_caption,
            R.string.health_atlas_melanin_story_shielding to
                R.string.health_atlas_melanin_story_shielding_caption,
        ),
        listOf(
            R.string.health_atlas_melanin_story_reference_transfer to "https://pubmed.ncbi.nlm.nih.gov/24141907/",
            R.string.health_atlas_melanin_story_reference_uv to "https://pubmed.ncbi.nlm.nih.gov/9579550/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    LARYNGEAL_VOICE(
        setOf("larynx"),
        R.string.health_atlas_larynx_story_title,
        R.string.health_atlas_larynx_story_scope,
        listOf(
            R.string.health_atlas_larynx_story_breathe to
                R.string.health_atlas_larynx_story_breathe_caption,
            R.string.health_atlas_larynx_story_approach to
                R.string.health_atlas_larynx_story_approach_caption,
            R.string.health_atlas_larynx_story_air to
                R.string.health_atlas_larynx_story_air_caption,
            R.string.health_atlas_larynx_story_pulse to
                R.string.health_atlas_larynx_story_pulse_caption,
            R.string.health_atlas_larynx_story_reopen to
                R.string.health_atlas_larynx_story_reopen_caption,
        ),
        listOf(
            R.string.health_atlas_larynx_story_ref_breathing to "https://pubmed.ncbi.nlm.nih.gov/6863086/",
            R.string.health_atlas_larynx_story_ref_phonation to "https://pmc.ncbi.nlm.nih.gov/articles/PMC11048587/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    ASTROCYTE_SUPPORT(
        setOf("cell-astrocyte"),
        R.string.health_atlas_astrocyte_story_title,
        R.string.health_atlas_astrocyte_story_scope,
        listOf(
            R.string.health_atlas_astrocyte_story_signal to
                R.string.health_atlas_astrocyte_story_signal_caption,
            R.string.health_atlas_astrocyte_story_capture to
                R.string.health_atlas_astrocyte_story_capture_caption,
            R.string.health_atlas_astrocyte_story_convert to
                R.string.health_atlas_astrocyte_story_convert_caption,
            R.string.health_atlas_astrocyte_story_recycle to
                R.string.health_atlas_astrocyte_story_recycle_caption,
            R.string.health_atlas_astrocyte_story_balance to
                R.string.health_atlas_astrocyte_story_balance_caption,
        ),
        listOf(
            R.string.health_atlas_astrocyte_story_ref_cycle to "https://pubmed.ncbi.nlm.nih.gov/11880482/",
            R.string.health_atlas_astrocyte_story_ref_buffer to "https://pubmed.ncbi.nlm.nih.gov/17942730/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    SPLENIC_FILTER(
        setOf("spleen"),
        R.string.health_atlas_splenic_filter_story_title,
        R.string.health_atlas_splenic_filter_story_scope,
        listOf(
            R.string.health_atlas_splenic_filter_story_locate to
                R.string.health_atlas_splenic_filter_story_locate_caption,
            R.string.health_atlas_splenic_filter_story_squeeze to
                R.string.health_atlas_splenic_filter_story_squeeze_caption,
            R.string.health_atlas_splenic_filter_story_retain to
                R.string.health_atlas_splenic_filter_story_retain_caption,
            R.string.health_atlas_splenic_filter_story_engulf to
                R.string.health_atlas_splenic_filter_story_engulf_caption,
            R.string.health_atlas_splenic_filter_story_recycle to
                R.string.health_atlas_splenic_filter_story_recycle_caption,
        ),
        listOf(
            R.string.health_atlas_splenic_filter_story_ref_filtration to "https://pmc.ncbi.nlm.nih.gov/articles/PMC6199658/",
            R.string.health_atlas_splenic_filter_story_ref_recycling to "https://pmc.ncbi.nlm.nih.gov/articles/PMC2756102/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    MACROPHAGE_CLEARANCE(
        setOf("cell-macrophage"),
        R.string.health_atlas_process_macrophage_title, R.string.health_atlas_phagocytosis_scope,
        listOf(
            R.string.health_atlas_process_macrophage_0 to R.string.health_atlas_cell_play_macrophage_0_caption,
            R.string.health_atlas_process_macrophage_1 to R.string.health_atlas_cell_play_macrophage_1_caption,
            R.string.health_atlas_process_macrophage_2 to R.string.health_atlas_cell_play_macrophage_2_caption,
            R.string.health_atlas_process_macrophage_3 to R.string.health_atlas_cell_play_macrophage_3_caption,
        ),
        listOf(R.string.health_atlas_reference_openstax to
            "https://openstax.org/books/anatomy-and-physiology-2e/pages/18-4-leukocytes-and-platelets"),
        16_000L,
        showStructurePreview = true,
    ),
    THYMIC_SELECTION(
        setOf("thymus"),
        R.string.health_atlas_thymus_story_title,
        R.string.health_atlas_thymus_story_scope,
        listOf(
            R.string.health_atlas_thymus_story_enter to R.string.health_atlas_thymus_story_enter_caption,
            R.string.health_atlas_thymus_story_positive_selection to R.string.health_atlas_thymus_story_positive_selection_caption,
            R.string.health_atlas_thymus_story_to_medulla to R.string.health_atlas_thymus_story_to_medulla_caption,
            R.string.health_atlas_thymus_story_negative_selection to R.string.health_atlas_thymus_story_negative_selection_caption,
            R.string.health_atlas_thymus_story_exit to R.string.health_atlas_thymus_story_exit_caption,
        ),
        listOf(
            R.string.health_atlas_thymus_story_ref_spatial to "https://pmc.ncbi.nlm.nih.gov/articles/PMC11578893/",
            R.string.health_atlas_thymus_story_ref_emigration to "https://pmc.ncbi.nlm.nih.gov/articles/PMC5367636/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    BRAINSTEM_RHYTHM(
        setOf("brainstem"),
        R.string.health_atlas_brainstem_story_title,
        R.string.health_atlas_brainstem_story_scope,
        listOf(
            R.string.health_atlas_brainstem_story_locate to R.string.health_atlas_brainstem_story_locate_caption,
            R.string.health_atlas_brainstem_story_rhythm to R.string.health_atlas_brainstem_story_rhythm_caption,
            R.string.health_atlas_brainstem_story_relay to R.string.health_atlas_brainstem_story_relay_caption,
            R.string.health_atlas_brainstem_story_inhale to R.string.health_atlas_brainstem_story_inhale_caption,
            R.string.health_atlas_brainstem_story_exhale to R.string.health_atlas_brainstem_story_exhale_caption,
        ),
        listOf(
            R.string.health_atlas_brainstem_story_ref_rhythm to "https://pmc.ncbi.nlm.nih.gov/articles/PMC3209964/",
            R.string.health_atlas_brainstem_story_ref_diaphragm to "https://pmc.ncbi.nlm.nih.gov/articles/PMC9785439/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    FIBROBLAST_MATRIX(
        setOf("cell-fibroblast", "dermis"),
        R.string.health_atlas_fibroblast_story_title,
        R.string.health_atlas_fibroblast_story_scope,
        listOf(
            R.string.health_atlas_fibroblast_story_scaffold to R.string.health_atlas_fibroblast_story_scaffold_caption,
            R.string.health_atlas_fibroblast_story_repair to R.string.health_atlas_fibroblast_story_repair_caption,
            R.string.health_atlas_fibroblast_story_deposit to R.string.health_atlas_fibroblast_story_deposit_caption,
            R.string.health_atlas_fibroblast_story_arrange to R.string.health_atlas_fibroblast_story_arrange_caption,
            R.string.health_atlas_fibroblast_story_support to R.string.health_atlas_fibroblast_story_support_caption,
        ),
        listOf(
            R.string.health_atlas_fibroblast_story_ref_deposition to "https://pmc.ncbi.nlm.nih.gov/articles/PMC7655599/",
            R.string.health_atlas_fibroblast_story_ref_structure to "https://pmc.ncbi.nlm.nih.gov/articles/PMC11101527/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    ARTERIAL_PULSE(
        setOf("arteries", "blood-vessels"),
        R.string.health_atlas_arterial_title,
        R.string.health_atlas_arterial_scope,
        listOf(
            R.string.health_atlas_arterial_locate to R.string.health_atlas_arterial_locate_caption,
            R.string.health_atlas_arterial_ejection to R.string.health_atlas_arterial_ejection_caption,
            R.string.health_atlas_arterial_wave_front to R.string.health_atlas_arterial_wave_front_caption,
            R.string.health_atlas_arterial_recoil to R.string.health_atlas_arterial_recoil_caption,
            R.string.health_atlas_arterial_smooth to R.string.health_atlas_arterial_smooth_caption,
        ),
        listOf(
            R.string.health_atlas_arterial_ref_distension to "https://pubmed.ncbi.nlm.nih.gov/27310400/",
            R.string.health_atlas_arterial_ref_wave to "https://doi.org/10.1097/HJH.0000000000001886",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    CHONDROCYTE_MATRIX(
        setOf("cell-chondrocyte"),
        R.string.health_atlas_chondrocyte_story_title,
        R.string.health_atlas_chondrocyte_story_scope,
        listOf(
            R.string.health_atlas_chondrocyte_story_locate to R.string.health_atlas_chondrocyte_story_locate_caption,
            R.string.health_atlas_chondrocyte_story_collagen to R.string.health_atlas_chondrocyte_story_collagen_caption,
            R.string.health_atlas_chondrocyte_story_aggrecan to R.string.health_atlas_chondrocyte_story_aggrecan_caption,
            R.string.health_atlas_chondrocyte_story_hydration to R.string.health_atlas_chondrocyte_story_hydration_caption,
            R.string.health_atlas_chondrocyte_story_recovery to R.string.health_atlas_chondrocyte_story_recovery_caption,
        ),
        listOf(
            R.string.health_atlas_chondrocyte_story_ref_aggrecan to "https://pubmed.ncbi.nlm.nih.gov/9862227/",
            R.string.health_atlas_chondrocyte_story_ref_swelling to "https://pmc.ncbi.nlm.nih.gov/articles/PMC3175069/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    ADRENAL_MEDULLA_SIGNAL(
        setOf("cell-chromaffin-cell", "adrenal-glands"),
        R.string.health_atlas_adrenal_medulla_story_title,
        R.string.health_atlas_adrenal_medulla_story_scope,
        listOf(
            R.string.health_atlas_adrenal_medulla_story_locate to R.string.health_atlas_adrenal_medulla_story_locate_caption,
            R.string.health_atlas_adrenal_medulla_story_signal to R.string.health_atlas_adrenal_medulla_story_signal_caption,
            R.string.health_atlas_adrenal_medulla_story_release to R.string.health_atlas_adrenal_medulla_story_release_caption,
            R.string.health_atlas_adrenal_medulla_story_circulate to R.string.health_atlas_adrenal_medulla_story_circulate_caption,
            R.string.health_atlas_adrenal_medulla_story_settle to R.string.health_atlas_adrenal_medulla_story_settle_caption,
        ),
        listOf(
            R.string.health_atlas_adrenal_medulla_story_ref_exocytosis to "https://pubmed.ncbi.nlm.nih.gov/16723417/",
            R.string.health_atlas_adrenal_medulla_story_ref_recovery to "https://pubmed.ncbi.nlm.nih.gov/6895925/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    GASTRIC_ACID_SECRETION(
        setOf("cell-gastric-parietal-cell"),
        R.string.health_atlas_gastric_acid_story_title,
        R.string.health_atlas_gastric_acid_story_scope,
        listOf(
            R.string.health_atlas_gastric_acid_story_locate to R.string.health_atlas_gastric_acid_story_locate_caption,
            R.string.health_atlas_gastric_acid_story_signal to R.string.health_atlas_gastric_acid_story_signal_caption,
            R.string.health_atlas_gastric_acid_story_exchange to R.string.health_atlas_gastric_acid_story_exchange_caption,
            R.string.health_atlas_gastric_acid_story_secrete to R.string.health_atlas_gastric_acid_story_secrete_caption,
            R.string.health_atlas_gastric_acid_story_feedback to R.string.health_atlas_gastric_acid_story_feedback_caption,
        ),
        listOf(
            R.string.health_atlas_gastric_acid_story_ref_canaliculus to "https://pubmed.ncbi.nlm.nih.gov/8382956/",
            R.string.health_atlas_gastric_acid_story_ref_feedback to "https://pubmed.ncbi.nlm.nih.gov/7481540/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    MARROW_HEMATOPOIESIS(
        setOf("bone-marrow", "cell-hematopoietic-stem-cell"),
        R.string.health_atlas_marrow_story_title,
        R.string.health_atlas_marrow_story_scope,
        listOf(
            R.string.health_atlas_marrow_story_niche to R.string.health_atlas_marrow_story_niche_caption,
            R.string.health_atlas_marrow_story_renewal to R.string.health_atlas_marrow_story_renewal_caption,
            R.string.health_atlas_marrow_story_commitment to R.string.health_atlas_marrow_story_commitment_caption,
            R.string.health_atlas_marrow_story_maturation to R.string.health_atlas_marrow_story_maturation_caption,
            R.string.health_atlas_marrow_story_release to R.string.health_atlas_marrow_story_release_caption,
        ),
        listOf(
            R.string.health_atlas_marrow_story_ref_lineages to "https://pubmed.ncbi.nlm.nih.gov/26541609/",
            R.string.health_atlas_marrow_story_ref_egress to "https://www.jstage.jst.go.jp/article/jvms/64/10/64_10_913/_article",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    CORONARY_PERFUSION(
        setOf("coronary-vessels"),
        R.string.health_atlas_coronary_story_title,
        R.string.health_atlas_coronary_story_scope,
        listOf(
            R.string.health_atlas_coronary_story_ostia to R.string.health_atlas_coronary_story_ostia_caption,
            R.string.health_atlas_coronary_story_branch to R.string.health_atlas_coronary_story_branch_caption,
            R.string.health_atlas_coronary_story_systole to R.string.health_atlas_coronary_story_systole_caption,
            R.string.health_atlas_coronary_story_diastole to R.string.health_atlas_coronary_story_diastole_caption,
            R.string.health_atlas_coronary_story_return to R.string.health_atlas_coronary_story_return_caption,
        ),
        listOf(
            R.string.health_atlas_coronary_story_ref_ostia to "https://pmc.ncbi.nlm.nih.gov/articles/PMC6172585/",
            R.string.health_atlas_coronary_story_ref_flow to "https://pubmed.ncbi.nlm.nih.gov/7261259/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    PODOCYTE_BARRIER(
        setOf("cell-podocyte"),
        R.string.health_atlas_podocyte_story_title,
        R.string.health_atlas_podocyte_story_scope,
        HealthAtlasPodocyteStage.entries.map { it.title to it.caption },
        listOf(
            R.string.health_atlas_podocyte_story_ref_structure to HealthAtlasPodocyteStoryView.STRUCTURE_SOURCE,
            R.string.health_atlas_podocyte_story_ref_albumin to HealthAtlasPodocyteStoryView.ALBUMIN_SOURCE,
        ),
        HealthAtlasPodocyteStoryView.DURATION_MS,
        showStructurePreview = true,
    ),
    ENDOMETRIUM_RENEWAL(
        setOf("endometrium", "cell-endometrial-epithelial-cell", "cell-endometrial-stromal-cell"),
        R.string.health_atlas_endometrium_story_title,
        R.string.health_atlas_endometrium_story_scope,
        listOf(
            R.string.health_atlas_endometrium_story_layers to R.string.health_atlas_endometrium_story_layers_caption,
            R.string.health_atlas_endometrium_story_growth to R.string.health_atlas_endometrium_story_growth_caption,
            R.string.health_atlas_endometrium_story_secretion to R.string.health_atlas_endometrium_story_secretion_caption,
            R.string.health_atlas_endometrium_story_shedding to R.string.health_atlas_endometrium_story_shedding_caption,
            R.string.health_atlas_endometrium_story_repair to R.string.health_atlas_endometrium_story_repair_caption,
        ),
        listOf(
            R.string.health_atlas_endometrium_story_ref_cycle to "https://pmc.ncbi.nlm.nih.gov/articles/PMC8648563/",
            R.string.health_atlas_endometrium_story_ref_repair to "https://pubmed.ncbi.nlm.nih.gov/1244749/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    CRANIAL_REFLEX(
        setOf("cranial-nerves"),
        R.string.health_atlas_cranial_reflex_story_title,
        R.string.health_atlas_cranial_reflex_story_scope,
        listOf(
            R.string.health_atlas_cranial_reflex_story_light to R.string.health_atlas_cranial_reflex_story_light_caption,
            R.string.health_atlas_cranial_reflex_story_input to R.string.health_atlas_cranial_reflex_story_input_caption,
            R.string.health_atlas_cranial_reflex_story_relay to R.string.health_atlas_cranial_reflex_story_relay_caption,
            R.string.health_atlas_cranial_reflex_story_output to R.string.health_atlas_cranial_reflex_story_output_caption,
            R.string.health_atlas_cranial_reflex_story_response to R.string.health_atlas_cranial_reflex_story_response_caption,
        ),
        listOf(
            R.string.health_atlas_cranial_reflex_story_ref_circuit to "https://pmc.ncbi.nlm.nih.gov/articles/PMC6957570/",
            R.string.health_atlas_cranial_reflex_story_ref_responses to "https://pubmed.ncbi.nlm.nih.gov/465430/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    SEBUM_RELEASE(
        setOf("sebaceous-glands", "cell-sebocyte"),
        R.string.health_atlas_sebaceous_title,
        R.string.health_atlas_sebaceous_scope,
        listOf(
            R.string.health_atlas_sebaceous_locate to R.string.health_atlas_sebaceous_locate_caption,
            R.string.health_atlas_sebaceous_renew to R.string.health_atlas_sebaceous_renew_caption,
            R.string.health_atlas_sebaceous_store to R.string.health_atlas_sebaceous_store_caption,
            R.string.health_atlas_sebaceous_release to R.string.health_atlas_sebaceous_release_caption,
            R.string.health_atlas_sebaceous_surface_flow to R.string.health_atlas_sebaceous_surface_flow_caption,
        ),
        listOf(
            R.string.health_atlas_sebaceous_ref_histology to "https://pubmed.ncbi.nlm.nih.gov/38542083/",
            R.string.health_atlas_sebaceous_ref_maturation to "https://pubmed.ncbi.nlm.nih.gov/8000703/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    CEREBRAL_SENSORIMOTOR(
        setOf("cerebrum"),
        R.string.health_atlas_cerebral_sensorimotor_story_title,
        R.string.health_atlas_cerebral_sensorimotor_story_scope,
        listOf(
            R.string.health_atlas_cerebral_sensorimotor_story_locate to R.string.health_atlas_cerebral_sensorimotor_story_locate_caption,
            R.string.health_atlas_cerebral_sensorimotor_story_register to R.string.health_atlas_cerebral_sensorimotor_story_register_caption,
            R.string.health_atlas_cerebral_sensorimotor_story_integrate to R.string.health_atlas_cerebral_sensorimotor_story_integrate_caption,
            R.string.health_atlas_cerebral_sensorimotor_story_command to R.string.health_atlas_cerebral_sensorimotor_story_command_caption,
            R.string.health_atlas_cerebral_sensorimotor_story_feedback to R.string.health_atlas_cerebral_sensorimotor_story_feedback_caption,
        ),
        listOf(
            R.string.health_atlas_cerebral_sensorimotor_story_ref_planning to "https://pubmed.ncbi.nlm.nih.gov/20660416/",
            R.string.health_atlas_cerebral_sensorimotor_story_ref_feedback to "https://pubmed.ncbi.nlm.nih.gov/21964335/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    AUTONOMIC_RELAY(
        setOf("autonomic-nerves"),
        R.string.health_atlas_autonomic_relay_story_title,
        R.string.health_atlas_autonomic_relay_story_scope,
        listOf(
            R.string.health_atlas_autonomic_relay_story_output to R.string.health_atlas_autonomic_relay_story_output_caption,
            R.string.health_atlas_autonomic_relay_story_sympathetic to R.string.health_atlas_autonomic_relay_story_sympathetic_caption,
            R.string.health_atlas_autonomic_relay_story_target to R.string.health_atlas_autonomic_relay_story_target_caption,
            R.string.health_atlas_autonomic_relay_story_vagal to R.string.health_atlas_autonomic_relay_story_vagal_caption,
            R.string.health_atlas_autonomic_relay_story_compare to R.string.health_atlas_autonomic_relay_story_compare_caption,
        ),
        listOf(
            R.string.health_atlas_autonomic_relay_story_ref_anatomy to "https://pubmed.ncbi.nlm.nih.gov/15887046/",
            R.string.health_atlas_autonomic_relay_story_ref_rate to "https://pubmed.ncbi.nlm.nih.gov/5914852/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    GASTRIC_CHIEF_SECRETION(
        setOf("cell-gastric-chief-cell"),
        R.string.health_atlas_gastric_chief_story_title,
        R.string.health_atlas_gastric_chief_story_scope,
        listOf(
            R.string.health_atlas_gastric_chief_story_locate to R.string.health_atlas_gastric_chief_story_locate_caption,
            R.string.health_atlas_gastric_chief_story_pack to R.string.health_atlas_gastric_chief_story_pack_caption,
            R.string.health_atlas_gastric_chief_story_release to R.string.health_atlas_gastric_chief_story_release_caption,
            R.string.health_atlas_gastric_chief_story_activate to R.string.health_atlas_gastric_chief_story_activate_caption,
            R.string.health_atlas_gastric_chief_story_digest to R.string.health_atlas_gastric_chief_story_digest_caption,
        ),
        listOf(
            R.string.health_atlas_gastric_chief_story_ref_fundic_cells to "https://pmc.ncbi.nlm.nih.gov/articles/PMC477213/",
            R.string.health_atlas_gastric_chief_story_ref_activation to "https://pubmed.ncbi.nlm.nih.gov/2500427/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    TONSILLAR_SAMPLING(
        setOf("tonsils", "adenoids"),
        R.string.health_atlas_tonsil_story_title,
        R.string.health_atlas_tonsil_story_scope,
        listOf(
            R.string.health_atlas_tonsil_story_locate to R.string.health_atlas_tonsil_story_locate_caption,
            R.string.health_atlas_tonsil_story_compare to R.string.health_atlas_tonsil_story_compare_caption,
            R.string.health_atlas_tonsil_story_encounter to R.string.health_atlas_tonsil_story_encounter_caption,
            R.string.health_atlas_tonsil_story_sample to R.string.health_atlas_tonsil_story_sample_caption,
            R.string.health_atlas_tonsil_story_present to R.string.health_atlas_tonsil_story_present_caption,
        ),
        listOf(
            R.string.health_atlas_tonsil_story_ref_palatine to "https://pubmed.ncbi.nlm.nih.gov/37202490/",
            R.string.health_atlas_tonsil_story_ref_adenoid to "https://pubmed.ncbi.nlm.nih.gov/10917169/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    ACINAR_ENZYME_SECRETION(
        setOf("cell-pancreatic-acinar-cell"),
        R.string.health_atlas_acinar_enzyme_story_title,
        R.string.health_atlas_acinar_enzyme_story_scope,
        listOf(
            R.string.health_atlas_acinar_enzyme_story_locate to R.string.health_atlas_acinar_enzyme_story_locate_caption,
            R.string.health_atlas_acinar_enzyme_story_package to R.string.health_atlas_acinar_enzyme_story_package_caption,
            R.string.health_atlas_acinar_enzyme_story_release to R.string.health_atlas_acinar_enzyme_story_release_caption,
            R.string.health_atlas_acinar_enzyme_story_duct to R.string.health_atlas_acinar_enzyme_story_duct_caption,
            R.string.health_atlas_acinar_enzyme_story_arrive to R.string.health_atlas_acinar_enzyme_story_arrive_caption,
        ),
        listOf(
            R.string.health_atlas_acinar_enzyme_story_ref_acinar to "https://pmc.ncbi.nlm.nih.gov/articles/PMC2106415/",
            R.string.health_atlas_acinar_enzyme_story_ref_duct to "https://pubmed.ncbi.nlm.nih.gov/8866361/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    NAIL_MATRIX_GROWTH(
        setOf("nails"),
        R.string.health_atlas_nail_story_title,
        R.string.health_atlas_nail_story_scope,
        listOf(
            R.string.health_atlas_nail_story_section to R.string.health_atlas_nail_story_section_caption,
            R.string.health_atlas_nail_story_division to R.string.health_atlas_nail_story_division_caption,
            R.string.health_atlas_nail_story_maturation to R.string.health_atlas_nail_story_maturation_caption,
            R.string.health_atlas_nail_story_advance to R.string.health_atlas_nail_story_advance_caption,
            R.string.health_atlas_nail_story_edge to R.string.health_atlas_nail_story_edge_caption,
        ),
        listOf(
            R.string.health_atlas_nail_story_ref_matrix to "https://pubmed.ncbi.nlm.nih.gov/15327543/",
            R.string.health_atlas_nail_story_ref_anatomy to "https://doi.org/10.1002/ar.22660",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    SINUS_DRAINAGE(
        setOf("paranasal-sinuses"),
        R.string.health_atlas_sinus_drainage_title,
        R.string.health_atlas_sinus_drainage_scope,
        listOf(
            R.string.health_atlas_sinus_drainage_locate to R.string.health_atlas_sinus_drainage_locate_caption,
            R.string.health_atlas_sinus_drainage_zoom to R.string.health_atlas_sinus_drainage_zoom_caption,
            R.string.health_atlas_sinus_drainage_secrete to R.string.health_atlas_sinus_drainage_secrete_caption,
            R.string.health_atlas_sinus_drainage_sweep to R.string.health_atlas_sinus_drainage_sweep_caption,
            R.string.health_atlas_sinus_drainage_enter to R.string.health_atlas_sinus_drainage_enter_caption,
        ),
        listOf(
            R.string.health_atlas_sinus_drainage_ref_opening to "https://pubmed.ncbi.nlm.nih.gov/22319687/",
            R.string.health_atlas_sinus_drainage_ref_clearance to "https://pubmed.ncbi.nlm.nih.gov/1874632/",
        ),
        20_000L,
        showStructurePreview = true,
    ),
    TOOTH_MASTICATION(
        setOf("teeth"),
        R.string.health_atlas_tooth_mastication_story_title,
        R.string.health_atlas_tooth_mastication_story_scope,
        listOf(
            R.string.health_atlas_tooth_mastication_story_arch to R.string.health_atlas_tooth_mastication_story_arch_caption,
            R.string.health_atlas_tooth_mastication_story_cut to R.string.health_atlas_tooth_mastication_story_cut_caption,
            R.string.health_atlas_tooth_mastication_story_tear to R.string.health_atlas_tooth_mastication_story_tear_caption,
            R.string.health_atlas_tooth_mastication_story_grind to R.string.health_atlas_tooth_mastication_story_grind_caption,
            R.string.health_atlas_tooth_mastication_story_bolus to R.string.health_atlas_tooth_mastication_story_bolus_caption,
        ),
        listOf(
            R.string.health_atlas_tooth_mastication_story_ref_motion to "https://pmc.ncbi.nlm.nih.gov/articles/PMC10530480/",
            R.string.health_atlas_tooth_mastication_story_ref_bolus to "https://pubmed.ncbi.nlm.nih.gov/12648556/",
        ),
        20_000L,
        showStructurePreview = true,
    );

    val choiceTitle get() = when (this) {
        GLUCOSE -> R.string.health_atlas_lesson_uptake
        MUSCLE_MOTION -> R.string.health_atlas_lesson_contraction
        DIGESTION -> R.string.health_atlas_lesson_digestion
        LYMPH_RETURN -> R.string.health_atlas_lesson_lymph
        ANTIBODY_RESPONSE -> R.string.health_atlas_lesson_antibodies
        INSULIN_SECRETION -> R.string.health_atlas_lesson_insulin
        GLUCAGON_RESPONSE -> R.string.health_atlas_home_lesson_glucagon
        SYNAPTIC_SIGNAL -> R.string.health_atlas_signal_lesson_neuro
        MYELIN_SIGNAL -> R.string.health_atlas_signal_lesson_myelin
        THYROID_FEEDBACK -> R.string.health_atlas_signal_lesson_thyroid
        SWEAT_COOLING -> R.string.health_atlas_barrier_choice_sweat
        EPIDERMAL_BARRIER -> R.string.health_atlas_barrier_choice
        VISION -> R.string.health_atlas_sense_choice_vision
        HEARING -> R.string.health_atlas_sense_choice_hearing
        VESTIBULAR_BALANCE -> R.string.health_atlas_sense_choice_balance
        OLFACTION -> R.string.health_atlas_sense_choice_smell
        TASTE_SIGNAL -> R.string.health_atlas_sense_choice_taste
        TOUCH_SIGNAL -> R.string.health_atlas_sense_choice_touch
        COLON -> R.string.health_atlas_sense_choice_colon
        LIGHT_ADAPTATION -> R.string.health_atlas_ocular_choice_adaptation
        RPE_VISUAL_CYCLE -> R.string.health_atlas_ocular_choice_pigment
        DIM_LIGHT_RELAY -> R.string.health_atlas_ocular_choice_relay
        CORNEAL_SURFACE_RENEWAL -> R.string.health_atlas_ocular_choice_cornea
        AIRWAY_CLEARANCE -> R.string.health_atlas_airway_choice
        ENDOTHELIAL_EXCHANGE -> R.string.health_atlas_endothelium_choice
        PLATELET_HEMOSTASIS -> R.string.health_atlas_platelet_hemostasis_choice
        TENDON_FORCE_TRANSFER -> R.string.health_atlas_tendon_story_choice
        ALVEOLAR_SURFACTANT -> R.string.health_atlas_surfactant_choice
        INTESTINAL_ABSORPTION -> R.string.health_atlas_absorption_story_choice
        KNEE_ARTICULATION -> R.string.health_atlas_knee_choice
        CARDIAC_EXCITATION -> R.string.health_atlas_cardiac_choice
        RED_CELL_OXYGEN -> R.string.health_atlas_red_cell_story_choice
        SALIVA_SECRETION -> R.string.health_atlas_saliva_story_choice
        VENOUS_RETURN -> R.string.health_atlas_venous_return_story_choice
        PLEURAL_COUPLING -> R.string.health_atlas_pleura_story_choice
        PARATHYROID_FEEDBACK -> R.string.health_atlas_calcium_feedback_story_choice
        CEREBELLAR_COORDINATION -> R.string.health_atlas_cerebellum_story_choice
        MELANIN_TRANSFER -> R.string.health_atlas_melanin_story_choice
        LARYNGEAL_VOICE -> R.string.health_atlas_larynx_story_choice
        ASTROCYTE_SUPPORT -> R.string.health_atlas_astrocyte_story_choice
        SPLENIC_FILTER -> R.string.health_atlas_splenic_filter_story_choice
        THYMIC_SELECTION -> R.string.health_atlas_thymus_story_choice
        BRAINSTEM_RHYTHM -> R.string.health_atlas_brainstem_story_choice
        FIBROBLAST_MATRIX -> R.string.health_atlas_fibroblast_story_choice
        ARTERIAL_PULSE -> R.string.health_atlas_arterial_choice
        CHONDROCYTE_MATRIX -> R.string.health_atlas_chondrocyte_story_choice
        ADRENAL_MEDULLA_SIGNAL -> R.string.health_atlas_adrenal_medulla_story_choice
        GASTRIC_ACID_SECRETION -> R.string.health_atlas_gastric_acid_story_choice
        MARROW_HEMATOPOIESIS -> R.string.health_atlas_marrow_story_choice
        CORONARY_PERFUSION -> R.string.health_atlas_coronary_story_choice
        PODOCYTE_BARRIER -> R.string.health_atlas_podocyte_story_choice
        ENDOMETRIUM_RENEWAL -> R.string.health_atlas_endometrium_story_choice
        CRANIAL_REFLEX -> R.string.health_atlas_cranial_reflex_story_choice
        SEBUM_RELEASE -> R.string.health_atlas_sebaceous_choice
        CEREBRAL_SENSORIMOTOR -> R.string.health_atlas_cerebral_sensorimotor_story_choice
        AUTONOMIC_RELAY -> R.string.health_atlas_autonomic_relay_story_choice
        GASTRIC_CHIEF_SECRETION -> R.string.health_atlas_gastric_chief_story_choice
        TONSILLAR_SAMPLING -> R.string.health_atlas_tonsil_story_choice
        ACINAR_ENZYME_SECRETION -> R.string.health_atlas_acinar_enzyme_story_choice
        NAIL_MATRIX_GROWTH -> R.string.health_atlas_nail_story_choice
        SINUS_DRAINAGE -> R.string.health_atlas_sinus_drainage_choice
        TOOTH_MASTICATION -> R.string.health_atlas_tooth_mastication_story_choice
        else -> title
    }

    val relatedLessons get() = when (this) {
        INSULIN_SECRETION -> listOf("tissue-skeletal-muscle" to GLUCOSE, "cell-pancreatic-alpha-cell" to GLUCAGON_RESPONSE)
        GLUCAGON_RESPONSE -> listOf("cell-pancreatic-beta-cell" to INSULIN_SECRETION)
        GLUCOSE -> listOf("cell-pancreatic-beta-cell" to INSULIN_SECRETION)
        SYNAPTIC_SIGNAL -> listOf("cell-oligodendrocyte" to MYELIN_SIGNAL)
        MYELIN_SIGNAL -> listOf("cell-neuron" to SYNAPTIC_SIGNAL)
        SWEAT_COOLING -> listOf("epidermis" to EPIDERMAL_BARRIER)
        EPIDERMAL_BARRIER -> listOf("sweat-glands" to SWEAT_COOLING, "sebaceous-glands" to SEBUM_RELEASE,
            "nails" to NAIL_MATRIX_GROWTH)
        ANTIBODY_RESPONSE -> listOf("tonsils" to TONSILLAR_SAMPLING)
        DIGESTION -> listOf("cell-pancreatic-acinar-cell" to ACINAR_ENZYME_SECRETION, "teeth" to TOOTH_MASTICATION)
        HAIR_FOLLICLE_CYCLE -> listOf("sebaceous-glands" to SEBUM_RELEASE)
        OVUM_TRANSPORT -> listOf("endometrium" to ENDOMETRIUM_RENEWAL)
        VISION -> listOf("cranial-nerves" to CRANIAL_REFLEX)
        OLFACTION -> listOf("taste-buds" to TASTE_SIGNAL, "paranasal-sinuses" to SINUS_DRAINAGE)
        TASTE_SIGNAL -> listOf("olfactory-mucosa" to OLFACTION)
        TOUCH_SIGNAL -> listOf("epidermis" to EPIDERMAL_BARRIER)
        VESTIBULAR_BALANCE -> listOf("cochlea" to HEARING)
        RPE_VISUAL_CYCLE -> listOf("cell-retinal-aii-amacrine-cell" to DIM_LIGHT_RELAY)
        DIM_LIGHT_RELAY -> listOf("cell-rod-photoreceptor" to LIGHT_ADAPTATION)
        CORNEAL_SURFACE_RENEWAL -> listOf("cornea" to VISION)
        BREATHING -> listOf("tissue-respiratory-epithelium" to AIRWAY_CLEARANCE)
        AIRWAY_CLEARANCE -> listOf("lungs" to BREATHING)
        ENDOTHELIAL_EXCHANGE -> listOf("lymphatic-vessels" to LYMPH_RETURN)
        PLATELET_HEMOSTASIS -> listOf("capillaries" to ENDOTHELIAL_EXCHANGE)
        SMOOTH_MUSCLE_WAVE -> listOf("small-intestine" to DIGESTION)
        TENDON_FORCE_TRANSFER -> listOf("biceps-brachii" to MUSCLE_MOTION)
        ALVEOLAR_SURFACTANT -> listOf("alveoli" to BREATHING)
        INTESTINAL_ABSORPTION -> listOf("lymphatic-vessels" to LYMPH_RETURN)
        KNEE_ARTICULATION -> listOf("patella" to CARTILAGE_LOAD, "tissue-dense-regular-connective" to TENDON_FORCE_TRANSFER)
        CARDIAC_EXCITATION -> listOf("heart" to HEARTBEAT)
        RED_CELL_OXYGEN -> listOf("pulmonary-capillaries" to BREATHING, "bone-marrow" to MARROW_HEMATOPOIESIS)
        SALIVA_SECRETION -> listOf("oral-cavity" to DIGESTION)
        VENOUS_RETURN -> listOf("heart" to HEARTBEAT)
        NEPHRON -> listOf("renal-pelvis" to URINE_ROUTE, "cell-podocyte" to PODOCYTE_BARRIER)
        URINE_ROUTE -> listOf("nephron" to NEPHRON)
        PLEURAL_COUPLING -> listOf("lungs" to BREATHING)
        PARATHYROID_FEEDBACK -> listOf("renal-cortex" to NEPHRON, "small-intestine" to INTESTINAL_ABSORPTION)
        THYROID_FEEDBACK -> listOf("parathyroid-glands" to PARATHYROID_FEEDBACK)
        DENDRITIC_PRESENTATION -> listOf("cell-t-cell" to T_CELL_RESPONSE)
        T_CELL_RESPONSE -> listOf("cell-dendritic-cell" to DENDRITIC_PRESENTATION, "thymus" to THYMIC_SELECTION)
        PLATELET_FORMATION -> listOf("fragment-platelet" to PLATELET_HEMOSTASIS)
        CEREBELLAR_COORDINATION -> listOf("brain" to SYNAPTIC_SIGNAL, "cerebrum" to CEREBRAL_SENSORIMOTOR)
        MELANIN_TRANSFER -> listOf("epidermis" to EPIDERMAL_BARRIER)
        LARYNGEAL_VOICE -> listOf("trachea" to BREATHING)
        ASTROCYTE_SUPPORT -> listOf("cell-neuron" to SYNAPTIC_SIGNAL)
        SPLENIC_FILTER -> listOf("cell-erythrocyte" to RED_CELL_OXYGEN, "cell-macrophage" to MACROPHAGE_CLEARANCE)
        MONOCYTE_RECRUITMENT -> listOf("cell-macrophage" to MACROPHAGE_CLEARANCE)
        THYMIC_SELECTION -> listOf("cell-t-cell" to T_CELL_RESPONSE)
        BRAINSTEM_RHYTHM -> listOf("diaphragm" to BREATHING)
        FIBROBLAST_MATRIX -> listOf("skin-organ" to EPIDERMAL_BARRIER)
        ARTERIAL_PULSE -> listOf("aorta" to HEARTBEAT, "capillaries" to ENDOTHELIAL_EXCHANGE, "veins" to VENOUS_RETURN)
        HEARTBEAT -> listOf("coronary-vessels" to CORONARY_PERFUSION, "autonomic-nerves" to AUTONOMIC_RELAY)
        CORONARY_PERFUSION -> listOf("heart" to HEARTBEAT)
        PODOCYTE_BARRIER -> listOf("glomerulus" to NEPHRON)
        ENDOMETRIUM_RENEWAL -> listOf("ovaries" to OVUM_TRANSPORT)
        CRANIAL_REFLEX -> listOf("eye" to VISION)
        SEBUM_RELEASE -> listOf("hair-follicles" to HAIR_FOLLICLE_CYCLE, "epidermis" to EPIDERMAL_BARRIER)
        CEREBRAL_SENSORIMOTOR -> listOf("cell-neuron" to SYNAPTIC_SIGNAL, "cerebellum" to CEREBELLAR_COORDINATION)
        AUTONOMIC_RELAY -> listOf("heart" to HEARTBEAT)
        GASTRIC_CHIEF_SECRETION -> listOf("stomach" to DIGESTION, "cell-gastric-parietal-cell" to GASTRIC_ACID_SECRETION)
        TONSILLAR_SAMPLING -> listOf("immune" to ANTIBODY_RESPONSE)
        ACINAR_ENZYME_SECRETION -> listOf("pancreas" to DIGESTION)
        NAIL_MATRIX_GROWTH -> listOf("epidermis" to EPIDERMAL_BARRIER)
        SINUS_DRAINAGE -> listOf("nasal-cavity" to OLFACTION)
        TOOTH_MASTICATION -> listOf("oral-cavity" to DIGESTION)
        CHONDROCYTE_MATRIX -> listOf("tissue-hyaline-cartilage" to CARTILAGE_LOAD)
        ADRENAL_MEDULLA_SIGNAL -> listOf("cell-neuron" to SYNAPTIC_SIGNAL)
        GASTRIC_ACID_SECRETION -> listOf("stomach" to DIGESTION, "cell-gastric-chief-cell" to GASTRIC_CHIEF_SECRETION)
        MARROW_HEMATOPOIESIS -> listOf("cell-erythrocyte" to RED_CELL_OXYGEN)
        CARTILAGE_LOAD -> listOf("cell-chondrocyte" to CHONDROCYTE_MATRIX)
        else -> emptyList()
    }

    fun chapter(value: Float) = (safePhase(value) * chapters.size).toInt().coerceAtMost(chapters.lastIndex)
    fun fraction(value: Float) = (safePhase(value) * chapters.size - chapter(value)).coerceIn(0f, 1f)
    fun startOf(chapter: Int) = chapter.coerceIn(chapters.indices) / chapters.size.toFloat()

    fun entryPhase(id: String): Float = startOf(when (this) {
        HEARTBEAT -> if (id == "aorta" || id == "pulmonary-trunk") HealthAtlasBeatStage.EJECTION.ordinal else 0
        BREATHING -> if (id == "cell-type-i-pneumocyte") HealthAtlasBreathingStage.DIFFUSE.ordinal else 0
        SALIVA_SECRETION -> if (id == "cell-salivary-acinar-cell") 1 else 0
        NEPHRON -> when (id) {
            "cell-proximal-tubular-cell" -> HealthAtlasNephronStage.PROXIMAL.ordinal
            "renal-medulla" -> HealthAtlasNephronStage.LOOP.ordinal
            "cell-collecting-duct-principal-cell" -> HealthAtlasNephronStage.COLLECT.ordinal
            else -> 0
        }
        URINE_ROUTE -> when (id) {
            "ureters" -> 1
            "bladder" -> 3
            "urethra" -> 4
            else -> 0
        }
        MAMMARY_MILK_FLOW -> when (id) {
            "cell-mammary-luminal-cell" -> 1
            "cell-myoepithelial-cell" -> 3
            else -> 0
        }
        ENDOMETRIUM_RENEWAL -> when (id) {
            "cell-endometrial-epithelial-cell" -> 4
            "cell-endometrial-stromal-cell" -> 1
            else -> 0
        }
        SEBUM_RELEASE -> if (id == "cell-sebocyte") 2 else 0
        TONSILLAR_SAMPLING -> if (id == "adenoids") 1 else 0
        else -> 0
    })

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
        GLUCAGON_RESPONSE, SWEAT_COOLING -> HealthAtlasHomeostasisStoryView(context, this)
        SYNAPTIC_SIGNAL, MYELIN_SIGNAL, THYROID_FEEDBACK -> HealthAtlasSignalStoryView(context, this)
        EPIDERMAL_BARRIER -> HealthAtlasBarrierStoryView(context)
        SPERM_TRANSPORT, OVUM_TRANSPORT -> HealthAtlasGameteStoryView(context, this)
        OLFACTION, TASTE_SIGNAL -> HealthAtlasChemicalSenseStoryView(context, this)
        TOUCH_SIGNAL, VESTIBULAR_BALANCE -> HealthAtlasMotionSenseStoryView(context, this)
        RPE_VISUAL_CYCLE, DIM_LIGHT_RELAY, CORNEAL_SURFACE_RENEWAL -> HealthAtlasOcularStoryView(context, this)
        AIRWAY_CLEARANCE -> HealthAtlasAirwayStoryView(context)
        ENDOTHELIAL_EXCHANGE -> HealthAtlasEndothelialStoryView(context)
        PLATELET_HEMOSTASIS -> HealthAtlasPlateletStoryView(context)
        CARTILAGE_LOAD -> HealthAtlasCartilageStoryView(context)
        SMOOTH_MUSCLE_WAVE -> HealthAtlasSmoothMuscleStoryView(context)
        TENDON_FORCE_TRANSFER -> HealthAtlasTendonStoryView(context)
        ALVEOLAR_SURFACTANT -> HealthAtlasSurfactantStoryView(context)
        INTESTINAL_ABSORPTION -> HealthAtlasIntestinalAbsorptionStoryView(context)
        KNEE_ARTICULATION -> HealthAtlasKneeStoryView(context)
        CARDIAC_EXCITATION -> HealthAtlasCardiacSignalStoryView(context)
        RED_CELL_OXYGEN -> HealthAtlasRedCellStoryView(context)
        SALIVA_SECRETION -> HealthAtlasSalivaStoryView(context)
        VENOUS_RETURN -> HealthAtlasVenousReturnStoryView(context)
        HAIR_FOLLICLE_CYCLE -> HealthAtlasHairCycleStoryView(context)
        URINE_ROUTE -> HealthAtlasUrineRouteStoryView(context)
        PLEURAL_COUPLING -> HealthAtlasPleuraStoryView(context)
        PARATHYROID_FEEDBACK -> HealthAtlasCalciumFeedbackStoryView(context)
        MAMMARY_MILK_FLOW -> HealthAtlasMammaryStoryView(context)
        CEREBELLAR_COORDINATION -> HealthAtlasCerebellumStoryView(context)
        MELANIN_TRANSFER -> HealthAtlasMelaninStoryView(context)
        LARYNGEAL_VOICE -> HealthAtlasLarynxStoryView(context)
        ASTROCYTE_SUPPORT -> HealthAtlasAstrocyteStoryView(context)
        SPLENIC_FILTER -> HealthAtlasSplenicFilterStoryView(context)
        THYMIC_SELECTION -> HealthAtlasThymusStoryView(context)
        BRAINSTEM_RHYTHM -> HealthAtlasBrainstemRhythmStoryView(context)
        FIBROBLAST_MATRIX -> HealthAtlasFibroblastStoryView(context)
        ARTERIAL_PULSE -> HealthAtlasArterialStoryView(context)
        CHONDROCYTE_MATRIX -> HealthAtlasChondrocyteStoryView(context)
        ADRENAL_MEDULLA_SIGNAL -> HealthAtlasAdrenalMedullaStoryView(context)
        GASTRIC_ACID_SECRETION -> HealthAtlasGastricAcidStoryView(context)
        MARROW_HEMATOPOIESIS -> HealthAtlasMarrowStoryView(context)
        CORONARY_PERFUSION -> HealthAtlasCoronaryStoryView(context)
        PODOCYTE_BARRIER -> HealthAtlasPodocyteStoryView(context)
        ENDOMETRIUM_RENEWAL -> HealthAtlasEndometriumStoryView(context)
        CRANIAL_REFLEX -> HealthAtlasCranialReflexStoryView(context)
        SEBUM_RELEASE -> HealthAtlasSebaceousStoryView(context)
        CEREBRAL_SENSORIMOTOR -> HealthAtlasCerebralSensorimotorStoryView(context)
        AUTONOMIC_RELAY -> HealthAtlasAutonomicRelayStoryView(context)
        GASTRIC_CHIEF_SECRETION -> HealthAtlasGastricChiefStoryView(context)
        TONSILLAR_SAMPLING -> HealthAtlasTonsilStoryView(context)
        ACINAR_ENZYME_SECRETION -> HealthAtlasAcinarEnzymeStoryView(context)
        NAIL_MATRIX_GROWTH -> HealthAtlasNailStoryView(context)
        SINUS_DRAINAGE -> HealthAtlasSinusDrainageStoryView(context)
        TOOTH_MASTICATION -> HealthAtlasToothMasticationStoryView(context)
        NEUTROPHIL_DEFENSE, EOSINOPHIL_RESPONSE, BASOPHIL_SIGNALING, MONOCYTE_RECRUITMENT,
        DENDRITIC_PRESENTATION, T_CELL_RESPONSE, NK_SURVEILLANCE, PLATELET_FORMATION, MACROPHAGE_CLEARANCE ->
            HealthAtlasCellFunctionArt(context, this, owners.single())
    }

    companion object {
        fun forId(id: String?) = if (id == null) null else entries.firstOrNull { id in it.owners }

        fun choicesForId(id: String?): List<HealthAtlasFunctionStory> {
            val primary = forId(id) ?: return emptyList()
            return when (id) {
                "pancreas" -> listOf(primary, INSULIN_SECRETION, GLUCAGON_RESPONSE)
                "endocrine" -> listOf(primary, GLUCAGON_RESPONSE, THYROID_FEEDBACK)
                "pancreatic-islets" -> listOf(primary, GLUCAGON_RESPONSE)
                "nervous", "brain", "spinal-cord", "cell-neuron" -> listOf(primary, MYELIN_SIGNAL)
                "tissue-central-nervous" -> listOf(primary, MYELIN_SIGNAL, ASTROCYTE_SUPPORT)
                "tissue-skeletal-muscle" -> listOf(primary, MUSCLE_MOTION)
                "cell-skeletal-myocyte" -> listOf(primary, GLUCOSE)
                "immune" -> listOf(primary, LYMPH_RETURN)
                "skin" -> listOf(primary, EPIDERMAL_BARRIER, TOUCH_SIGNAL)
                "skin-organ" -> listOf(primary, TOUCH_SIGNAL)
                "epidermis" -> listOf(primary, TOUCH_SIGNAL, MELANIN_TRANSFER)
                "sensory" -> listOf(primary, HEARING, VESTIBULAR_BALANCE, OLFACTION, TASTE_SIGNAL, TOUCH_SIGNAL)
                "ear", "inner-ear", "cell-inner-ear-hair-cell" -> listOf(primary, VESTIBULAR_BALANCE)
                "tongue" -> listOf(primary, TASTE_SIGNAL)
                "gut" -> listOf(primary, COLON)
                "retina" -> listOf(primary, DIM_LIGHT_RELAY, RPE_VISUAL_CYCLE)
                "cell-rod-photoreceptor" -> listOf(primary, DIM_LIGHT_RELAY, RPE_VISUAL_CYCLE)
                "cell-retinal-bipolar-cell" -> listOf(primary, DIM_LIGHT_RELAY)
                "cornea" -> listOf(primary, CORNEAL_SURFACE_RENEWAL)
                "respiratory", "trachea", "bronchi" -> listOf(primary, AIRWAY_CLEARANCE)
                "small-intestine" -> listOf(primary, INTESTINAL_ABSORPTION, SMOOTH_MUSCLE_WAVE)
                "tissue-intestinal-epithelium" -> listOf(primary, DIGESTION)
                "duodenum", "jejunum", "ileum", "cell-enterocyte" -> listOf(primary, INTESTINAL_ABSORPTION)
                "alveoli", "tissue-alveolar-epithelium" -> listOf(primary, ALVEOLAR_SURFACTANT)
                "patella" -> listOf(primary, KNEE_ARTICULATION)
                "cardio", "heart", "ventricles", "tissue-cardiac-muscle" -> listOf(primary, CARDIAC_EXCITATION)
                "aorta" -> listOf(primary, ARTERIAL_PULSE)
                "blood-vessels" -> listOf(primary, ENDOTHELIAL_EXCHANGE, VENOUS_RETURN)
                "stomach" -> listOf(primary, GASTRIC_ACID_SECRETION, GASTRIC_CHIEF_SECRETION)
                "salivary-glands", "oral-cavity" -> listOf(primary, SALIVA_SECRETION)
                "lungs" -> listOf(primary, PLEURAL_COUPLING)
                "tendons" -> listOf(primary, TENDON_FORCE_TRANSFER)
                else -> listOf(primary)
            }
        }

        fun safePhase(value: Float) = if (value.isFinite()) value.coerceIn(0f, 1f) else 0f
    }
}
