package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasMaleDuctRouteDetailPlates {
    private const val PELVIC_ANATOMY =
        "https://medicine.uams.edu/neuroscience/education/medical-school-courses/human-structure-module/anatomy-tables/viscera-tables/visceral-structures-of-the-pelvis-and-perineum/"
    private const val VESICLE_HISTOLOGY = "https://histology.siu.edu/erg/semves.htm"
    private const val DUCT_MORPHOLOGY = "https://pubmed.ncbi.nlm.nih.gov/31894887/"

    val all: List<HealthAtlasPlate> = listOf(
        plate(
            "epididymis", drawable.health_atlas_epididymis_duct_detail, "epididymis-duct-detail",
            string.health_atlas_mdr_epi_selector, string.health_atlas_mdr_epi_view, PELVIC_ANATOMY,
            listOf(marker("testes", 112, 159), marker("vas-deferens", 268, 94)),
            feature("epididymis-efferent-ductules", 164, 83,
                string.health_atlas_mdr_epi_ductules, string.health_atlas_mdr_epi_ductules_detail),
            feature("epididymis-head", 212, 53,
                string.health_atlas_mdr_epi_head, string.health_atlas_mdr_epi_head_detail),
            feature("epididymis-body", 218, 139,
                string.health_atlas_mdr_epi_body, string.health_atlas_mdr_epi_body_detail),
            feature("epididymis-tail", 200, 224,
                string.health_atlas_mdr_epi_tail, string.health_atlas_mdr_epi_tail_detail),
        ),
        plate(
            "vas-deferens", drawable.health_atlas_vas_deferens_route_detail, "vas-deferens-route-detail",
            string.health_atlas_mdr_vas_selector, string.health_atlas_mdr_vas_view, PELVIC_ANATOMY,
            listOf(marker("epididymis", 91, 226), marker("seminal-vesicles", 277, 162),
                marker("ejaculatory-ducts", 216, 230)),
            feature("vas-deferens-spermatic-cord", 59, 155,
                string.health_atlas_mdr_vas_cord, string.health_atlas_mdr_vas_cord_detail),
            feature("vas-deferens-inguinal-canal", 96, 94,
                string.health_atlas_mdr_vas_canal, string.health_atlas_mdr_vas_canal_detail),
            feature("vas-deferens-pelvic-segment", 189, 122,
                string.health_atlas_mdr_vas_pelvic, string.health_atlas_mdr_vas_pelvic_detail),
            feature("vas-deferens-ampulla", 221, 181,
                string.health_atlas_mdr_vas_ampulla, string.health_atlas_mdr_vas_ampulla_detail),
        ),
        plate(
            "seminal-vesicles", drawable.health_atlas_seminal_vesicles_posterior_detail,
            "seminal-vesicles-posterior-detail",
            string.health_atlas_mdr_sv_selector, string.health_atlas_mdr_sv_view, VESICLE_HISTOLOGY,
            listOf(marker("bladder", 176, 54), marker("vas-deferens", 157, 145),
                marker("ejaculatory-ducts", 200, 215)),
            feature("seminal-vesicles-blind-end", 82, 89,
                string.health_atlas_mdr_sv_blind, string.health_atlas_mdr_sv_blind_detail),
            feature("seminal-vesicles-coiled-gland", 263, 111,
                string.health_atlas_mdr_sv_coil, string.health_atlas_mdr_sv_coil_detail),
            feature("seminal-vesicles-excretory-duct", 218, 174,
                string.health_atlas_mdr_sv_outlet, string.health_atlas_mdr_sv_outlet_detail),
        ),
        plate(
            "ejaculatory-ducts", drawable.health_atlas_ejaculatory_ducts_prostatic_cutaway,
            "ejaculatory-ducts-prostatic-cutaway",
            string.health_atlas_mdr_ej_selector, string.health_atlas_mdr_ej_view, DUCT_MORPHOLOGY,
            listOf(marker("vas-deferens", 146, 36), marker("seminal-vesicles", 256, 51),
                marker("prostate", 258, 168)),
            feature("ejaculatory-ducts-formation", 112, 83,
                string.health_atlas_mdr_ej_union, string.health_atlas_mdr_ej_union_detail),
            feature("ejaculatory-ducts-intraprostatic-course", 142, 144,
                string.health_atlas_mdr_ej_course, string.health_atlas_mdr_ej_course_detail),
            feature("ejaculatory-ducts-collicular-openings", 192, 197,
                string.health_atlas_mdr_ej_openings, string.health_atlas_mdr_ej_openings_detail),
            feature("ejaculatory-ducts-prostatic-urethra", 181, 227,
                string.health_atlas_mdr_ej_urethra, string.health_atlas_mdr_ej_urethra_detail),
        ),
    )

    private fun plate(
        owner: String, art: Int, viewKey: String, selector: Int, caption: Int, source: String,
        markers: List<HealthAtlasMarker>, vararg features: HealthAtlasFeature,
    ) = HealthAtlasPlate(
        drawable = art,
        owner = owner,
        viewLabel = caption,
        markers = markers,
        source = source,
        viewKey = viewKey,
        selectorLabel = selector,
        features = features.toList(),
        splitCallouts = true,
    )

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(marker(id, x, y), title, explanation)
}
