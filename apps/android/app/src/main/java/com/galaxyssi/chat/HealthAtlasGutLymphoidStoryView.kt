package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Shader
import android.graphics.drawable.Drawable

internal object HealthAtlasGutLymphoidMotion {
    fun appendixFocus(t: Float) = ease(t, 0f, .48f)
    fun ileumFocus(t: Float) = ease(t, .38f, .94f)
    fun appendixScale(t: Float) = 1f + .14f * ease(t, .04f, .68f)
    fun ileumScale(t: Float) = 1f + .13f * ease(t, .28f, .94f)
    fun uptake(t: Float) = ease(t, .05f, .94f)
    fun contact(t: Float) = ease(t, .10f, .76f)
    fun display(t: Float) = ease(t, .36f, .64f)
    fun iga(t: Float, index: Int) = ease(t, .03f + index * .23f, .70f + index * .14f)
    fun igaDistance(progress: Float, index: Int) = progress * (1f - .095f * index)

    private fun ease(t: Float, start: Float, end: Float): Float {
        val p = ((HealthAtlasFunctionStory.safePhase(t) - start) / (end - start)).coerceIn(0f, 1f)
        return p * p * (3f - 2f * p)
    }
}

internal class HealthAtlasGutLymphoidStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.GUT_LYMPHOID_SAMPLING) {
    private val locator = plate(R.drawable.health_atlas_gut_lymphoid_locator)
    private val comparison = plate(R.drawable.health_atlas_gut_lymphoid_comparison)
    private val contour = 0xff976c78
    private val guide = 0xff526e75
    private val darkPlum = 0xff895d84
    private val amber = 0xffa77336
    private val rose = 0xffeab7ad
    private val inner = shade(124f, 305f, 0xfff5dbc8, 0xffd8a9b8)
    private val follicleShade = shade(199f, 303f, 0xffebcedd, 0xffbd91b1)
    private val cellShade = shade(178f, 255f, 0xffebd4e8, 0xffc4a0cb)
    private val layer = shade(118f, 166f, 0xfff7d5bb, 0xffe3a7a0)
    private val mucus = shade(92f, 123f, 0xffe5f1e8, 0xffafd4cf)

