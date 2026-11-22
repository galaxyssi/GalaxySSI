package com.galaxyssi.chat

internal object HealthAtlasOpticsDetailPlates {
    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)

    val all = listOf(
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_corneal_lamellae,
            owner = "cornea",
            viewLabel = R.string.health_atlas_optics_cornea_detail,
            markers = emptyList(),
            source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC9317547/",
            viewKey = "corneal-layers",
            selectorLabel = R.string.health_atlas_optics_cornea_detail,
            features = listOf(
                feature("optics-cornea-tear", 178, 64, R.string.health_atlas_optics_cornea_tear,
                    R.string.health_atlas_optics_cornea_tear_detail),
                feature("optics-cornea-epithelium", 83, 93, R.string.health_atlas_optics_cornea_epithelium,
                    R.string.health_atlas_optics_cornea_epithelium_detail),
                feature("optics-cornea-bowman", 244, 95, R.string.health_atlas_optics_cornea_bowman,
                    R.string.health_atlas_optics_cornea_bowman_detail),
                feature("optics-cornea-stroma", 148, 125, R.string.health_atlas_optics_cornea_stroma,
                    R.string.health_atlas_optics_cornea_stroma_detail),
                feature("optics-cornea-descemet", 219, 169, R.string.health_atlas_optics_cornea_descemet,
                    R.string.health_atlas_optics_cornea_descemet_detail),
                feature("optics-cornea-endothelium", 101, 185, R.string.health_atlas_optics_cornea_endothelium,
                    R.string.health_atlas_optics_cornea_endothelium_detail),
                feature("optics-cornea-aqueous", 269, 222, R.string.health_atlas_optics_cornea_aqueous,
                    R.string.health_atlas_optics_cornea_aqueous_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_lens_fibers,
            owner = "lens",
            viewLabel = R.string.health_atlas_optics_lens_detail,
            markers = emptyList(),
            source = "https://pubmed.ncbi.nlm.nih.gov/8641842/",
            viewKey = "lens-fibers-and-zonules",
            selectorLabel = R.string.health_atlas_optics_lens_detail,
            features = listOf(
                feature("optics-lens-capsule", 269, 141, R.string.health_atlas_optics_lens_capsule,
                    R.string.health_atlas_optics_lens_capsule_detail),
                feature("optics-lens-epithelium", 117, 140, R.string.health_atlas_optics_lens_epithelium,
                    R.string.health_atlas_optics_lens_epithelium_detail),
                feature("optics-lens-cortex", 236, 166, R.string.health_atlas_optics_lens_cortex,
                    R.string.health_atlas_optics_lens_cortex_detail),
                feature("optics-lens-nucleus", 186, 142, R.string.health_atlas_optics_lens_nucleus,
                    R.string.health_atlas_optics_lens_nucleus_detail),
                feature("optics-lens-zonules", 146, 51, R.string.health_atlas_optics_lens_zonules,
                    R.string.health_atlas_optics_lens_zonules_detail),
                feature("optics-lens-ciliary", 90, 46, R.string.health_atlas_optics_lens_ciliary,
                    R.string.health_atlas_optics_lens_ciliary_detail),
            ),
            splitCallouts = true,
        ),
    )
}
