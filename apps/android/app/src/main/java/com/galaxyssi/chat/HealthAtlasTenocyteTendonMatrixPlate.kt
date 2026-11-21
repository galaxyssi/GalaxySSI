package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasTenocyteTendonMatrixPlate {
    const val VIEW_KEY = "tenocyte-tendon-longitudinal"

    val plate = HealthAtlasPlate(
        R.drawable.health_atlas_tenocyte_tendon_matrix_longitudinal,
        HealthAtlasTenocyteTendonMatrixAssignment.ID,
        string.health_atlas_tenocyte_tendon_matrix_plate_caption,
        emptyList(),
        HealthAtlasTenocyteTendonMatrixAssignment.MORPHOLOGY_SOURCE,
        viewKey = VIEW_KEY,
        selectorLabel = string.health_atlas_tenocyte_tendon_matrix_plate_selector,
        features = listOf(
            feature("tenocyte-tendon-matrix-nucleus", 92, 104,
                string.health_atlas_tenocyte_tendon_matrix_art_nucleus,
                string.health_atlas_tenocyte_tendon_matrix_plate_nucleus_detail),
            feature("tenocyte-tendon-matrix-cell", 235, 148,
                string.health_atlas_tenocyte_tendon_matrix_plate_cell,
                string.health_atlas_tenocyte_tendon_matrix_plate_cell_detail),
            feature("tenocyte-tendon-matrix-fibers", 264, 177,
                string.health_atlas_tenocyte_tendon_matrix_art_fibers,
                string.health_atlas_tenocyte_tendon_matrix_plate_fibers_detail),
        ),
        splitCallouts = true,
    )

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)
}