    private val dome = shape { domeRim() }
    private val domeTrack = track(dome)
    private val mucosa = shape {
        domeRim()
        cubicTo(334f, 185f, 337f, 262f, 315f, 287f)
        cubicTo(276f, 316f, 81f, 316f, 44f, 290f)
        cubicTo(23f, 270f, 25f, 199f, 30f, 151f)
        close()
    }
    private val deepEdge = shape {
        moveTo(41f, 271f)
        cubicTo(87f, 302f, 278f, 297f, 319f, 269f)
    }
    private val domeEpithelium = shape {
        domeRim()
        lineTo(330f, 166f)
        quadTo(310f, 168f, 301f, 139f)
        quadTo(298f, 129f, 296f, 142f)
        quadTo(292f, 170f, 273f, 166f)
        quadTo(259f, 163f, 253f, 142f)
        quadTo(251f, 133f, 249f, 148f)
        cubicTo(243f, 178f, 225f, 182f, 203f, 176f)
        cubicTo(178f, 167f, 156f, 166f, 132f, 174f)
        quadTo(104f, 183f, 103f, 143f)
        quadTo(102f, 132f, 99f, 147f)
        quadTo(93f, 173f, 73f, 170f)
        quadTo(63f, 168f, 59f, 142f)
        quadTo(58f, 128f, 56f, 145f)
        quadTo(52f, 171f, 29f, 175f)
        close()
    }
    private val mCell = shape {
        moveTo(158f, 133f)
        cubicTo(165f, 131f, 175f, 131f, 182f, 132f)
        cubicTo(181f, 144f, 183f, 170f, 187f, 178f)
        cubicTo(179f, 181f, 180f, 162f, 170f, 162f)
        cubicTo(162f, 164f, 164f, 181f, 154f, 178f)
        cubicTo(159f, 168f, 157f, 152f, 158f, 133f)
        close()
    }
    private val sampleTrack = track(shape {
        moveTo(92f, 94f)
        cubicTo(124f, 92f, 153f, 101f, 168f, 129f)
        cubicTo(172f, 143f, 169f, 150f, 170f, 162f)
        quadTo(172f, 178f, 173f, 195f)
    })
    private val surfaceTissue = shape {
        surfaceRim()
        cubicTo(335f, 171f, 332f, 254f, 305f, 276f)
        cubicTo(264f, 307f, 99f, 305f, 54f, 287f)
        cubicTo(28f, 270f, 26f, 176f, 30f, 130f)
        close()
    }
    private val surfaceEpithelium = shape {
        surfaceRim()
        lineTo(330f, 159f)
        cubicTo(289f, 147f, 247f, 163f, 206f, 163f)
        cubicTo(155f, 168f, 78f, 154f, 31f, 167f)
        close()
    }
    private val apicalEdge = track(shape { surfaceRim() })
    private val basalEdge = track(shape {
        moveTo(31f, 167f)
        cubicTo(78f, 154f, 155f, 168f, 206f, 163f)
        cubicTo(247f, 163f, 289f, 147f, 330f, 159f)
    })
    private val mucusBand = shape {
        surfaceRim()
        cubicTo(307f, 104f, 296f, 99f, 269f, 102f)
        cubicTo(205f, 107f, 189f, 113f, 134f, 106f)
        cubicTo(89f, 101f, 52f, 104f, 30f, 120f)
        close()
    }
    private val igaTrack = track(shape {
        moveTo(123f, 237f)
        cubicTo(145f, 225f, 183f, 205f, 208f, 178f)
        cubicTo(219f, 163f, 213f, 143f, 215f, 125f)
        cubicTo(217f, 108f, 254f, 117f, 287f, 108f)
    })
    private val processes = Path()

