package com.galaxyssi.chat

/** Original instructional diagrams; colors, dimensions and receptor shapes are schematic. */
internal object HealthAtlasImmunePlates {
    private const val BOOK = "https://openstax.org/books/anatomy-and-physiology-2e/pages/"
    private const val BLOOD = BOOK + "18-4-leukocytes-and-platelets"
    const val INNATE = BOOK + "21-2-barrier-defenses-and-the-innate-immune-response"
    private const val T_CELLS = BOOK + "21-3-the-adaptive-immune-response-t-lymphocytes-and-their-functional-types"
    private const val B_CELLS = BOOK + "21-4-the-adaptive-immune-response-b-lymphocytes-and-antibodies"

    private fun feature(id: String, x: Int, y: Int, name: Int, explanation: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), name, explanation)
    private fun paintedFeature(id: String, x: Int, y: Int, name: Int, explanation: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 1254f, y / 1254f), name, explanation)
    private fun plate(owner: String, drawable: Int, viewLabel: Int, source: String, vararg features: HealthAtlasFeature) =
        HealthAtlasPlate(drawable, owner, viewLabel, emptyList(), source, features = features.toList())

    val all = listOf(
        plate("cell-neutrophil", R.drawable.health_atlas_cell_neutrophil, R.string.health_atlas_cell_morphology, BLOOD,
            paintedFeature("lobulated", 593, 540, R.string.health_atlas_feature_lobulated, R.string.health_atlas_feature_lobulated_detail),
            paintedFeature("fine-granules", 917, 652, R.string.health_atlas_feature_fine_granules, R.string.health_atlas_feature_fine_granules_detail)),
        plate("cell-eosinophil", R.drawable.health_atlas_cell_eosinophil, R.string.health_atlas_cell_morphology, BLOOD,
            paintedFeature("bilobed", 488, 604, R.string.health_atlas_feature_bilobed, R.string.health_atlas_feature_bilobed_detail),
            paintedFeature("eosin-granules", 904, 587, R.string.health_atlas_feature_eosin_granules, R.string.health_atlas_feature_eosin_granules_detail)),
        plate("cell-basophil", R.drawable.health_atlas_cell_basophil, R.string.health_atlas_cell_morphology, BLOOD,
            paintedFeature("obscured-nucleus", 495, 484, R.string.health_atlas_feature_obscured_nucleus, R.string.health_atlas_feature_obscured_nucleus_detail),
            paintedFeature("baso-granules", 900, 593, R.string.health_atlas_feature_baso_granules, R.string.health_atlas_feature_baso_granules_detail)),
        plate("cell-monocyte", R.drawable.health_atlas_cell_monocyte, R.string.health_atlas_cell_morphology, BLOOD,
            feature("kidney-nucleus", 128, 131, R.string.health_atlas_feature_kidney_nucleus, R.string.health_atlas_feature_kidney_nucleus_detail),
            feature("monocyte-cytoplasm", 238, 152, R.string.health_atlas_feature_monocyte_cytoplasm, R.string.health_atlas_feature_monocyte_cytoplasm_detail)),
        plate("cell-macrophage", R.drawable.health_atlas_cell_macrophage, R.string.health_atlas_cell_morphology, INNATE,
            paintedFeature("cell-projection", 1028, 410, R.string.health_atlas_feature_cell_projection, R.string.health_atlas_feature_cell_projection_detail),
            paintedFeature("vesicle", 712, 615, R.string.health_atlas_feature_vesicle, R.string.health_atlas_feature_vesicle_detail)),
        plate("cell-t-cell", R.drawable.health_atlas_cell_t, R.string.health_atlas_cell_receptor_scheme, T_CELLS,
            feature("t-receptor", 301, 149, R.string.health_atlas_feature_t_receptor, R.string.health_atlas_feature_t_receptor_detail),
            feature("lymphocyte-nucleus", 173, 145, R.string.health_atlas_feature_lymphocyte_nucleus, R.string.health_atlas_feature_lymphocyte_nucleus_detail)),
        plate("cell-b-cell", R.drawable.health_atlas_cell_b, R.string.health_atlas_cell_receptor_scheme, B_CELLS,
            feature("b-receptor", 303, 150, R.string.health_atlas_feature_b_receptor, R.string.health_atlas_feature_b_receptor_detail),
            feature("lymphocyte-nucleus", 173, 145, R.string.health_atlas_feature_lymphocyte_nucleus, R.string.health_atlas_feature_lymphocyte_nucleus_detail)),
        plate("cell-natural-killer-cell", R.drawable.health_atlas_cell_nk, R.string.health_atlas_cell_morphology, INNATE,
            feature("cytotoxic-granules", 239, 166, R.string.health_atlas_feature_cytotoxic_granules, R.string.health_atlas_feature_cytotoxic_granules_detail),
            feature("lymphocyte-nucleus", 155, 135, R.string.health_atlas_feature_lymphocyte_nucleus, R.string.health_atlas_feature_lymphocyte_nucleus_detail)),
        plate("cell-plasma-cell", R.drawable.health_atlas_cell_plasma, R.string.health_atlas_cell_morphology, B_CELLS,
            feature("plasma-nucleus", 121, 145, R.string.health_atlas_feature_plasma_nucleus, R.string.health_atlas_feature_plasma_nucleus_detail),
            feature("golgi-zone", 187, 140, R.string.health_atlas_feature_golgi_zone, R.string.health_atlas_feature_golgi_zone_detail),
            feature("rough-er", 246, 171, R.string.health_atlas_feature_rough_er, R.string.health_atlas_feature_rough_er_detail)),
        plate("cell-megakaryocyte", R.drawable.health_atlas_cell_megakaryocyte, R.string.health_atlas_cell_morphology, BLOOD,
            feature("polyploid", 184, 135, R.string.health_atlas_feature_polyploid, R.string.health_atlas_feature_polyploid_detail),
            feature("proplatelet", 281, 158, R.string.health_atlas_feature_proplatelet, R.string.health_atlas_feature_proplatelet_detail)),
        plate("fragment-platelet", R.drawable.health_atlas_cell_platelet, R.string.health_atlas_platelet_disc, BLOOD,
            feature("anucleate", 144, 148, R.string.health_atlas_feature_anucleate, R.string.health_atlas_feature_anucleate_detail),
            feature("platelet-granules", 209, 139, R.string.health_atlas_feature_platelet_granules, R.string.health_atlas_feature_platelet_granules_detail)),
        plate("cell-dendritic-cell", R.drawable.health_atlas_cell_dendritic, R.string.health_atlas_cell_morphology, INNATE,
            feature("dendritic-process", 284, 99, R.string.health_atlas_feature_dendritic_process, R.string.health_atlas_feature_dendritic_process_detail),
            feature("dendritic-nucleus", 171, 145, R.string.health_atlas_feature_dendritic_nucleus, R.string.health_atlas_feature_dendritic_nucleus_detail)),
    )
    private val byId = all.associateBy { it.owner }
    fun forId(id: String): HealthAtlasPlate? = byId[id]
}
