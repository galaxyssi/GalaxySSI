package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasUterocervicalPlates {
    const val UTERUS_VIEW_KEY = "uterine-wall-cutaway"
    const val CERVIX_VIEW_KEY = "cervical-canal-cutaway"

    val uterus = HealthAtlasPlate(
        drawable.health_atlas_uterocervical_uterine_wall, HealthAtlasUterocervicalAssignment.UTERUS,
        string.health_atlas_uterocervical_uterus_view, emptyList(), HealthAtlasUterocervicalAssignment.ANATOMY_SOURCE,
        viewKey = UTERUS_VIEW_KEY, splitCallouts = true, features = listOf(
            feature("uterine-perimetrium", 105, 60, string.health_atlas_uterocervical_perimetrium,
                string.health_atlas_uterocervical_perimetrium_detail),
            feature("uterine-myometrium", 238, 124, string.health_atlas_uterocervical_myometrium,
                string.health_atlas_uterocervical_myometrium_detail),
            feature("uterine-endometrium", 138, 115, string.health_atlas_uterocervical_endometrium,
                string.health_atlas_uterocervical_endometrium_detail),
        ),
    )
    val cervix = HealthAtlasPlate(
        drawable.health_atlas_uterocervical_cervical_canal, HealthAtlasUterocervicalAssignment.CERVIX,
        string.health_atlas_uterocervical_cervix_view, emptyList(), HealthAtlasUterocervicalAssignment.CERVIX_SOURCE,
        viewKey = CERVIX_VIEW_KEY, splitCallouts = true, features = listOf(
            feature("cervical-internal-os", 175, 80, string.health_atlas_uterocervical_internal_os,
                string.health_atlas_uterocervical_internal_os_detail),
            feature("cervical-canal", 183, 140, string.health_atlas_uterocervical_canal,
                string.health_atlas_uterocervical_canal_detail),
            feature("cervical-external-os", 181, 202, string.health_atlas_uterocervical_external_os,
                string.health_atlas_uterocervical_external_os_detail),
        ),
    )
    val all = listOf(uterus, cervix)

    fun forId(id: String?) = when (id) {
        HealthAtlasUterocervicalAssignment.UTERUS -> uterus
        HealthAtlasUterocervicalAssignment.CERVIX -> cervix
        else -> null
    }

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)
}
