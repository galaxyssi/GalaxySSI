package com.galaxyssi.chat

/** Representative instructional views; adjacent structures are context, not additional catalogue entries. */
internal object HealthAtlasCoreCellPlates {
    private const val BOOK = "https://openstax.org/books/anatomy-and-physiology-2e/pages/"
    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, explanation)
    private fun plate(id: String, drawable: Int, chapter: String, vararg features: HealthAtlasFeature) =
        HealthAtlasPlate(drawable, id, R.string.health_atlas_cell_morphology, emptyList(), BOOK + chapter,
            features = features.toList())
    val all = listOf(
        plate("cell-astrocyte", R.drawable.health_atlas_core_astrocyte, "12-2-nervous-tissue",
            feature("astrocyte-endfoot", 257, 213, R.string.health_atlas_feature_astrocyte_endfoot, R.string.health_atlas_feature_astrocyte_endfoot_detail),
            feature("astrocyte-branches", 121, 95, R.string.health_atlas_feature_astrocyte_branches, R.string.health_atlas_feature_astrocyte_branches_detail)),
        plate("cell-schwann-cell", R.drawable.health_atlas_core_schwann, "12-2-nervous-tissue",
            feature("schwann-myelin", 180, 111, R.string.health_atlas_feature_schwann_myelin, R.string.health_atlas_feature_schwann_myelin_detail),
            feature("schwann-nucleus", 191, 77, R.string.health_atlas_feature_schwann_nucleus, R.string.health_atlas_feature_schwann_nucleus_detail)),
        plate("cell-skeletal-myocyte", R.drawable.health_atlas_core_skeletal_myocyte, "10-3-muscle-fiber-contraction-and-relaxation",
            feature("skeletal-striations", 175, 147, R.string.health_atlas_feature_skeletal_striations, R.string.health_atlas_feature_skeletal_striations_detail),
            feature("peripheral-nuclei", 95, 100, R.string.health_atlas_feature_peripheral_nuclei, R.string.health_atlas_feature_peripheral_nuclei_detail)),
        plate("cell-cardiomyocyte", R.drawable.health_atlas_core_cardiomyocyte, "10-7-cardiac-muscle-tissue",
            feature("intercalated-disc", 253, 124, R.string.health_atlas_feature_intercalated_disc, R.string.health_atlas_feature_intercalated_disc_detail),
            feature("cardiac-central-nucleus", 167, 149, R.string.health_atlas_feature_cardiac_central_nucleus, R.string.health_atlas_feature_cardiac_central_nucleus_detail),
            feature("cardiac-branch", 220, 117, R.string.health_atlas_feature_cardiac_branch, R.string.health_atlas_feature_cardiac_branch_detail)),
        plate("cell-smooth-muscle-cell", R.drawable.health_atlas_core_smooth_muscle_cell, "10-8-smooth-muscle",
            feature("smooth-spindle", 103, 141, R.string.health_atlas_feature_smooth_spindle, R.string.health_atlas_feature_smooth_spindle_detail),
            feature("smooth-central-nucleus", 179, 138, R.string.health_atlas_feature_smooth_central_nucleus, R.string.health_atlas_feature_smooth_central_nucleus_detail)),
        plate("cell-keratinocyte", R.drawable.health_atlas_core_keratinocyte, "5-1-layers-of-the-skin",
            feature("keratin-filaments", 216, 154, R.string.health_atlas_feature_keratin_filaments, R.string.health_atlas_feature_keratin_filaments_detail),
            feature("cell-junction", 243, 102, R.string.health_atlas_feature_cell_junction, R.string.health_atlas_feature_cell_junction_detail)),
        plate("cell-melanocyte", R.drawable.health_atlas_core_melanocyte, "5-1-layers-of-the-skin",
            feature("melanosomes", 196, 122, R.string.health_atlas_feature_melanosomes, R.string.health_atlas_feature_melanosomes_detail),
            feature("melanocyte-dendrite", 257, 161, R.string.health_atlas_feature_melanocyte_dendrite, R.string.health_atlas_feature_melanocyte_dendrite_detail)),
        plate("cell-fibroblast", R.drawable.health_atlas_core_fibroblast, "4-3-connective-tissue-supports-and-protects",
            feature("fibroblast-spindle", 219, 125, R.string.health_atlas_feature_fibroblast_spindle, R.string.health_atlas_feature_fibroblast_spindle_detail),
            feature("fibroblast-matrix", 225, 198, R.string.health_atlas_feature_fibroblast_matrix, R.string.health_atlas_feature_fibroblast_matrix_detail)),
        plate("cell-adipocyte", R.drawable.health_atlas_core_adipocyte, "4-3-connective-tissue-supports-and-protects",
            feature("lipid-droplet", 180, 132, R.string.health_atlas_feature_lipid_droplet, R.string.health_atlas_feature_lipid_droplet_detail),
            feature("adipocyte-nucleus", 93, 187, R.string.health_atlas_feature_adipocyte_nucleus, R.string.health_atlas_feature_adipocyte_nucleus_detail)),
        plate("cell-osteoblast", R.drawable.health_atlas_core_osteoblast, "6-3-bone-structure",
            feature("osteoblast-surface", 185, 111, R.string.health_atlas_feature_osteoblast_surface, R.string.health_atlas_feature_osteoblast_surface_detail),
            feature("osteoid", 180, 164, R.string.health_atlas_feature_osteoid, R.string.health_atlas_feature_osteoid_detail)),
        plate("cell-osteocyte", R.drawable.health_atlas_core_osteocyte, "6-3-bone-structure",
            feature("osteocyte-lacuna", 181, 139, R.string.health_atlas_feature_osteocyte_lacuna, R.string.health_atlas_feature_osteocyte_lacuna_detail),
            feature("canaliculi", 244, 167, R.string.health_atlas_feature_canaliculi, R.string.health_atlas_feature_canaliculi_detail)),
        plate("cell-osteoclast", R.drawable.health_atlas_core_osteoclast, "6-3-bone-structure",
            feature("multiple-nuclei", 181, 114, R.string.health_atlas_feature_multiple_nuclei, R.string.health_atlas_feature_multiple_nuclei_detail),
            feature("ruffled-border", 185, 178, R.string.health_atlas_feature_ruffled_border, R.string.health_atlas_feature_ruffled_border_detail)),
        plate("cell-chondrocyte", R.drawable.health_atlas_core_chondrocyte, "4-3-connective-tissue-supports-and-protects",
            feature("cartilage-lacuna", 228, 143, R.string.health_atlas_feature_cartilage_lacuna, R.string.health_atlas_feature_cartilage_lacuna_detail),
            feature("cartilage-matrix", 268, 177, R.string.health_atlas_feature_cartilage_matrix, R.string.health_atlas_feature_cartilage_matrix_detail)),
        plate("cell-vascular-endothelial-cell", R.drawable.health_atlas_core_vascular_endothelial_cell, "20-1-structure-and-function-of-blood-vessels",
            feature("endothelial-sheet", 114, 148, R.string.health_atlas_feature_endothelial_sheet, R.string.health_atlas_feature_endothelial_sheet_detail),
            feature("endothelial-nucleus", 187, 151, R.string.health_atlas_feature_endothelial_nucleus, R.string.health_atlas_feature_endothelial_nucleus_detail)),
        plate("cell-hepatocyte", R.drawable.health_atlas_core_hepatocyte, "23-6-accessory-organs-in-digestion-the-liver-pancreas-and-gallbladder",
            feature("hepatocyte-body", 187, 117, R.string.health_atlas_feature_hepatocyte_body, R.string.health_atlas_feature_hepatocyte_body_detail),
            feature("bile-canaliculus", 236, 139, R.string.health_atlas_feature_bile_canaliculus, R.string.health_atlas_feature_bile_canaliculus_detail)),
        plate("cell-enterocyte", R.drawable.health_atlas_core_enterocyte, "23-7-chemical-digestion-and-absorption-a-closer-look",
            feature("microvilli", 165, 59, R.string.health_atlas_feature_microvilli, R.string.health_atlas_feature_microvilli_detail),
            feature("enterocyte-basal", 184, 225, R.string.health_atlas_feature_enterocyte_basal, R.string.health_atlas_feature_enterocyte_basal_detail)),
        plate("cell-spermatozoon", R.drawable.health_atlas_core_spermatozoon, "28-1-fertilization",
            feature("acrosome", 73, 128, R.string.health_atlas_feature_acrosome, R.string.health_atlas_feature_acrosome_detail),
            feature("sperm-midpiece", 159, 140, R.string.health_atlas_feature_sperm_midpiece, R.string.health_atlas_feature_sperm_midpiece_detail),
            feature("flagellum", 263, 167, R.string.health_atlas_feature_flagellum, R.string.health_atlas_feature_flagellum_detail)),
        plate("cell-oocyte-or-ovum", R.drawable.health_atlas_core_oocyte, "28-1-fertilization",
            feature("oocyte-zona", 271, 151, R.string.health_atlas_feature_oocyte_zona, R.string.health_atlas_feature_oocyte_zona_detail),
            feature("polar-body", 208, 75, R.string.health_atlas_feature_polar_body, R.string.health_atlas_feature_polar_body_detail),
            feature("corona-radiata", 102, 63, R.string.health_atlas_feature_corona_radiata, R.string.health_atlas_feature_corona_radiata_detail)),
    )
    private val byId = all.associateBy { it.owner }
    fun forId(id: String): HealthAtlasPlate? = byId[id]
}