    init { tag = "atlas-function-gut-lymphoid-sampling-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            0 -> locate(c, t)
            1 -> compare(c, t)
            2 -> sampling(c, t)
            3 -> recognition(c, t)
            else -> defense(c, t)
        }
    }

    private fun locate(c: Canvas, t: Float) {
        locator.draw(c)
        locatorFocus(c, 142f, 248f, 27f, 32f, darkPlum, HealthAtlasGutLymphoidMotion.appendixFocus(t))
        locatorFocus(c, 251f, 165f, 36f, 26f, teal, HealthAtlasGutLymphoidMotion.ileumFocus(t))
        label(c, R.string.health_atlas_gut_lymphoid_story_cecum, 50f, 95f, 83f)
        leader(c, 50f, 102f, 55f, 132f, 109f, 155f)
        label(c, R.string.health_atlas_gut_lymphoid_story_ileum, 269f, 89f, 145f)
        leader(c, 269f, 96f, 274f, 116f, 261f, 147f)
        label(c, R.string.health_atlas_gut_lymphoid_story_appendix, 232f, 307f, 146f)
        leader(c, 232f, 294f, 205f, 270f, 151f, 267f)
    }

    private fun compare(c: Canvas, t: Float) {
        val left = HealthAtlasGutLymphoidMotion.appendixScale(t)
        val right = HealthAtlasGutLymphoidMotion.ileumScale(t)
        zoom(c, 0f, 175f, 92f, 183f, left)
        zoom(c, 175f, 360f, 266f, 183f, right)
        label(c, R.string.health_atlas_gut_lymphoid_story_appendix_wall, 93f, 84f, 154f)
        label(c, R.string.health_atlas_gut_lymphoid_story_ileal_wall, 265f, 84f, 162f)
        label(c, R.string.health_atlas_gut_lymphoid_story_appendix_lumen, 92f, 111f, 145f)
        leader(c, 92f, 118f, 92f, 128f, 92f, 183f + (185f - 183f) * left)
        label(c, R.string.health_atlas_gut_lymphoid_story_villi, 293f, 111f, 114f)
        leader(c, 293f, 118f, 305f, 128f, 266f + (308f - 266f) * right, 183f + (154f - 183f) * right)
        label(c, R.string.health_atlas_gut_lymphoid_story_follicles, 91f, 295f, 152f)
        leader(c, 91f, 281f, 85f, 261f, 92f + (69f - 92f) * left, 183f + (217f - 183f) * left)
        label(c, R.string.health_atlas_gut_lymphoid_story_peyer, 265f, 295f, 159f)
        leader(c, 265f, 281f, 265f, 263f, 266f + (266f - 266f) * right, 183f + (206f - 183f) * right)
    }

    private fun sampling(c: Canvas, t: Float) {
        samplingAnatomy(c)
        dendritic(c, 182f)
        val progress = HealthAtlasGutLymphoidMotion.uptake(t)
        at(sampleTrack, progress) { x, y ->
            if (y in 135f..167f) disc(c, x, y, 8f, 0xfffae2b1, amber)
            protein(c, x, y, 4.5f)
        }
        protein(c, 44f, 60f, 4.5f)
        label(c, R.string.health_atlas_gut_lymphoid_story_food_protein, 104f, 64f, 104f)
        label(c, R.string.health_atlas_gut_lymphoid_story_dendritic, 158f, 338f, 155f)
        leader(c, 158f, 324f, 157f, 281f, 161f, 233f)
    }

    private fun recognition(c: Canvas, t: Float) {
        samplingAnatomy(c)
        val approach = HealthAtlasGutLymphoidMotion.contact(t)
        val tx = 267f - 41f * approach
        val ty = 258f - 34f * approach
        val tip = 182f + 24f * approach
        dendritic(c, tip)
        oval(c, tx - 20f, ty - 17f, tx + 20f, ty + 17f, 0xffb5d8ca, teal)
        oval(c, tx - 9f, ty - 10f, tx + 11f, ty + 10f, 0xff79aaa1, teal)
        disc(c, tx - 12f, ty - 8f, 2f, cream)
        val display = HealthAtlasGutLymphoidMotion.display(t)
        if (display > 0f) {
            val y = 222f + 8f * (1f - approach)
            line(c, tip - 2f, y + 3f, tip + 2f, y + 3f, darkPlum, 1.8f)
            protein(c, tip + 1f, y, 2.7f * display)
        }
        label(c, R.string.health_atlas_gut_lymphoid_story_dendritic, 104f, 338f, 145f)
        leader(c, 104f, 324f, 104f, 284f, 154f, 236f)
        label(c, R.string.health_atlas_gut_lymphoid_story_t_cell, 262f, 338f, 114f)
        leader(c, 262f, 324f, 261f, 296f, tx + 4f, ty + 15f)
    }

    private fun defense(c: Canvas, t: Float) {
        fill(c, surfaceTissue, inner, contour)
        fill(c, mucusBand, mucus, 0xffa4c6c0)
        fill(c, surfaceEpithelium, layer, contour)
        for (i in 1 until 17) {
            val f = i / 17f
            at(apicalEdge, f) { x, y ->
                at(basalEdge, f) { bx, by ->
                    line(c, x, y, bx, by, 0xffc59a98, .9f)
                    oval(c, bx - 13f, by - 14f, bx - 7f, by - 5f, 0xffbd8499, 0xffbf8698)
                }
            }
        }
        oval(c, 80f, 222f, 128f, 267f, cellShade, darkPlum)
        oval(c, 86f, 239f, 104f, 259f, 0xffac84b5, darkPlum)
        line(c, 106f, 232f, 116f, 235f, cream, 2.4f)
        line(c, 108f, 242f, 119f, 243f, cream, 1.8f)
        line(c, 210f, 163f, 215f, 168f, teal, 1.6f)
        line(c, 215f, 168f, 221f, 162f, teal, 1.6f)
        for (i in 0..2) {
            val progress = HealthAtlasGutLymphoidMotion.iga(t, i)
            if (i == 0 || progress > 0f) {
                at(igaTrack, HealthAtlasGutLymphoidMotion.igaDistance(progress, i)) { x, y ->
                    antibody(c, x, y, y < 122f)
                }
            }
        }
        label(c, R.string.health_atlas_gut_lymphoid_story_secretory_iga, 260f, 67f, 166f)
        leader(c, 260f, 75f, 274f, 87f, 282f, 102f)
        label(c, R.string.health_atlas_gut_lymphoid_story_epithelial_transport, 258f, 217f, 144f)
        leader(c, 258f, 203f, 246f, 184f, 214f, 150f)
        label(c, R.string.health_atlas_gut_lymphoid_story_plasma_cell, 112f, 336f, 155f)
        leader(c, 112f, 322f, 113f, 296f, 109f, 260f)
    }

    private fun samplingAnatomy(c: Canvas) {
        fill(c, mucosa, inner, contour)
        stroke(c, deepEdge, 0xffc58fa4, 2f)
        follicle(c, 91f, 247f, 37f, 39f)
        follicle(c, 288f, 249f, 31f, 39f)
        fill(c, domeEpithelium, layer, contour)
        stroke(c, dome, rose, 3.5f)
        for (i in 1 until 46) {
            at(domeTrack, i / 46f) { x, y ->
                if (x !in 152f..187f) disc(c, x, y + 4f, 1.35f, darkPlum)
            }
        }
        ink(0xffb9d6cf); c.drawPath(mCell, paint)
        stroke(c, mCell, teal, 1.35f)
        oval(c, 158f, 150f, 165f, 160f, 0xff84aba5, teal)
        line(c, 162f, 129f, 165f, 128f, teal, 1.15f)
        line(c, 170f, 128f, 173f, 128f, teal, 1.15f)
        line(c, 178f, 129f, 181f, 130f, teal, 1.15f)
        label(c, R.string.health_atlas_gut_lymphoid_story_m_cell, 259f, 91f, 113f)
        leader(c, 247f, 97f, 215f, 105f, 181f, 142f)
    }

    private fun dendritic(c: Canvas, tip: Float) {
        processes.rewind()
        processes.moveTo(147f, 226f); processes.quadTo(137f, 219f, 131f, 209f)
        processes.moveTo(156f, 214f); processes.quadTo(148f, 203f, 153f, 195f)
        processes.moveTo(165f, 213f); processes.quadTo(172f, 201f, 173f, 191f)
        processes.moveTo(176f, 224f); processes.quadTo(183f, 222f, tip, 225f)
        processes.moveTo(171f, 237f); processes.quadTo(178f, 245f, 183f, 247f)
        processes.moveTo(154f, 237f); processes.quadTo(151f, 246f, 141f, 252f)
        stroke(c, processes, darkPlum, 5f)
        stroke(c, processes, 0xffddbedc, 3f)
        oval(c, 141f, 211f, 181f, 243f, cellShade, darkPlum)
        oval(c, 149f, 219f, 167f, 233f, 0xffac84b5, darkPlum)
        disc(c, 169f, 216f, 2f, cream)
    }

    private fun follicle(c: Canvas, x: Float, y: Float, rx: Float, ry: Float) {
        oval(c, x - rx, y - ry, x + rx, y + ry, follicleShade, 0xffa67c9b)
        oval(c, x - rx * .60f, y - ry * .66f, x + rx * .50f, y + ry * .35f, 0xffefdae0, 0xffc9a0b4)
        for (i in 0..9) {
            val dx = (i % 5 - 2) * rx * .32f
            val dy = (i / 5 - .5f) * ry * .98f + (i % 3 - 1) * 4f
            disc(c, x + dx, y + dy, 1.3f, 0xffae839f)
        }
    }

    private fun antibody(c: Canvas, x: Float, y: Float, secreted: Boolean) {
        val color = if (secreted) teal else blue
        line(c, x - 4f, y - 2f, x + 4f, y + 2f, color, 1.8f)
        line(c, x - 4f, y - 2f, x - 8f, y - 5f, color, 1.9f)
        line(c, x - 8f, y - 5f, x - 11f, y - 4f, color, 1.9f)
        line(c, x - 8f, y - 5f, x - 8f, y - 9f, color, 1.9f)
        line(c, x + 4f, y + 2f, x + 8f, y + 5f, color, 1.9f)
        line(c, x + 8f, y + 5f, x + 11f, y + 4f, color, 1.9f)
        line(c, x + 8f, y + 5f, x + 8f, y + 9f, color, 1.9f)
        disc(c, x, y, 2f, if (secreted) 0xffd9ead8 else cream, color)
    }

    private fun protein(c: Canvas, x: Float, y: Float, r: Float) {
        c.save()
        c.rotate(-25f, x, y)
        oval(c, x - r, y - r * .67f, x + r, y + r * .67f, 0xffedbd73, amber)
        c.restore()
    }

    private fun locatorFocus(c: Canvas, x: Float, y: Float, rx: Float, ry: Float, color: Long, t: Float) {
        ink(color, 2f)
        paint.alpha = (199f - 65f * t).toInt()
        val scale = 1.18f - .18f * t
        c.drawArc(x - rx * scale, y - ry * scale, x + rx * scale, y + ry * scale,
            -100f, 52f + 296f * t, false, paint)
    }

    private fun zoom(c: Canvas, left: Float, right: Float, x: Float, y: Float, amount: Float) {
        c.save()
        c.clipRect(left, 119f, right, 268f)
        c.scale(amount, amount, x, y)
        comparison.draw(c)
        c.restore()
    }

    private fun leader(c: Canvas, x: Float, y: Float, bx: Float, by: Float, tx: Float, ty: Float) {
        line(c, x, y, bx, by, guide, 1.05f)
        line(c, bx, by, tx, ty, guide, 1.05f)
        disc(c, tx, ty, 1.8f, guide, cream)
    }

    private fun fill(c: Canvas, path: Path, shader: Shader, edge: Long) {
        ink(cream); paint.shader = shader; c.drawPath(path, paint); paint.shader = null
        stroke(c, path, edge, 1.45f)
    }

    private fun plate(id: Int): Drawable = requireNotNull(context.getDrawable(id)).apply {
        setBounds(0, 40, 360, 320)
    }

    private fun Path.domeRim() {
        moveTo(30f, 151f)
        quadTo(45f, 150f, 48f, 128f)
        cubicTo(50f, 102f, 66f, 104f, 68f, 128f)
        quadTo(70f, 159f, 83f, 148f)
        quadTo(91f, 139f, 94f, 123f)
        cubicTo(99f, 103f, 112f, 111f, 112f, 132f)
        quadTo(114f, 156f, 131f, 143f)
        cubicTo(146f, 132f, 156f, 132f, 170f, 132f)
        cubicTo(193f, 130f, 204f, 142f, 221f, 150f)
        quadTo(237f, 158f, 242f, 130f)
        cubicTo(246f, 99f, 262f, 105f, 263f, 132f)
        quadTo(268f, 158f, 279f, 148f)
        quadTo(289f, 140f, 290f, 123f)
        cubicTo(294f, 104f, 306f, 106f, 310f, 125f)
        quadTo(315f, 147f, 330f, 145f)
    }

    private fun Path.surfaceRim() {
        moveTo(30f, 130f)
        cubicTo(78f, 113f, 155f, 132f, 206f, 126f)
        cubicTo(247f, 125f, 289f, 109f, 329f, 121f)
    }

    private fun shape(build: Path.() -> Unit) = Path().apply(build)
}
