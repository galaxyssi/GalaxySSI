package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

internal object HealthAtlasGasExchangeText {
    fun name(gas: HealthAtlasGas) = if (gas == HealthAtlasGas.OXYGEN) R.string.health_atlas_gas_oxygen else R.string.health_atlas_gas_carbon
    fun summary(context: Context, gradient: HealthAtlasGasGradient) = context.getString(R.string.health_atlas_gas_summary,
        context.getString(name(gradient.gas)), gradient.alveolar, gradient.incomingBlood,
        context.getString(if (gradient.towardBlood) R.string.health_atlas_gas_to_blood else R.string.health_atlas_gas_to_air))
}

/** Both arrows move together. Phase selects a teaching focus, not a physiological time interval. */
internal class HealthAtlasGasExchangeView(context: Context, mechanism: HealthAtlasMechanism,
    selected: (Int) -> Unit, open: (String) -> Unit) : LinearLayout(context) {
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private val arrows = arrayListOf<View>()
    private val stages = arrayListOf<TextView>()
    private val primary = context.getColor(R.color.text_primary)
    private val accent = context.getColor(R.color.health_overview_green)
    private fun label(value: String, size: Float = 14f) = TextView(context).apply {
        text = value; textSize = size; setTextColor(primary); gravity = Gravity.CENTER
        setPadding(dp(4), dp(6), dp(4), dp(6)); isSaveEnabled = false
    }
    private fun row() = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
    var phase = 0f
        set(value) {
            field = HealthAtlasGasExchange.phase(value)
            stages.forEachIndexed { index, view ->
                val active = index == HealthAtlasGasExchange.stage(field)
                if (view.isSelected != active) {
                    view.isSelected = active; view.setTextColor(if (active) accent else primary)
                }
            }
            arrows.forEach(View::invalidate)
        }
    init {
        require(mechanism.stages.size == 4)
        orientation = VERTICAL; tag = "atlas-process"; isSaveEnabled = false
        addView(ImageView(context).apply {
            setImageResource(R.drawable.health_atlas_alveolus); scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = context.getString(R.string.health_atlas_view_alveolus)
            tag = "atlas-gas-alveolus"; isFocusable = true; setOnClickListener { open("alveoli") }
        }, LayoutParams(-1, dp(240)))
        addView(label(context.getString(R.string.health_atlas_gas_example), 12f))
        addView(row().apply {
            addView(label(context.getString(R.string.health_atlas_gas_alveolar)).apply {
                tag = "atlas-gas-air"; minimumHeight = dp(48); isFocusable = true; setOnClickListener { open("alveoli") }
            }, LayoutParams(0, -2, 1f))
            addView(label(context.getString(R.string.health_atlas_respiratory_membrane_name), 12f).apply {
                tag = "atlas-gas-membrane"; minimumHeight = dp(48); isFocusable = true
                setOnClickListener { open("respiratory-membrane") }
            }, LayoutParams(0, -2, 1f))
            addView(label(context.getString(R.string.health_atlas_gas_blood)).apply {
                tag = "atlas-gas-blood"; minimumHeight = dp(48); isFocusable = true; setOnClickListener { open("pulmonary-capillaries") }
            }, LayoutParams(0, -2, 1f))
        })
        HealthAtlasGasExchange.gradients.forEach { gradient ->
            addView(label(context.getString(HealthAtlasGasExchangeText.name(gradient.gas))).apply {
                tag = "atlas-gas-label-${gradient.gas.name}"
                contentDescription = HealthAtlasGasExchangeText.summary(context, gradient)
            })
            addView(row().apply {
                addView(label(HealthAtlasPhysiologyText.number(gradient.alveolar.toDouble()), 20f), LayoutParams(0, -2, 1f))
                val arrow = object : View(context) {
                    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = context.getColor(if (gradient.towardBlood) R.color.health_atlas_blood_high else R.color.health_atlas_blood_low)
                    }
                    private val head = Path()
                    override fun onDraw(canvas: Canvas) {
                        val start = dp(10).toFloat(); val end = (width - dp(10)).coerceAtLeast(dp(10)).toFloat()
                        val y = height / 2f
                        paint.strokeWidth = resources.displayMetrics.density * 2
                        canvas.drawLine(start, y, end, y, paint)
                        val tip = if (gradient.towardBlood) end else start
                        val sign = if (gradient.towardBlood) 1 else -1
                        head.reset(); head.moveTo(tip, y); head.lineTo(tip - sign * dp(8), y - dp(5))
                        head.lineTo(tip - sign * dp(8), y + dp(5)); head.close(); canvas.drawPath(head, paint)
                        canvas.drawCircle(start + (end - start) * HealthAtlasGasExchange.position(gradient.gas, phase), y, dp(4).toFloat(), paint)
                    }
                }.apply { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO; tag = "atlas-gas-arrow-${gradient.gas.name}" }
                arrows += arrow; addView(arrow, LayoutParams(0, dp(40), 1f))
                addView(label(HealthAtlasPhysiologyText.number(gradient.incomingBlood.toDouble()), 20f), LayoutParams(0, -2, 1f))
            })
        }
        mechanism.stages.chunked(2).forEachIndexed { rowIndex, values ->
            addView(row().apply {
                values.forEachIndexed { column, value ->
                    val index = rowIndex * 2 + column
                    val button = object : TextView(context) { override fun getAccessibilityClassName(): CharSequence = "android.widget.Button" }.apply {
                        text = value; textSize = 14f; gravity = Gravity.CENTER; minimumHeight = dp(48)
                        setTypeface(null, android.graphics.Typeface.BOLD)
                        setTextColor(primary); setPadding(dp(6), dp(8), dp(6), dp(8)); isFocusable = true; isSaveEnabled = false
                        tag = "atlas-process-stage-$index"; setOnClickListener { selected(index) }
                    }
                    stages += button; addView(button, LayoutParams(0, -2, 1f))
                }
            })
        }
        phase = 0f
    }
}
