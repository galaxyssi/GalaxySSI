package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasNephronStructureDetailPlates {
    val all: List<HealthAtlasPlate> = listOf(
        HealthAtlasPlate(
            drawable = drawable.health_atlas_glomerulus_tuft_cutaway,
            owner = "glomerulus",
            viewLabel = string.health_atlas_glomerulus_tuft_view,
            markers = listOf(marker("cell-podocyte", 239, 77), marker("bowmans-capsule", 285, 183)),
            source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-4-microscopic-anatomy-of-the-kidney",
            viewKey = "glomerulus-tuft-cutaway",
            selectorLabel = string.health_atlas_glomerulus_tuft_selector,
            features = listOf(
                feature("glomerulus-afferent", 77, 95, string.health_atlas_glomerulus_afferent,
                    string.health_atlas_glomerulus_afferent_detail),
                feature("glomerulus-efferent", 77, 143, string.health_atlas_glomerulus_efferent,
                    string.health_atlas_glomerulus_efferent_detail),
                feature("glomerulus-capillary-loops", 181, 187, string.health_atlas_glomerulus_loops,
                    string.health_atlas_glomerulus_loops_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_bowmans_capsule_poles_cutaway,
            owner = "bowmans-capsule",
            viewLabel = string.health_atlas_bowmans_capsule_poles_view,
            markers = listOf(marker("glomerulus", 127, 116), marker("proximal-tubule", 301, 180)),
            source = "https://histologylab.ctl.columbia.edu/lab12/kidney/",
            viewKey = "bowmans-capsule-poles-cutaway",
            selectorLabel = string.health_atlas_bowmans_capsule_poles_selector,
            features = listOf(
                feature("bowmans-capsule-parietal", 130, 211, string.health_atlas_bowmans_capsule_parietal,
                    string.health_atlas_bowmans_capsule_parietal_detail),
                feature("bowmans-capsule-visceral", 196, 79, string.health_atlas_bowmans_capsule_visceral,
                    string.health_atlas_bowmans_capsule_visceral_detail),
                feature("bowmans-capsule-space", 247, 122, string.health_atlas_bowmans_capsule_space,
                    string.health_atlas_bowmans_capsule_space_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_proximal_tubule_brush_border_cutaway,
            owner = "proximal-tubule",
            viewLabel = string.health_atlas_proximal_tubule_brush_view,
            markers = listOf(marker("bowmans-capsule", 56, 102), marker("nephron-loop", 299, 241)),
            source = "https://histology.oit.duke.edu/NormalBody/Urinary/Urinary.html",
            viewKey = "proximal-tubule-brush-border-cutaway",
            selectorLabel = string.health_atlas_proximal_tubule_brush_selector,
            features = listOf(
                feature("proximal-tubule-cortical-coil", 201, 60, string.health_atlas_proximal_tubule_coil,
                    string.health_atlas_proximal_tubule_coil_detail),
                feature("proximal-tubule-cuboidal-wall", 153, 174, string.health_atlas_proximal_tubule_cuboidal,
                    string.health_atlas_proximal_tubule_cuboidal_detail),
                feature("proximal-tubule-apical-brush", 204, 143, string.health_atlas_proximal_tubule_microvilli,
                    string.health_atlas_proximal_tubule_microvilli_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_nephron_loop_limb_cutaway,
            owner = "nephron-loop",
            viewLabel = string.health_atlas_nephron_loop_limb_view,
            markers = listOf(marker("proximal-tubule", 106, 67), marker("distal-tubule", 291, 49)),
            source = "https://histopathology.pennstatehealth.net/slideview/MH-141b-kidney/16-slide-1.html?page=1",
            viewKey = "nephron-loop-limb-cutaway",
            selectorLabel = string.health_atlas_nephron_loop_limb_selector,
            features = listOf(
                feature("nephron-loop-thin-descending", 110, 144, string.health_atlas_nephron_loop_thin_descending,
                    string.health_atlas_nephron_loop_thin_descending_detail),
                feature("nephron-loop-thin-ascending", 201, 229, string.health_atlas_nephron_loop_thin_ascending,
                    string.health_atlas_nephron_loop_thin_ascending_detail),
                feature("nephron-loop-thick-ascending", 235, 105, string.health_atlas_nephron_loop_thick_ascending,
                    string.health_atlas_nephron_loop_thick_ascending_detail),
            ),
            splitCallouts = true,
        ),
    )

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(marker(id, x, y), title, explanation)
}
