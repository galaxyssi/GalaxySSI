package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Path
import android.graphics.PathMeasure
import androidx.annotation.StringRes
import com.galaxyssi.chat.HealthAtlasAccessoryGlandRoutingAssignment as Chapter
import com.galaxyssi.chat.R.string

internal object HealthAtlasAccessoryGlandRoutingMotion {
    fun landmark(t: Float, count: Int) = (phase(t) * count).toInt().coerceIn(0, count - 1)

    fun progress(t: Float, delay: Float = 0f): Float {
        val p = ((phase(t) - .04f - delay) / (.84f - delay)).coerceIn(0f, 1f)
        return p * p * (3f - 2f * p)
    }

    private fun phase(t: Float) = if (t.isFinite()) t.coerceIn(0f, 1f) else 0f
}

internal class HealthAtlasAccessoryGlandRoutingStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private class Route(val left: Path, val right: Path, val lengthwise: List<PathMeasure>, val color: Long)
    private data class Callout(@StringRes val text: Int, val x: Float, val y: Float, val row: Float, val left: Boolean)

    private val illustration = requireNotNull(context.getDrawable(R.drawable.health_atlas_accessory_gland_routing_cutaway))
        .apply { setBounds(0, 0, 360, 280) }
    private val reflection = Matrix().apply { setScale(-1f, 1f, 180f, 0f) }
    private val trail = Path()
    private val ductWall = 0xff786c74
    private val ductLumen = 0xfff9ecdd
    private val guide = 0xff5f7375
    private val vesicleInk = 0xff985944
    private val ejaculatoryInk = 0xff6b5683
    private val prostateInk = 0xff426e8b
    private val bulbInk = 0xff2a746d

    private val vas = route(0xff7b756d) {
        moveTo(143f, 23f)
        cubicTo(139f, 45f, 150f, 61f, 150f, 74f)
        cubicTo(150f, 84f, 150f, 92f, 155f, 97f)
    }
    private val vesicle = route(vesicleInk) {
        moveTo(127f, 69f)
        cubicTo(133f, 70f, 132f, 79f, 138f, 86f)
        quadTo(144f, 93f, 155f, 97f)
    }
    private val ejaculatory = route(ejaculatoryInk) {
        moveTo(155f, 97f)
        cubicTo(163f, 106f, 160f, 124f, 175f, 139f)
    }
    private val prostateUpper = route(prostateInk) {
        moveTo(144f, 130f)
        cubicTo(152f, 131f, 155f, 148f, 175f, 147f)
    }
    private val prostateLower = route(prostateInk) {
        moveTo(146f, 148f)
        cubicTo(156f, 147f, 165f, 161f, 175f, 158f)
    }
    private val bulb = route(bulbInk) {
        moveTo(153f, 183f)
        cubicTo(159f, 188f, 158f, 199f, 163f, 207f)
        cubicTo(168f, 215f, 170f, 223f, 176f, 229f)
    }
    private val routes = listOf(vas, vesicle, ejaculatory, prostateUpper, prostateLower, bulb)

    private val vesicleLabel = Callout(string.health_atlas_accessory_gland_routing_vesicles, 119f, 67f, 58f, true)
    private val ejaculatoryLabel = Callout(string.health_atlas_accessory_gland_routing_ejaculatory, 199f, 113f, 102f, false)
    private val prostateLabel = Callout(string.health_atlas_accessory_gland_routing_prostate, 138f, 136f, 134f, true)
    private val bulbLabel = Callout(string.health_atlas_accessory_gland_routing_bulbourethral, 207f, 183f, 180f, false)
    private val bulbarLabel = Callout(string.health_atlas_accessory_gland_routing_label_bulbar, 187f, 229f, 240f, false)
    private val prostaticUrethra = Callout(string.health_atlas_accessory_gland_routing_label_prostatic, 181f, 163f, 163f, false)
    private val locatorLabels = listOf(vesicleLabel, ejaculatoryLabel, prostateLabel, bulbLabel, bulbarLabel)
    private val vesicleLabels = listOf(
        vesicleLabel,
        Callout(string.health_atlas_accessory_gland_routing_label_vas, 217f, 35f, 28f, false),
        Callout(string.health_atlas_accessory_gland_routing_label_junction, 205f, 97f, 87f, false),
    )
    private val ejaculatoryLabels = listOf(
        ejaculatoryLabel.copy(x = 161f, y = 115f, row = 102f, left = true),
        prostateLabel.copy(x = 220f, y = 119f, row = 110f, left = false),
        prostaticUrethra,
    )
    private val prostateLabels = listOf(
        prostateLabel.copy(y = 121f, row = 113f),
        Callout(string.health_atlas_accessory_gland_routing_label_prostate_ducts, 160f, 156f, 157f, true),
        prostaticUrethra,
    )
    private val bulbLabels = listOf(
        bulbLabel.copy(x = 149f, y = 183f, row = 166f, left = true),
        Callout(string.health_atlas_accessory_gland_routing_label_membranous, 184f, 172f, 166f, false),
        Callout(string.health_atlas_accessory_gland_routing_label_long_duct, 165f, 210f, 213f, true),
        bulbarLabel,
    )

    override fun scene(c: Canvas, step: Int, t: Float) {
        c.save()
        c.translate(0f, 40f)
        illustration.draw(c)
        for (route in routes) drawRoute(c, route, step)

        val labels = when (step) {
            Chapter.SEMINAL_VESICLES -> {
                move(c, vesicle, t)
                vesicleLabels
            }
            Chapter.EJACULATORY_DUCTS -> {
                move(c, ejaculatory, t)
                ejaculatoryLabels
            }
            Chapter.PROSTATE -> {
                move(c, prostateUpper, t)
                move(c, prostateLower, t, .17f)
                prostateLabels
            }
            Chapter.BULBOURETHRAL_GLANDS -> {
                move(c, bulb, t)
                bulbLabels
            }
            else -> locatorLabels
        }
        val landmark = if (step == Chapter.LOCATOR) HealthAtlasAccessoryGlandRoutingMotion.landmark(t, labels.size) else -1
        labels.forEachIndexed { index, callout -> annotate(c, callout, index == landmark) }
        c.restore()
    }

    private fun route(color: Long, draw: Path.() -> Unit): Route {
        val left = Path().apply(draw)
        val right = Path(left).apply { transform(reflection) }
        return Route(left, right, listOf(track(left), track(right)), color)
    }

    private fun drawRoute(c: Canvas, route: Route, step: Int) {
        val active = when (step) {
            Chapter.SEMINAL_VESICLES -> route === vesicle
            Chapter.EJACULATORY_DUCTS -> route === ejaculatory
            Chapter.PROSTATE -> route === prostateUpper || route === prostateLower
            Chapter.BULBOURETHRAL_GLANDS -> route === bulb
            else -> route !== vas
        }
        val color = if (active) route.color else ductWall
        stroke(c, route.left, color, if (active) 4f else 3f)
        stroke(c, route.right, color, if (active) 4f else 3f)
        stroke(c, route.left, ductLumen, 1.5f)
        stroke(c, route.right, ductLumen, 1.5f)
    }

    private fun move(c: Canvas, route: Route, t: Float, delay: Float = 0f) {
        val p = HealthAtlasAccessoryGlandRoutingMotion.progress(t, delay)
        for (measure in route.lengthwise) {
            trail.rewind()
            if (measure.getSegment(measure.length * (p - .22f).coerceAtLeast(0f), measure.length * p, trail, true)) {
                stroke(c, trail, route.color, 2.8f)
            }
            at(measure, p) { x, y -> disc(c, x, y, 3.15f, cream, route.color) }
        }
    }

    private fun annotate(c: Canvas, callout: Callout, active: Boolean) {
        val end = if (callout.left) 107f else 246f
        val bend = callout.x + if (callout.left) -9f else 9f
        val color = if (active) teal else guide
        line(c, callout.x, callout.y, bend, callout.row, color, 1f)
        line(c, bend, callout.row, end, callout.row, color, 1f)
        if (active) disc(c, callout.x, callout.y, 5f, 0x3a337b6d, teal)
        disc(c, callout.x, callout.y, 2f, cream, color)
        label(c, callout.text, if (callout.left) 64f else 293f, callout.row - 5f, if (callout.left) 116f else 120f)
    }
}
