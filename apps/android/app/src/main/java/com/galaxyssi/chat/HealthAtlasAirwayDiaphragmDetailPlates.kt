package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasAirwayDiaphragmDetailPlates {
    private const val NASAL_ANATOMY =
        "https://www.ncbi.nlm.nih.gov/books/NBK544232/"
    private const val PHARYNX_ANATOMY =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-1-organs-and-structures-of-the-respiratory-system"
    private const val DIAPHRAGM_ANATOMY =
        "https://www.ncbi.nlm.nih.gov/books/NBK519558/"

    val all: List<HealthAtlasPlate> = listOf(
        plate(
            "nasal-cavity", drawable.health_atlas_nasal_cavity_lateral_wall, "nasal-cavity-lateral-wall",
            string.health_atlas_nasal_wall_selector, string.health_atlas_nasal_wall_view, NASAL_ANATOMY,
            listOf(marker("pharynx", 287, 169), marker("oral-cavity", 148, 202)),
            feature("nasal-cavity-vestibule", 76, 151,
                string.health_atlas_nasal_wall_vestibule, string.health_atlas_nasal_wall_vestibule_detail),
            feature("nasal-cavity-superior-concha", 205, 83,
                string.health_atlas_nasal_wall_superior, string.health_atlas_nasal_wall_superior_detail),
            feature("nasal-cavity-middle-concha", 161, 106,
                string.health_atlas_nasal_wall_middle, string.health_atlas_nasal_wall_middle_detail),
            feature("nasal-cavity-inferior-concha", 144, 139,
                string.health_atlas_nasal_wall_inferior, string.health_atlas_nasal_wall_inferior_detail),
            feature("nasal-cavity-choana", 252, 126,
                string.health_atlas_nasal_wall_choana, string.health_atlas_nasal_wall_choana_detail),
        ),
        plate(
            "pharynx", drawable.health_atlas_pharynx_sagittal_regions, "pharynx-sagittal-regions",
            string.health_atlas_pharynx_regions_selector, string.health_atlas_pharynx_regions_view, PHARYNX_ANATOMY,
            listOf(marker("nasal-cavity", 239, 78), marker("larynx", 201, 216), marker("esophagus", 144, 248)),
            feature("pharynx-nasopharynx", 153, 91,
                string.health_atlas_pharynx_regions_nasopharynx, string.health_atlas_pharynx_regions_nasopharynx_detail),
            feature("pharynx-oropharynx", 155, 146,
                string.health_atlas_pharynx_regions_oropharynx, string.health_atlas_pharynx_regions_oropharynx_detail),
            feature("pharynx-laryngopharynx", 147, 189,
                string.health_atlas_pharynx_regions_laryngopharynx,
                string.health_atlas_pharynx_regions_laryngopharynx_detail),
            feature("pharynx-soft-palate", 198, 111,
                string.health_atlas_pharynx_regions_soft_palate, string.health_atlas_pharynx_regions_soft_palate_detail),
            feature("pharynx-epiglottis", 182, 175,
                string.health_atlas_pharynx_regions_epiglottis, string.health_atlas_pharynx_regions_epiglottis_detail),
        ),
        plate(
            "diaphragm", drawable.health_atlas_diaphragm_inferior_surface, "diaphragm-inferior-surface",
            string.health_atlas_diaphragm_inferior_selector, string.health_atlas_diaphragm_inferior_view,
            DIAPHRAGM_ANATOMY,
            listOf(marker("esophagus", 215, 145), marker("aorta", 177, 251)),
            feature("diaphragm-central-tendon", 186, 85,
                string.health_atlas_diaphragm_inferior_tendon, string.health_atlas_diaphragm_inferior_tendon_detail),
            feature("diaphragm-costal-muscle", 280, 128,
                string.health_atlas_diaphragm_inferior_costal, string.health_atlas_diaphragm_inferior_costal_detail),
            feature("diaphragm-caval-opening", 124, 112,
                string.health_atlas_diaphragm_inferior_caval, string.health_atlas_diaphragm_inferior_caval_detail),
            feature("diaphragm-esophageal-hiatus", 192, 172,
                string.health_atlas_diaphragm_inferior_esophageal,
                string.health_atlas_diaphragm_inferior_esophageal_detail),
            feature("diaphragm-aortic-hiatus", 172, 218,
                string.health_atlas_diaphragm_inferior_aortic, string.health_atlas_diaphragm_inferior_aortic_detail),
            feature("diaphragm-right-crus", 149, 227,
                string.health_atlas_diaphragm_inferior_crus, string.health_atlas_diaphragm_inferior_crus_detail),
        ),
    )

    private fun plate(
        owner: String, art: Int, viewKey: String, selector: Int, caption: Int, source: String,
        neighbors: List<HealthAtlasMarker>, vararg features: HealthAtlasFeature,
    ) = HealthAtlasPlate(
        drawable = art,
        owner = owner,
        viewLabel = caption,
        markers = neighbors,
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
