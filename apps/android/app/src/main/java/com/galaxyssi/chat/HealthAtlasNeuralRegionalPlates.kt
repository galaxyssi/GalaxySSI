package com.galaxyssi.chat

internal object HealthAtlasNeuralRegionalPlates {
    private const val BRAINSTEM_SOURCE = "https://brain.oit.duke.edu/lab03/lab03.html"
    private const val CEREBELLUM_SOURCE = "https://nba.uth.tmc.edu/neuroscience/s3/chapter05.html"
    private const val SPINAL_CORD_SOURCE =
        "https://cumming.ucalgary.ca/sites/default/files/teams/122/education/neurosurgery/spine3-sl-anatomy-of-the-spinal-cord.pdf"

    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, explanation)

    val all = listOf(
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_brainstem_midline_section,
            owner = "brainstem",
            viewLabel = R.string.health_atlas_brainstem_section_view,
            markers = emptyList(),
            source = BRAINSTEM_SOURCE,
            viewKey = "brainstem-midline-section",
            selectorLabel = R.string.health_atlas_brainstem_section_selector,
            features = listOf(
                feature("brainstem-section-midbrain", 162, 55, R.string.health_atlas_brainstem_section_midbrain,
                    R.string.health_atlas_brainstem_section_midbrain_detail),
                feature("brainstem-section-aqueduct", 191, 73, R.string.health_atlas_brainstem_section_aqueduct,
                    R.string.health_atlas_brainstem_section_aqueduct_detail),
                feature("brainstem-section-pons", 121, 127, R.string.health_atlas_brainstem_section_pons,
                    R.string.health_atlas_brainstem_section_pons_detail),
                feature("brainstem-section-fourth-ventricle", 213, 134,
                    R.string.health_atlas_brainstem_section_fourth_ventricle,
                    R.string.health_atlas_brainstem_section_fourth_ventricle_detail),
                feature("brainstem-section-medulla", 153, 197, R.string.health_atlas_brainstem_section_medulla,
                    R.string.health_atlas_brainstem_section_medulla_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_cerebellum_vermis_section,
            owner = "cerebellum",
            viewLabel = R.string.health_atlas_cerebellum_section_view,
            markers = emptyList(),
            source = CEREBELLUM_SOURCE,
            viewKey = "cerebellum-vermis-section",
            selectorLabel = R.string.health_atlas_cerebellum_section_selector,
            features = listOf(
                feature("cerebellum-section-anterior-lobe", 107, 83,
                    R.string.health_atlas_cerebellum_section_anterior_lobe,
                    R.string.health_atlas_cerebellum_section_anterior_lobe_detail),
                feature("cerebellum-section-primary-fissure", 172, 72,
                    R.string.health_atlas_cerebellum_section_primary_fissure,
                    R.string.health_atlas_cerebellum_section_primary_fissure_detail),
                feature("cerebellum-section-posterior-lobe", 234, 98,
                    R.string.health_atlas_cerebellum_section_posterior_lobe,
                    R.string.health_atlas_cerebellum_section_posterior_lobe_detail),
                feature("cerebellum-section-arbor-vitae", 154, 132, R.string.health_atlas_cerebellum_section_arbor_vitae,
                    R.string.health_atlas_cerebellum_section_arbor_vitae_detail),
                feature("cerebellum-section-folia", 289, 172, R.string.health_atlas_cerebellum_section_folia,
                    R.string.health_atlas_cerebellum_section_folia_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_spinal_cord_transverse_section,
            owner = "spinal-cord",
            viewLabel = R.string.health_atlas_spinal_cord_section_view,
            markers = emptyList(),
            source = SPINAL_CORD_SOURCE,
            viewKey = "spinal-cord-transverse-section",
            selectorLabel = R.string.health_atlas_spinal_cord_section_selector,
            features = listOf(
                feature("spinal-cord-section-posterior-sulcus", 179, 67,
                    R.string.health_atlas_spinal_cord_section_posterior_sulcus,
                    R.string.health_atlas_spinal_cord_section_posterior_sulcus_detail),
                feature("spinal-cord-section-dorsal-horn", 134, 109, R.string.health_atlas_spinal_cord_section_dorsal_horn,
                    R.string.health_atlas_spinal_cord_section_dorsal_horn_detail),
                feature("spinal-cord-section-central-canal", 180, 136,
                    R.string.health_atlas_spinal_cord_section_central_canal,
                    R.string.health_atlas_spinal_cord_section_central_canal_detail),
                feature("spinal-cord-section-white-matter", 263, 143,
                    R.string.health_atlas_spinal_cord_section_white_matter,
                    R.string.health_atlas_spinal_cord_section_white_matter_detail),
                feature("spinal-cord-section-ventral-horn", 133, 174,
                    R.string.health_atlas_spinal_cord_section_ventral_horn,
                    R.string.health_atlas_spinal_cord_section_ventral_horn_detail),
                feature("spinal-cord-section-anterior-fissure", 185, 198,
                    R.string.health_atlas_spinal_cord_section_anterior_fissure,
                    R.string.health_atlas_spinal_cord_section_anterior_fissure_detail),
            ),
            splitCallouts = true,
        ),
    )

    fun forId(id: String): HealthAtlasPlate? = all.firstOrNull { it.owner == id }
}
