package com.galaxyssi.chat

import android.content.Context

internal data class HealthAtlasMarker(val id: String, val x: Float, val y: Float) {
    init { require(x in 0f..1f && y in 0f..1f) }
}

internal data class HealthAtlasFeature(val marker: HealthAtlasMarker, val title: Int, val explanation: Int)

internal data class HealthAtlasPlate(val drawable: Int, val owner: String?, val viewLabel: Int,
    val markers: List<HealthAtlasMarker>, val source: String? = null, val viewKey: String? = null,
    val selectorLabel: Int? = null, val features: List<HealthAtlasFeature> = emptyList()) {
    init {
        val ids = markers.map { it.id } + features.map { it.marker.id }
        require(ids.distinct().size == ids.size)
    }
    val hasLabels get() = markers.isNotEmpty() || features.isNotEmpty()
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
        HealthAtlasMarker("ventricles", .61f, .84f)), HealthAtlasHeartSection.ANATOMY_SOURCE,
        "heart-exterior", R.string.health_atlas_cardiac_exterior)
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
    private val nephron = HealthAtlasPlate(R.drawable.health_atlas_nephron, "nephron",
        R.string.health_atlas_view_nephron, listOf(
            HealthAtlasMarker("glomerulus", .243f, .175f), HealthAtlasMarker("bowmans-capsule", .288f, .095f),
            HealthAtlasMarker("proximal-tubule", .45f, .275f), HealthAtlasMarker("nephron-loop", .494f, .902f),
            HealthAtlasMarker("distal-tubule", .716f, .184f), HealthAtlasMarker("collecting-ducts", .853f, .644f)),
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-4-microscopic-anatomy-of-the-kidney")
    private val alveolus = HealthAtlasPlate(R.drawable.health_atlas_alveolus, "alveoli",
        R.string.health_atlas_view_alveolus, listOf(
            HealthAtlasMarker("alveoli", .48f, .48f), HealthAtlasMarker("respiratory-membrane", .66f, .67f),
            HealthAtlasMarker("pulmonary-capillaries", .74f, .69f)), HealthAtlasGasExchange.SOURCE)
    private val eye = HealthAtlasPlate(R.drawable.health_atlas_eye_section, "eye",
        R.string.health_atlas_view_eye_section, listOf(
            HealthAtlasMarker("cornea", .138f, .39f), HealthAtlasMarker("lens", .30f, .49f),
            HealthAtlasMarker("retina", .663f, .669f)), HealthAtlasEyeOptics.ANATOMY_SOURCE)
    private val ear = HealthAtlasPlate(R.drawable.health_atlas_ear_section, "ear",
        R.string.health_atlas_view_ear_section, listOf(
            HealthAtlasMarker("external-ear", .129f, .354f), HealthAtlasMarker("middle-ear", .54f, .447f),
            HealthAtlasMarker("inner-ear", .686f, .509f), HealthAtlasMarker("cochlea", .79f, .668f),
            HealthAtlasMarker("vestibular-apparatus", .797f, .19f)), HealthAtlasMiddleEar.ANATOMY_SOURCE)
    val all = listOf(whole, heart, brain, lungs, liver, kidney, beta, erythrocyte, neuron, urinary, gut, pancreas, nephron, alveolus, eye, ear) +
        HealthAtlasSystemPlates.all + HealthAtlasMusculoskeletalPlates.all + HealthAtlasTissuePlates.all +
        HealthAtlasHeartSection.section + HealthAtlasImmunePlates.all + HealthAtlasCoreCellPlates.all

    fun viewsForId(id: String?): List<HealthAtlasPlate> = if (id == "heart") listOf(heart, HealthAtlasHeartSection.section)
        else HealthAtlasMusculoskeletalPlates.viewsForId(id).ifEmpty { listOfNotNull(defaultForId(id)) }

    fun forId(id: String?, viewKey: String? = null): HealthAtlasPlate? = viewsForId(id).let { views ->
        views.firstOrNull { it.viewKey == viewKey } ?: views.firstOrNull()
    }

    private fun defaultForId(id: String?): HealthAtlasPlate? = when (id) {
        null -> whole
        "heart", "atria", "ventricles", "coronary-vessels" -> heart
        "brain", "cerebrum", "cerebellum", "brainstem" -> brain
        "lungs", "trachea", "bronchi" -> lungs
        "alveoli", "respiratory-membrane", "pulmonary-capillaries" -> alveolus
        "eye", "cornea", "lens", "retina" -> eye
        "ear", "external-ear", "middle-ear", "inner-ear", "cochlea", "vestibular-apparatus" -> ear
        "liver", "gallbladder" -> liver
        "kidneys", "renal-cortex", "renal-medulla", "renal-pelvis" -> kidney
        "urinary", "ureters", "bladder", "urethra" -> urinary
        "gut", "esophagus", "stomach", "small-intestine", "large-intestine", "appendix", "rectum" -> gut
        "pancreas", "pancreatic-duct", "duodenum" -> pancreas
        "nephron", "glomerulus", "bowmans-capsule", "renal-tubules", "proximal-tubule", "nephron-loop",
        "distal-tubule", "collecting-ducts" -> nephron
        "cell-pancreatic-beta-cell" -> beta
        "cell-erythrocyte" -> erythrocyte
        "cell-neuron" -> neuron
        else -> HealthAtlasHeartSection.forId(id) ?: HealthAtlasTissuePlates.forId(id) ?:
            HealthAtlasImmunePlates.forId(id) ?: HealthAtlasCoreCellPlates.forId(id) ?: HealthAtlasSystemPlates.forId(id)
    }
}
