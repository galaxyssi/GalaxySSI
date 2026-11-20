package com.galaxyssi.chat

import android.content.Context

internal data class HealthAtlasMarker(val id: String, val x: Float, val y: Float) {
    init { require(x in 0f..1f && y in 0f..1f) }
}

internal data class HealthAtlasPlate(val drawable: Int, val owner: String?, val viewLabel: Int,
    val markers: List<HealthAtlasMarker>) {
    fun caption(context: Context, data: HealthBodyAtlas, selected: HealthAtlasItem?): String {
        val view = context.getString(viewLabel)
        return if (selected != null && selected.id != owner)
            context.getString(R.string.health_atlas_plate_context, data[requireNotNull(owner)]!!.name, view)
        else view
    }
}

/** Coordinates refer to the full transparent bitmap, not its nontransparent bounding box. */
internal object HealthAtlasPlates {
    val whole = HealthAtlasPlate(R.drawable.health_atlas_body, null, R.string.health_atlas_view_anterior, listOf(
        HealthAtlasMarker("brain", .50f, .045f), HealthAtlasMarker("lungs", .60f, .24f),
        HealthAtlasMarker("heart", .54f, .28f), HealthAtlasMarker("liver", .45f, .34f),
        HealthAtlasMarker("small-intestine", .51f, .44f)))
    private val heart = HealthAtlasPlate(R.drawable.health_atlas_heart, "heart", R.string.health_atlas_view_external, listOf(
        HealthAtlasMarker("atria", .28f, .46f), HealthAtlasMarker("coronary-vessels", .57f, .68f),
        HealthAtlasMarker("ventricles", .61f, .84f)))
    private val brain = HealthAtlasPlate(R.drawable.health_atlas_brain, "brain", R.string.health_atlas_view_lateral, listOf(
        HealthAtlasMarker("cerebrum", .60f, .34f), HealthAtlasMarker("cerebellum", .76f, .73f),
        HealthAtlasMarker("brainstem", .53f, .86f)))
    private val lungs = HealthAtlasPlate(R.drawable.health_atlas_lungs, "lungs", R.string.health_atlas_view_anterior, listOf(
        HealthAtlasMarker("trachea", .50f, .22f), HealthAtlasMarker("bronchi", .53f, .43f),
        HealthAtlasMarker("lungs", .80f, .70f)))
    private val liver = HealthAtlasPlate(R.drawable.health_atlas_liver, "liver", R.string.health_atlas_view_liver, listOf(
        HealthAtlasMarker("liver", .57f, .44f), HealthAtlasMarker("gallbladder", .28f, .73f)))
    private val kidney = HealthAtlasPlate(R.drawable.health_atlas_kidney, "kidneys", R.string.health_atlas_view_coronal, listOf(
        HealthAtlasMarker("renal-cortex", .37f, .12f), HealthAtlasMarker("renal-medulla", .36f, .24f),
        HealthAtlasMarker("renal-pelvis", .56f, .51f), HealthAtlasMarker("ureters", .68f, .85f)))
    private val beta = HealthAtlasPlate(R.drawable.health_atlas_beta_cell, "cell-pancreatic-beta-cell",
        R.string.health_atlas_view_cell, emptyList())
    private val erythrocyte = HealthAtlasPlate(R.drawable.health_atlas_erythrocyte, "cell-erythrocyte",
        R.string.health_atlas_view_erythrocyte, emptyList())
    private val neuron = HealthAtlasPlate(R.drawable.health_atlas_neuron, "cell-neuron",
        R.string.health_atlas_view_neuron, emptyList())
    val all = listOf(whole, heart, brain, lungs, liver, kidney, beta, erythrocyte, neuron)

    fun forId(id: String?): HealthAtlasPlate? = when (id) {
        null -> whole
        "heart", "cardio", "atria", "ventricles", "coronary-vessels" -> heart
        "brain", "cerebrum", "cerebellum", "brainstem" -> brain
        "lungs", "trachea", "bronchi" -> lungs
        "liver", "gallbladder" -> liver
        "kidneys", "renal-cortex", "renal-medulla", "renal-pelvis", "ureters" -> kidney
        "cell-pancreatic-beta-cell" -> beta
        "cell-erythrocyte" -> erythrocyte
        "cell-neuron" -> neuron
        else -> null
    }
}
