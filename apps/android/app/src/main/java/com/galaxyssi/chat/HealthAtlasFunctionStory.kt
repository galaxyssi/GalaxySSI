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
        else -> title
    }

    val relatedLessons get() = when (this) {
        INSULIN_SECRETION -> listOf("tissue-skeletal-muscle" to GLUCOSE, "cell-pancreatic-alpha-cell" to GLUCAGON_RESPONSE)
        GLUCAGON_RESPONSE -> listOf("cell-pancreatic-beta-cell" to INSULIN_SECRETION)
        GLUCOSE -> listOf("cell-pancreatic-beta-cell" to INSULIN_SECRETION)
        SYNAPTIC_SIGNAL -> listOf("cell-oligodendrocyte" to MYELIN_SIGNAL)
        MYELIN_SIGNAL -> listOf("cell-neuron" to SYNAPTIC_SIGNAL)
        SWEAT_COOLING -> listOf("epidermis" to EPIDERMAL_BARRIER)
        EPIDERMAL_BARRIER -> listOf("sweat-glands" to SWEAT_COOLING)
        OLFACTION -> listOf("taste-buds" to TASTE_SIGNAL)
        TASTE_SIGNAL -> listOf("olfactory-mucosa" to OLFACTION)
        TOUCH_SIGNAL -> listOf("epidermis" to EPIDERMAL_BARRIER)
        VESTIBULAR_BALANCE -> listOf("cochlea" to HEARING)
        RPE_VISUAL_CYCLE -> listOf("cell-retinal-aii-amacrine-cell" to DIM_LIGHT_RELAY)
        DIM_LIGHT_RELAY -> listOf("cell-rod-photoreceptor" to LIGHT_ADAPTATION)
        CORNEAL_SURFACE_RENEWAL -> listOf("cornea" to VISION)
        BREATHING -> listOf("tissue-respiratory-epithelium" to AIRWAY_CLEARANCE)
        AIRWAY_CLEARANCE -> listOf("lungs" to BREATHING)
        else -> emptyList()
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
        GLUCAGON_RESPONSE, SWEAT_COOLING -> HealthAtlasHomeostasisStoryView(context, this)
        SYNAPTIC_SIGNAL, MYELIN_SIGNAL, THYROID_FEEDBACK -> HealthAtlasSignalStoryView(context, this)
        EPIDERMAL_BARRIER -> HealthAtlasBarrierStoryView(context)
        SPERM_TRANSPORT, OVUM_TRANSPORT -> HealthAtlasGameteStoryView(context, this)
        OLFACTION, TASTE_SIGNAL -> HealthAtlasChemicalSenseStoryView(context, this)
        TOUCH_SIGNAL, VESTIBULAR_BALANCE -> HealthAtlasMotionSenseStoryView(context, this)
        RPE_VISUAL_CYCLE, DIM_LIGHT_RELAY, CORNEAL_SURFACE_RENEWAL -> HealthAtlasOcularStoryView(context, this)
        AIRWAY_CLEARANCE -> HealthAtlasAirwayStoryView(context)
    }

    companion object {
        fun forId(id: String?) = if (id == null) null else entries.firstOrNull { id in it.owners }

        fun choicesForId(id: String?): List<HealthAtlasFunctionStory> {
            val primary = forId(id) ?: return emptyList()
            return when (id) {
                "pancreas" -> listOf(primary, INSULIN_SECRETION, GLUCAGON_RESPONSE)
                "endocrine" -> listOf(primary, GLUCAGON_RESPONSE, THYROID_FEEDBACK)
                "pancreatic-islets" -> listOf(primary, GLUCAGON_RESPONSE)
                "nervous", "brain", "spinal-cord", "cell-neuron", "tissue-central-nervous" -> listOf(primary, MYELIN_SIGNAL)
                "tissue-skeletal-muscle" -> listOf(primary, MUSCLE_MOTION)
                "cell-skeletal-myocyte" -> listOf(primary, GLUCOSE)
                "immune" -> listOf(primary, LYMPH_RETURN)
                "skin" -> listOf(primary, EPIDERMAL_BARRIER, TOUCH_SIGNAL)
                "skin-organ", "epidermis" -> listOf(primary, TOUCH_SIGNAL)
                "sensory" -> listOf(primary, HEARING, VESTIBULAR_BALANCE, OLFACTION, TASTE_SIGNAL, TOUCH_SIGNAL)
                "ear", "inner-ear", "cell-inner-ear-hair-cell" -> listOf(primary, VESTIBULAR_BALANCE)
                "tongue" -> listOf(primary, TASTE_SIGNAL)
                "gut" -> listOf(primary, COLON)
                "retina" -> listOf(primary, DIM_LIGHT_RELAY, RPE_VISUAL_CYCLE)
                "cell-rod-photoreceptor" -> listOf(primary, DIM_LIGHT_RELAY, RPE_VISUAL_CYCLE)
                "cell-retinal-bipolar-cell" -> listOf(primary, DIM_LIGHT_RELAY)
                "cornea" -> listOf(primary, CORNEAL_SURFACE_RENEWAL)
                "respiratory", "trachea", "bronchi" -> listOf(primary, AIRWAY_CLEARANCE)
                else -> listOf(primary)
            }
        }

        fun safePhase(value: Float) = if (value.isFinite()) value.coerceIn(0f, 1f) else 0f
    }
}
