package com.galaxyssi.chat

/** Original schematics of representative tissue microstructure, not microscopy images. */
internal object HealthAtlasTissuePlates {
    private fun plate(id: String, drawable: Int, vararg cells: HealthAtlasMarker) = HealthAtlasPlate(
        drawable, "tissue-$id", R.string.health_atlas_view_tissue, cells.toList())

    val all = listOf(
        plate("epidermal", R.drawable.health_atlas_tissue_epidermal,
            HealthAtlasMarker("cell-keratinocyte", 0.2571f, 0.5750f)),
        plate("respiratory-epithelium", R.drawable.health_atlas_tissue_respiratory_epithelium,
            HealthAtlasMarker("cell-ciliated-airway-cell", 0.2286f, 0.3650f),
            HealthAtlasMarker("cell-goblet-cell", 0.4476f, 0.3900f)),
        plate("intestinal-epithelium", R.drawable.health_atlas_tissue_intestinal_epithelium,
            HealthAtlasMarker("cell-enterocyte", 0.2286f, 0.4650f)),
        plate("alveolar-epithelium", R.drawable.health_atlas_tissue_alveolar_epithelium,
            HealthAtlasMarker("cell-type-i-pneumocyte", 0.1976f, 0.5300f),
            HealthAtlasMarker("cell-type-ii-pneumocyte", 0.6071f, 0.5100f)),
        plate("vascular-endothelium", R.drawable.health_atlas_tissue_vascular_endothelium,
            HealthAtlasMarker("cell-vascular-endothelial-cell", 0.3167f, 0.5850f)),
        plate("renal-tubular-epithelium", R.drawable.health_atlas_tissue_renal_tubular_epithelium,
            HealthAtlasMarker("cell-proximal-tubular-cell", 0.3595f, 0.4200f)),
        plate("skeletal-muscle", R.drawable.health_atlas_tissue_skeletal_muscle,
            HealthAtlasMarker("cell-skeletal-myocyte", 0.3143f, 0.5500f)),
        plate("cardiac-muscle", R.drawable.health_atlas_tissue_cardiac_muscle,
            HealthAtlasMarker("cell-cardiomyocyte", 0.2690f, 0.4350f)),
        plate("smooth-muscle", R.drawable.health_atlas_tissue_smooth_muscle,
            HealthAtlasMarker("cell-smooth-muscle-cell", 0.3048f, 0.3650f)),
        plate("dense-regular-connective", R.drawable.health_atlas_tissue_dense_regular_connective,
            HealthAtlasMarker("cell-tenocyte", 0.2976f, 0.4450f)),
        plate("compact-bone", R.drawable.health_atlas_tissue_compact_bone,
            HealthAtlasMarker("cell-osteocyte", 0.4952f, 0.3150f)),
        plate("hyaline-cartilage", R.drawable.health_atlas_tissue_hyaline_cartilage,
            HealthAtlasMarker("cell-chondrocyte", 0.3143f, 0.4750f)),
        plate("white-adipose", R.drawable.health_atlas_tissue_white_adipose,
            HealthAtlasMarker("cell-adipocyte", 0.2905f, 0.3350f)),
        plate("central-nervous", R.drawable.health_atlas_tissue_central_nervous,
            HealthAtlasMarker("cell-neuron", 0.3119f, 0.5100f),
            HealthAtlasMarker("cell-astrocyte", 0.6119f, 0.2700f)),
    )
    private val byId = all.associateBy { it.owner }
    fun forId(id: String) = byId[id]
}
