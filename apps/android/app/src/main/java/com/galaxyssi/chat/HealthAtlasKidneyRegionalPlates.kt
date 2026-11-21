package com.galaxyssi.chat

internal object HealthAtlasKidneyRegionalPlates {
    private const val HISTOLOGY = "https://histologylab.ctl.columbia.edu/lab12/kidney/"
    private const val GROSS_ANATOMY =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-3-gross-anatomy-of-the-kidney"

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)
    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(marker(id, x, y), title, explanation)

    val all = listOf(
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_renal_cortex_cutaway,
            owner = "renal-cortex",
            viewLabel = R.string.health_atlas_renal_cortex_cutaway_view,
            markers = listOf(marker("renal-medulla", 118, 226)),
            source = HISTOLOGY,
            viewKey = "renal-cortex-cutaway",
            selectorLabel = R.string.health_atlas_renal_cortex_cutaway_selector,
            features = listOf(
                feature("renal-cortex-capsule", 100, 49, R.string.health_atlas_renal_cortex_capsule,
                    R.string.health_atlas_renal_cortex_capsule_detail),
                feature("renal-cortex-corpuscle", 112, 109, R.string.health_atlas_renal_cortex_corpuscle,
                    R.string.health_atlas_renal_cortex_corpuscle_detail),
                feature("renal-cortex-ray", 202, 110, R.string.health_atlas_renal_cortex_ray,
                    R.string.health_atlas_renal_cortex_ray_detail),
                feature("renal-cortex-labyrinth", 254, 170, R.string.health_atlas_renal_cortex_labyrinth,
                    R.string.health_atlas_renal_cortex_labyrinth_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_renal_medulla_cutaway,
            owner = "renal-medulla",
            viewLabel = R.string.health_atlas_renal_medulla_cutaway_view,
            markers = listOf(marker("renal-cortex", 242, 51)),
            source = HISTOLOGY,
            viewKey = "renal-medulla-cutaway",
            selectorLabel = R.string.health_atlas_renal_medulla_cutaway_selector,
            features = listOf(
                feature("renal-medulla-pyramid-base", 120, 75, R.string.health_atlas_renal_medulla_pyramid_base,
                    R.string.health_atlas_renal_medulla_pyramid_base_detail),
                feature("renal-medulla-column", 79, 125, R.string.health_atlas_renal_medulla_column,
                    R.string.health_atlas_renal_medulla_column_detail),
                feature("renal-medulla-ducts", 219, 130, R.string.health_atlas_renal_medulla_ducts,
                    R.string.health_atlas_renal_medulla_ducts_detail),
                feature("renal-medulla-papilla", 188, 204, R.string.health_atlas_renal_medulla_papilla,
                    R.string.health_atlas_renal_medulla_papilla_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_renal_pelvis_cutaway,
            owner = "renal-pelvis",
            viewLabel = R.string.health_atlas_renal_pelvis_cutaway_view,
            markers = listOf(marker("ureters", 263, 237)),
            source = GROSS_ANATOMY,
            viewKey = "renal-pelvis-cutaway",
            selectorLabel = R.string.health_atlas_renal_pelvis_cutaway_selector,
            features = listOf(
                feature("renal-pelvis-minor-calyx", 117, 64, R.string.health_atlas_renal_pelvis_minor_calyx,
                    R.string.health_atlas_renal_pelvis_minor_calyx_detail),
                feature("renal-pelvis-major-calyx", 164, 104, R.string.health_atlas_renal_pelvis_major_calyx,
                    R.string.health_atlas_renal_pelvis_major_calyx_detail),
                feature("renal-pelvis-funnel", 221, 154, R.string.health_atlas_renal_pelvis_funnel,
                    R.string.health_atlas_renal_pelvis_funnel_detail),
            ),
            splitCallouts = true,
        ),
    )

    fun forId(id: String): HealthAtlasPlate? = all.firstOrNull { it.owner == id }
}
