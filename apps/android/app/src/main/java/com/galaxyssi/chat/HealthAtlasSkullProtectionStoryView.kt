package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Path
import android.graphics.Shader
import androidx.core.graphics.PathParser

internal class HealthAtlasSkullProtectionStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val boneEdge = 0xff8b7264
    private val seam = 0xff876356
    private val guide = 0xff55717b
    private val fluidInk = 0xff398295
    private val cranialFill = shade(63f, 302f, 0xfffff6e6, 0xffd4ad95)
    private val cortexFill = shade(116f, 242f, 0xffefd1c6, 0xffbb7f83)
    private val mineralFill = shade(64f, 143f, 0xfffff1d8, 0xffdec3a7)
    private val diploeFill = shade(74f, 133f, 0xffdab38f, 0xffc49477)
    private val fluidFill = shade(90f, 181f, 0xffe0f4f2, 0xffa9cfd8)

    private val vault = path("M180 63 C226 60 259 91 269 140 C282 193 265 240 237 274 C221 293 202 300 180 301 C158 300 139 293 123 274 C95 240 78 193 91 140 C101 91 134 60 180 63 Z")
    private val frontal = path("M91 140 C101 91 134 60 180 63 C226 60 259 91 269 140 Q232 126 180 129 Q128 126 91 140 Z")
    private val occipital = path("M105 248 Q140 239 180 229 Q220 239 255 248 C236 280 216 300 180 301 C144 300 124 280 105 248 Z")
    private val vaultLight = path("M109 184 C110 115 140 82 172 78 M192 78 C218 83 236 99 246 127 M116 207 Q125 242 146 269 M244 207 Q236 242 215 268")
    private val coronal = path("M91 140 l8 -4 6 1 6 -5 7 2 5 -4 8 1 7 -3 8 2 8 -3 7 2 7 -3 6 3 6 0 7 -2 6 2 7 -2 7 3 8 -2 7 3 8 -1 6 4 7 -2 6 5 7 -1 13 4")
    private val sagittal = path("M180 129 l-2 7 4 5 -4 6 3 6 -3 6 4 6 -4 7 3 5 -3 7 4 5 -4 7 3 5 -3 6 4 6 -3 6 1 10")
    private val lambdoid = path("M105 248 l8 -3 5 1 5 -5 6 2 6 -5 6 1 6 -4 6 1 6 -5 6 2 6 -5 9 1 9 -1 6 5 6 -2 6 5 6 -1 6 4 6 -1 6 5 6 -2 5 5 5 -1 8 3")
    private val sutures = listOf(coronal, sagittal, lambdoid)
    private val sutureTracks = sutures.map(::track)
    private val trace = Path()
    private val locator = Path()
    private val dash = DashPathEffect(floatArrayOf(4f, 4f), 0f)

    // The section uses the same 360 x 280 coordinates as the structure plate.
    private val tables = path("M32 111 Q180 29 328 111 L328 139 Q180 57 32 139 Z")
    private val diploe = path("M32 119 Q180 37 328 119 L328 131 Q180 49 32 131 Z")
    private val lattice = path("M43 117 l7 6 7 -13 7 6 6 -12 8 7 7 -12 6 7 8 -11 7 7 8 -11 8 7 7 -11 8 8 7 -10 7 8 8 -10 8 8 7 -9 8 8 8 -8 7 9 8 -8 8 10 7 -8 7 10 8 -8 7 11 8 -7 8 11 7 -7 8 11 6 -7 7 12 8 -7 6 12 7 -6 7 13 7 -6")
    private val dura = path("M32 139 Q180 57 328 139 L328 146 Q180 64 32 146 Z")
    private val fluid = path("M32 146 Q180 64 328 146 L328 208 Q180 251 32 208 Z")
    private val arachnoid = path("M32 146 Q180 64 328 146")
    private val brain = path("M32 169 C49 156 55 163 60 161 C72 157 68 140 85 137 C101 134 102 150 109 145 C117 140 109 128 127 124 C149 119 146 139 154 139 C164 138 151 119 175 116 C195 113 193 134 202 135 C213 134 201 120 220 123 C238 126 232 143 241 144 C249 143 249 131 264 137 C283 144 271 154 286 159 C292 162 295 153 309 158 Q322 163 328 171 L328 210 Q180 260 32 210 Z")
    private val pia = path("M32 169 C49 156 55 163 60 161 C72 157 68 140 85 137 C101 134 102 150 109 145 C117 140 109 128 127 124 C149 119 146 139 154 139 C164 138 151 119 175 116 C195 113 193 134 202 135 C213 134 201 120 220 123 C238 126 232 143 241 144 C249 143 249 131 264 137 C283 144 271 154 286 159 C292 162 295 153 309 158 Q322 163 328 171")
    private val gyri = path("M43 184 Q63 178 70 193 T99 191 M88 149 Q76 165 96 170 T115 195 M133 139 Q121 153 138 161 T149 198 M175 132 Q166 146 179 154 T188 193 M219 141 Q226 156 210 164 T211 195 M252 149 Q263 169 244 172 T237 207 M283 174 Q272 185 291 189 T306 207 M66 209 Q90 201 105 220 M171 220 Q186 204 206 216")
    private val fluidTrack = track(path("M37 153 Q180 70 323 153"))

    init { tag = "atlas-function-skull-protection-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            HealthAtlasAxialProtectionAssignment.Skull.ORIENTATION -> top(c, t, locate = true)
            HealthAtlasAxialProtectionAssignment.Skull.SUTURES -> top(c, t, locate = false)
            HealthAtlasAxialProtectionAssignment.Skull.BONE -> section(c, t, membranes = false)
            else -> section(c, t, membranes = true)
        }
    }

    private fun top(c: Canvas, t: Float, locate: Boolean) {
        wash(c, vault, cranialFill, boneEdge)
        c.save()
        c.clipPath(vault)
        ink(0x68fff5d9); c.drawPath(frontal, paint)
        ink(0x78be8f7d); c.drawPath(occipital, paint)
        c.restore()
        stroke(c, vaultLight, 0x7afff9ec, 2.6f)
        sutures.forEach { stroke(c, it, seam, 1.55f) }
        if (locate) {
            // This translating line is a locator for the enlarged layer view, not motion of bone.
            val y = 165f + t * 35f
            locator.rewind()
            locator.moveTo(95f, y + 5f)
            locator.quadTo(180f, y - 12f, 265f, y + 5f)
            paint.pathEffect = dash
            stroke(c, locator, fluidInk, 1.6f)
            paint.pathEffect = null
            callout(c, R.string.health_atlas_skull_protection_art_vault_section, 69f, 295f, 114f, 100f, y + 4f, 276f)
        } else {
            val progress = t * sutureTracks.size
            sutureTracks.forEachIndexed { i, track ->
                trace.rewind()
                if (track.getSegment(0f, (progress - i).coerceIn(0f, 1f) * track.length, trace, true)) {
                    stroke(c, trace, 0x7ffaf1da, 5f)
                    stroke(c, trace, seam, 2.5f)
                }
            }
            callout(c, R.string.health_atlas_skull_protection_art_coronal, 66f, 91f, 120f, 123f, 130f, 97f)
            callout(c, R.string.health_atlas_skull_protection_art_sagittal, 286f, 182f, 122f, 180f, 179f, 187f)
            callout(c, R.string.health_atlas_skull_protection_art_lambdoid, 286f, 292f, 125f, 215f, 236f, 275f)
        }
        label(c, R.string.health_atlas_skull_protection_art_anterior, 180f, 44f, 134f)
        label(c, R.string.health_atlas_skull_protection_art_posterior, 180f, 328f, 134f)
    }

    private fun section(c: Canvas, t: Float, membranes: Boolean) {
        c.save()
        c.translate(0f, 40f)
        wash(c, fluid, fluidFill, 0xff7aa9b4)
        wash(c, brain, cortexFill, 0xff8b6570)
        stroke(c, gyri, 0xffb28086, 1.5f)
        stroke(c, pia, 0xff94606e, 2f)
        wash(c, dura, shadeDura, 0xff827c97)
        stroke(c, arachnoid, 0xff5f7a93, 1.75f)
        wash(c, tables, mineralFill, boneEdge)
        wash(c, diploe, diploeFill, 0xffa9856e)
        c.save()
        c.clipPath(diploe)
        stroke(c, lattice, 0xfff2d3ad, 1.6f)
        if (!membranes) stroke(c, lattice, (70L + (90f * t).toLong()) shl 24 or 0xffedc5, 2.8f)
        c.restore()
        if (membranes) {
            // Tracers stay in the subarachnoid space and are illustrative, not a flow map.
            c.save()
            c.clipPath(fluid)
            c.clipOutPath(brain)
            for (i in 0..4) {
                at(fluidTrack, (t * .48f + i * .2f) % 1f) { x, y ->
                    disc(c, x, y, 2f, 0xbb398295)
                }
            }
            c.restore()
        }
        c.restore()
        if (membranes) {
            callout(c, R.string.health_atlas_skull_protection_art_dura, 65f, 66f, 111f, 64f, 167f, 72f)
            callout(c, R.string.health_atlas_skull_protection_art_arachnoid, 284f, 66f, 135f, 279f, 163f, 72f)
            callout(c, R.string.health_atlas_skull_protection_art_pia, 65f, 310f, 110f, 67f, 195f, 293f)
            callout(c, R.string.health_atlas_skull_protection_art_csf, 282f, 310f, 143f, 288f, 176f, 293f)
        } else {
            callout(c, R.string.health_atlas_skull_protection_art_outer, 64f, 65f, 122f, 100f, 126f, 72f)
            callout(c, R.string.health_atlas_skull_protection_art_diploe, 180f, 65f, 104f, 180f, 121f, 72f)
            callout(c, R.string.health_atlas_skull_protection_art_inner, 296f, 65f, 122f, 254f, 145f, 72f)
            callout(c, R.string.health_atlas_skull_protection_art_brain, 180f, 310f, 132f, 180f, 207f, 293f)
        }
    }

    private val shadeDura = shade(101f, 148f, 0xffd4c5d6, 0xffb0a0b7)

    private fun callout(c: Canvas, id: Int, x: Float, y: Float, w: Float, tx: Float, ty: Float, startY: Float) {
        line(c, x, startY, tx, ty, guide, 1f)
        disc(c, tx, ty, 2.35f, 0xfff7f7ec, guide)
        label(c, id, x, y, w)
    }

    private fun wash(c: Canvas, path: Path, fill: Shader, edge: Long) {
        ink(cream)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, edge, 1.1f)
    }

    private fun path(data: String) = PathParser.createPathFromPathData(data)
}
