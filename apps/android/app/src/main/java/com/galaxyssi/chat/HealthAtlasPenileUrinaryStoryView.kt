package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import com.galaxyssi.chat.HealthAtlasPenileUrinaryAssignment as Assignment
import com.galaxyssi.chat.R.string

internal class HealthAtlasPenileUrinaryStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val rim = 0xffa7828d
    private val lumenEdge = 0xff9a6845
    private val amber = 0xffc28233
    private val violetEdge = 0xff897395
    private val tissue = shade(94f, 267f, 0xffffe9dc, 0xffe8b6b3)
    private val corporal = shade(102f, 215f, 0xffeee5f4, 0xffc8b4d4)
    private val spongy = shade(191f, 277f, 0xffffdbc6, 0xffe6a49a)
    private val reservoir = shade(79f, 178f, 0xfffff3db, 0xfff0c88c)
    private val support = shade(166f, 213f, 0xffeadfee, 0xffc9b8ce)
    private val shaft = shade(180f, 243f, 0xffeee6f2, 0xffbfaccb)
    private val bulb = shade(203f, 262f, 0xffffe2ce, 0xffe6ab9e)
    private val section = Path().apply {
        moveTo(180f, 109f)
        cubicTo(143f, 87f, 85f, 93f, 67f, 128f)
        cubicTo(46f, 170f, 66f, 211f, 117f, 223f)
        cubicTo(124f, 254f, 148f, 275f, 180f, 276f)
        cubicTo(212f, 275f, 236f, 254f, 243f, 223f)
        cubicTo(294f, 211f, 314f, 170f, 293f, 128f)
        cubicTo(275f, 93f, 217f, 87f, 180f, 109f)
        close()
    }
    private val cavernosa = Path().apply {
        moveTo(169f, 128f)
        cubicTo(157f, 107f, 110f, 105f, 88f, 123f)
        cubicTo(68f, 141f, 67f, 175f, 85f, 192f)
        cubicTo(103f, 211f, 156f, 215f, 170f, 195f)
        cubicTo(177f, 183f, 178f, 141f, 169f, 128f)
        close()
    }
    private val weave = Path().apply {
        moveTo(92f, 151f); cubicTo(106f, 129f, 143f, 124f, 157f, 142f)
        moveTo(86f, 166f); cubicTo(103f, 155f, 129f, 145f, 163f, 156f)
        moveTo(94f, 179f); cubicTo(111f, 166f, 143f, 163f, 161f, 173f)
        moveTo(110f, 191f); quadTo(136f, 182f, 153f, 187f)
    }
    private val spongiosum = Path().apply {
        moveTo(180f, 197f)
        cubicTo(158f, 195f, 138f, 207f, 134f, 227f)
        cubicTo(127f, 247f, 151f, 266f, 180f, 266f)
        cubicTo(209f, 266f, 233f, 247f, 226f, 227f)
        cubicTo(222f, 207f, 202f, 195f, 180f, 197f)
        close()
    }
    private val bladder = Path().apply {
        moveTo(84f, 179f)
        cubicTo(75f, 167f, 50f, 166f, 44f, 145f)
        cubicTo(30f, 104f, 54f, 78f, 90f, 78f)
        cubicTo(125f, 78f, 145f, 106f, 132f, 145f)
        cubicTo(124f, 166f, 99f, 163f, 94f, 179f)
        close()
    }
    private val bladderInterior = Path().apply {
        moveTo(89f, 168f)
        cubicTo(76f, 155f, 60f, 157f, 53f, 139f)
        cubicTo(44f, 109f, 60f, 88f, 90f, 88f)
        cubicTo(119f, 88f, 133f, 110f, 123f, 139f)
        cubicTo(115f, 155f, 99f, 154f, 89f, 168f)
        close()
    }
    private val shaftSection = Path().apply {
        moveTo(132f, 207f)
        cubicTo(157f, 182f, 225f, 179f, 293f, 187f)
        cubicTo(308f, 189f, 316f, 198f, 309f, 207f)
        cubicTo(304f, 216f, 284f, 217f, 263f, 215f)
        cubicTo(207f, 210f, 161f, 224f, 142f, 231f)
        quadTo(125f, 228f, 132f, 207f)
        close()
    }
    private val spongySection = Path().apply {
        moveTo(105f, 213f)
        cubicTo(125f, 202f, 144f, 210f, 160f, 222f)
        cubicTo(185f, 236f, 226f, 223f, 264f, 222f)
        cubicTo(287f, 221f, 296f, 207f, 309f, 209f)
        cubicTo(324f, 210f, 332f, 219f, 330f, 228f)
        cubicTo(328f, 244f, 302f, 253f, 279f, 248f)
        cubicTo(248f, 244f, 198f, 260f, 158f, 254f)
        cubicTo(143f, 252f, 110f, 253f, 100f, 238f)
        quadTo(94f, 222f, 105f, 213f)
        close()
    }
    private val proximalRoute = Path().apply {
        moveTo(89f, 120f)
        cubicTo(89f, 147f, 88f, 179f, 90f, 197f)
        cubicTo(91f, 210f, 103f, 222f, 115f, 225f)
    }
    private val route = Path(proximalRoute).apply {
        cubicTo(136f, 225f, 146f, 235f, 168f, 239f)
        cubicTo(208f, 248f, 271f, 224f, 310f, 229f)
        quadTo(319f, 230f, 330f, 228f)
    }
    private val flow = track(route)
    private val spongyStart = track(proximalRoute).length
    private val trace = Path()

    init { tag = "atlas-function-penile-urinary-route-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            Assignment.CROSS_SECTION -> transverse(c, t)
            Assignment.PROXIMAL_ROUTE -> longitudinal(c, t, distal = false)
            Assignment.SPONGY_ROUTE -> longitudinal(c, t, distal = true)
        }
    }

    private fun transverse(c: Canvas, t: Float) {
        surface(c, section, tissue, rim)
        repeat(2) { side ->
            c.save()
            if (side == 1) c.scale(-1f, 1f, 180f, 0f)
            surface(c, cavernosa, corporal, violetEdge)
            stroke(c, weave, 0xffad97b9, 1.4f)
            c.restore()
        }
        surface(c, spongiosum, spongy, coral)
        oval(c, 164f, 225f, 196f, 239f, 0xffffebbd, lumenEdge)
        val glow = (90 + 108 * (0.5f + 0.5f * wave(t))).toLong()
        oval(c, 166f, 227f, 194f, 237f, (glow shl 24) or 0x00efb962, 0x00ffffff)

        label(c, string.health_atlas_penile_urinary_dorsal, 180f, 44f, 100f)
        label(c, string.health_atlas_penile_urinary_cavernosa, 180f, 76f, 155f)
        leader(c, 151f, 82f, 125f, 136f)
        leader(c, 209f, 82f, 235f, 136f)
        callout(c, string.health_atlas_penile_urinary_spongiosum, 86f, 310f, 148f, 148f, 242f, above = false)
        callout(c, string.health_atlas_penile_urinary_spongy, 273f, 330f, 148f, 182f, 232f, above = false)
    }

    private fun longitudinal(c: Canvas, t: Float, distal: Boolean) {
        oval(c, 59f, 166f, 122f, 205f, support, violetEdge)
        surface(c, shaftSection, shaft, violetEdge)
        surface(c, spongySection, bulb, coral)
        surface(c, bladder, tissue, rim)
        surface(c, bladderInterior, reservoir, 0xffd7a171)
        stroke(c, route, lumenEdge, 7f)
        stroke(c, route, 0xffffecbe, 4.5f)

        // A single fixed centerline encodes direction, not timing or changes in caliber.
        val start = if (distal) spongyStart else 0f
        val end = if (distal) flow.length else spongyStart
        val distance = start + t * (end - start + 24f)
        trace.rewind()
        if (flow.getSegment((distance - 24f).coerceAtLeast(start), distance.coerceAtMost(end), trace, true)) {
            stroke(c, trace, amber, 4.4f)
            stroke(c, trace, 0xffffd47f, 2.4f)
        }
        disc(c, 330f, 228f, 3f, 0xffffecbe, lumenEdge)

        if (distal) {
            arrow(c, 279f, 265f, 323f, 265f, teal)
            callout(c, string.health_atlas_penile_urinary_spongy, 204f, 132f, 144f, 196f, 240f)
            callout(c, string.health_atlas_penile_urinary_spongiosum, 147f, 309f, 149f, 154f, 248f, above = false)
            callout(c, string.health_atlas_penile_urinary_meatus, 281f, 161f, 138f, 330f, 228f)
        } else {
            callout(c, string.health_atlas_penile_urinary_bladder, 87f, 57f, 113f, 78f, 103f)
            callout(c, string.health_atlas_penile_urinary_prostatic, 204f, 102f, 145f, 90f, 185f)
            callout(c, string.health_atlas_penile_urinary_membranous, 95f, 290f, 162f, 95f, 210f, above = false)
            callout(c, string.health_atlas_penile_urinary_spongy, 267f, 311f, 142f, 251f, 233f, above = false)
        }
    }

    private fun surface(c: Canvas, path: Path, tone: Shader, edge: Long) {
        ink(cream); paint.shader = tone; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, edge, 1.45f)
    }

    private fun callout(c: Canvas, id: Int, x: Float, y: Float, max: Float, a: Float, b: Float, above: Boolean = true) {
        leader(c, x, y + if (above) 5f else -15f, a, b)
        label(c, id, x, y, max)
    }

    private fun leader(c: Canvas, x: Float, y: Float, a: Float, b: Float) {
        line(c, x, y, a, b, 0xff776873, 1.1f)
        disc(c, a, b, 2f, violet, cream)
    }
}
