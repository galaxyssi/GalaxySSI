package com.galaxyssi.chat

import android.content.Context

internal data class HealthAtlasMarker(val id: String, val x: Float, val y: Float) {
    init { require(x in 0f..1f && y in 0f..1f) }
}

internal data class HealthAtlasPlate(val drawable: Int, val owner: String?, val viewLabel: Int,
    val markers: List<HealthAtlasMarker>, val source: String? = null) {
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
    private val urinary = HealthAtlasPlate(R.drawable.health_atlas_urinary, "urinary",
        R.string.health_atlas_view_urinary, listOf(
            HealthAtlasMarker("kidneys", .73f, .22f), HealthAtlasMarker("ureters", .66f, .53f),
            HealthAtlasMarker("bladder", .50f, .79f), HealthAtlasMarker("urethra", .48f, .91f)),
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-2-gross-anatomy-of-urine-transport")
    private val gut = HealthAtlasPlate(R.drawable.health_atlas_gut, "gut", R.string.health_atlas_view_gut, listOf(
        HealthAtlasMarker("esophagus", .56f, .08f), HealthAtlasMarker("stomach", .66f, .24f),
        HealthAtlasMarker("large-intestine", .85f, .52f), HealthAtlasMarker("small-intestine", .47f, .60f),
        HealthAtlasMarker("appendix", .26f, .79f), HealthAtlasMarker("rectum", .50f, .90f)),
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-1-overview-of-the-digestive-system")
    private val pancreas = HealthAtlasPlate(R.drawable.health_atlas_pancreas, "pancreas",
        R.string.health_atlas_view_pancreas, listOf(
            HealthAtlasMarker("pancreas", .62f, .30f), HealthAtlasMarker("pancreatic-duct", .57f, .41f),
            HealthAtlasMarker("duodenum", .12f, .48f)),
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-6-accessory-organs-in-digestion-the-liver-pancreas-and-gallbladder")
    val all = listOf(whole, heart, brain, lungs, liver, kidney, beta, erythrocyte, neuron, urinary, gut, pancreas)

    fun forId(id: String?): HealthAtlasPlate? = when (id) {
        null -> whole
        "heart", "cardio", "atria", "ventricles", "coronary-vessels" -> heart
        "brain", "cerebrum", "cerebellum", "brainstem" -> brain
        "lungs", "trachea", "bronchi" -> lungs
        "liver", "gallbladder" -> liver
        "kidneys", "renal-cortex", "renal-medulla", "renal-pelvis" -> kidney
        "urinary", "ureters", "bladder", "urethra" -> urinary
        "gut", "esophagus", "stomach", "small-intestine", "large-intestine", "appendix", "rectum" -> gut
        "pancreas", "pancreatic-duct", "duodenum" -> pancreas
        "cell-pancreatic-beta-cell" -> beta
        "cell-erythrocyte" -> erythrocyte
        "cell-neuron" -> neuron
        else -> null
    }
}
