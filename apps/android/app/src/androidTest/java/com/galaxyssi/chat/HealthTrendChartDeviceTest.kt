package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.MotionEvent
import android.view.View
import androidx.test.platform.app.InstrumentationRegistry
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

/** Software-canvas fixtures never enter the user's health database or require an unlocked screen. */
class HealthTrendChartDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun summary(pressure: Boolean = false, gap: Boolean = false): HealthTrendSummary {
        val metric = if (pressure) HealthMetric.BLOOD_PRESSURE else HealthMetric.STEPS
        val spec = HealthTrendSpec(metric, LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 3), ZoneId.of("UTC"), metric.units.first())
        return HealthTrendBuilder(spec).apply {
            for (day in listOf(0, if (gap) 2 else 1)) {
                val values = if (pressure) mapOf("systolic" to "${124 + day}", "diastolic" to "${82 + day}") else mapOf("steps" to "${100 + day * 100}")
                add(HealthObservationPolicy.observation(HealthDraft(metric, values, spec.unit, spec.from + day * 86_400_000L + 43_200_000)))
            }
        }.finish()
    }
    private fun fixture(summary: HealthTrendSummary, widthDp: Int = 360, test: (HealthTrendChart, Bitmap, MutableList<HealthTrendPoint>) -> Unit) {
        lateinit var chart: HealthTrendChart; lateinit var bitmap: Bitmap; val selected = arrayListOf<HealthTrendPoint>()
        instrumentation.runOnMainSync {
            val d = context.resources.displayMetrics.density; val width = (widthDp * d).toInt(); val height = (240 * d).toInt()
            chart = HealthTrendChart(context) { selected += it }; chart.bind(summary)
            chart.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY)); chart.layout(0, 0, width, height)
            bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888); chart.draw(Canvas(bitmap))
        }
        try { test(chart, bitmap, selected) } finally { instrumentation.runOnMainSync { chart.clear() }; bitmap.recycle() }
    }
    private fun colored(bitmap: Bitmap, color: Int): List<Pair<Int, Int>> = buildList {
        for (y in 0 until bitmap.height) for (x in 0 until bitmap.width) if (bitmap.getPixel(x, y) == color) add(x to y)
    }
    @Test fun phoneAndTabletCanvasesActuallyRenderBothPressureComponents() {
        for (width in listOf(320, 600)) fixture(summary(pressure = true), width) { _, bitmap, _ ->
            assertTrue(colored(bitmap, HealthTrendChart.GREEN).size > 15); assertTrue(colored(bitmap, HealthTrendChart.BLUE).size > 15)
        }
    }
    @Test fun aMissingMiddleDayHasNeitherAConnectingLineNorAFabricatedZeroPoint() = fixture(summary(gap = true)) { _, bitmap, _ ->
        val d = context.resources.displayMetrics.density
        val middle = ((58 * d + bitmap.width - 14 * d) / 2).toInt()
        assertTrue(colored(bitmap, HealthTrendChart.GREEN).none { (x, _) -> kotlin.math.abs(x - middle) <= 1 })
    }
    @Test fun tappingAnActualDotReturnsItsOwnPointAndRecordIdentity() = fixture(summary(gap = true)) { chart, bitmap, selected ->
        val pixel = colored(bitmap, HealthTrendChart.GREEN).minBy { it.first }
        instrumentation.runOnMainSync {
            val down = MotionEvent.obtain(1, 1, MotionEvent.ACTION_DOWN, pixel.first.toFloat(), pixel.second.toFloat(), 0)
            val up = MotionEvent.obtain(1, 2, MotionEvent.ACTION_UP, pixel.first.toFloat(), pixel.second.toFloat(), 0)
            try { chart.onTouchEvent(down); chart.onTouchEvent(up) } finally { down.recycle(); up.recycle() }
        }
        assertEquals(1, selected.size); assertEquals(summary(gap = true).points.first().bucket, selected.single().bucket)
        assertTrue(selected.single().recordId.isNotBlank())
    }
    @Test fun aVerticalScrollGestureDoesNotOpenARecord() = fixture(summary()) { chart, bitmap, selected ->
        val pixel = colored(bitmap, HealthTrendChart.GREEN).minBy { it.first }
        instrumentation.runOnMainSync {
            val x = pixel.first.toFloat(); val y = pixel.second.toFloat()
            val events = listOf(MotionEvent.obtain(1, 1, MotionEvent.ACTION_DOWN, x, y, 0), MotionEvent.obtain(1, 2, MotionEvent.ACTION_MOVE, x, y + 100, 0), MotionEvent.obtain(1, 3, MotionEvent.ACTION_UP, x, y + 100, 0))
            try { events.forEach { chart.onTouchEvent(it) } } finally { events.forEach(MotionEvent::recycle) }
        }; assertTrue(selected.isEmpty())
    }
    @Test fun clearingAChartDropsBothRenderedPointsAndHitTargets() = fixture(summary()) { chart, bitmap, _ ->
        instrumentation.runOnMainSync { chart.clear(); bitmap.eraseColor(0); chart.draw(Canvas(bitmap)) }
        assertTrue(colored(bitmap, HealthTrendChart.GREEN).isEmpty()); assertNull(chart.hit(bitmap.width / 2f, bitmap.height / 2f)); assertEquals("", chart.contentDescription.toString())
    }
}
