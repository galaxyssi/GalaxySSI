package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/** Native labels over a teaching circuit; paths are not anatomical vessels or measured transit times. */
internal class HealthAtlasCirculationView(context: Context, private val mechanism: HealthAtlasMechanism,
    private val selected: (Int) -> Unit, private val open: (String) -> Unit) : ViewGroup(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val path = Path()
    private val arrow = Path()
    private val measure = PathMeasure()
    private val position = FloatArray(2)
    private val tangent = FloatArray(2)
    private val density = resources.displayMetrics.density
    private val low = context.getColor(R.color.health_atlas_blood_low)
    private val high = context.getColor(R.color.health_atlas_blood_high)
    private val titles = listOf(R.string.health_atlas_circuit_lungs, R.string.health_atlas_circuit_heart,
        R.string.health_atlas_circuit_tissues)
    private val routes = listOf(R.string.health_atlas_circuit_leg_0, R.string.health_atlas_circuit_leg_1,
        R.string.health_atlas_circuit_leg_2, R.string.health_atlas_circuit_leg_3)
    private var upperGap = 0
    private var lowerGap = 0
    private val heartValue = label("", 12f).apply { tag = "atlas-circulation-flow" }
    private fun dp(value: Int) = (value * density).toInt()
    private fun label(value: String, size: Float) = TextView(context).apply {
        text = value; textSize = size; gravity = Gravity.CENTER
        setTextColor(context.getColor(R.color.text_primary)); isSaveEnabled = false
    }
    private val nodes = listOf(R.drawable.health_atlas_lungs, R.drawable.health_atlas_heart,
        R.drawable.health_atlas_body).mapIndexed { index, drawable ->
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            val title = context.getString(titles[index])
            tag = "atlas-circulation-node-${listOf("lungs", "heart", "tissues")[index]}"
            addView(ImageView(context).apply {
                setImageResource(drawable); scaleType = ImageView.ScaleType.FIT_CENTER
                importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(-1, dp(if (index == 2) 104 else 88)))
            addView(label(title, 13f), LinearLayout.LayoutParams(-1, -2))
            if (index == 1) addView(heartValue, LinearLayout.LayoutParams(-1, -2))
            if (index < 2) {
                isFocusable = true; contentDescription = title
                setOnClickListener { open(if (index == 0) "lungs" else "heart") }
            }
        }.also { addView(it) }
    }
    private val sides = listOf(R.string.health_atlas_circuit_right, R.string.health_atlas_circuit_left).mapIndexed { index, title ->
        label(context.getString(title), 12f).apply {
            setTextColor(if (index == 0) low else high); tag = "atlas-circulation-side-$index"
            setPadding(dp(2), dp(2), dp(2), dp(2)); setBackgroundColor(context.getColor(R.color.page_bg))
        }.also { addView(it) }
    }
    private val stages = mechanism.stages.mapIndexed { index, title ->
        object : TextView(context) { override fun getAccessibilityClassName(): CharSequence = "android.widget.Button" }.apply {
            text = context.getString(routes[index]); textSize = 12f; gravity = Gravity.CENTER; minimumHeight = dp(48)
            setTypeface(null, android.graphics.Typeface.BOLD)
            setPadding(dp(4), dp(6), dp(4), dp(6)); setTextColor(context.getColor(R.color.text_primary))
            setBackgroundColor(context.getColor(R.color.page_bg)); isSaveEnabled = false; isFocusable = true
            tag = "atlas-process-stage-$index"
            contentDescription = context.getString(R.string.health_atlas_stage, index + 1, 4, title)
            setOnClickListener { selected(index) }
        }.also { addView(it) }
    }
    var flowLitresPerMinute: Double? = null
        set(value) {
            require(value == null || value.isFinite() && value >= 0)
            field = value
            heartValue.text = value?.let { context.getString(R.string.health_atlas_circuit_flow, HealthAtlasPhysiologyText.number(it)) }.orEmpty()
            heartValue.visibility = if (value == null) GONE else VISIBLE
            nodes[1].contentDescription = listOf(context.getString(titles[1]), heartValue.text.toString()).filter(String::isNotBlank).joinToString(" \u00b7 ")
        }
    var phase = 0f
        set(value) {
            field = HealthAtlasCirculation.phase(value)
            val stage = HealthAtlasCirculation.stage(field)
            stages.forEachIndexed { index, label ->
                val active = index == stage
                if (label.isSelected != active) {
                    label.isSelected = active
                    label.setTextColor(if (active) if (index < 2) low else high else context.getColor(R.color.text_primary))
                }
            }
            invalidate()
        }
    init {
        require(mechanism.stages.size == HealthAtlasCirculation.legs.size)
        tag = "atlas-process"; isSaveEnabled = false; setWillNotDraw(false)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        flowLitresPerMinute = null; phase = 0f
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        fun View.width(fraction: Float) = measure(MeasureSpec.makeMeasureSpec((w * fraction).toInt().coerceAtLeast(1), MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
        nodes.forEach { it.width(.40f) }; sides.forEach { it.width(.28f) }; stages.forEach { it.width(.28f) }
        upperGap = maxOf(dp(64), stages[1].measuredHeight + dp(16), stages[2].measuredHeight + dp(16))
        lowerGap = maxOf(dp(64), stages[0].measuredHeight + dp(16), stages[3].measuredHeight + dp(16))
        setMeasuredDimension(w, resolveSize(nodes.sumOf { it.measuredHeight } + upperGap + lowerGap + dp(16) + paddingBottom,
            heightMeasureSpec))
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        var top = dp(8)
        nodes.forEachIndexed { index, node ->
            val x = (width - node.measuredWidth) / 2
            node.layout(x, top, x + node.measuredWidth, top + node.measuredHeight)
            top = node.bottom + if (index == 0) upperGap else lowerGap
        }
        stages.forEachIndexed { index, label ->
            val upper = index in 1..2
            val centerY = if (upper) (nodes[0].bottom + nodes[1].top) / 2 else (nodes[1].bottom + nodes[2].top) / 2
            val x = if (index < 2) 0 else width - label.measuredWidth
            label.layout(x, centerY - label.measuredHeight / 2, x + label.measuredWidth, centerY + (label.measuredHeight + 1) / 2)
        }
        sides.forEachIndexed { index, label ->
            val x = if (index == 0) 0 else width - label.measuredWidth
            val y = nodes[1].top + dp(44) - label.measuredHeight / 2
            label.layout(x, y, x + label.measuredWidth, y + label.measuredHeight)
        }
    }
    private fun route(index: Int) {
        fun node(id: HealthAtlasBloodNode) = when (id) { HealthAtlasBloodNode.LUNGS -> 0; HealthAtlasBloodNode.TISSUES -> 2; else -> 1 }
        val leg = HealthAtlasCirculation.legs[index]
        val from = node(leg.from)
        val to = node(leg.to)
        val left = !leg.oxygenRich
        val inner = width * if (left) .40f else .60f
        val outer = width * if (left) .14f else .86f
        // Separate incoming and outgoing heart ports so opposite arrows never share a line.
        val y0 = nodes[from].top + dp(if (from == 2) 52 else 44) + if (from == 1) dp(if (left) -18 else 18).toFloat() else 0f
        val y1 = nodes[to].top + dp(if (to == 2) 52 else 44) + if (to == 1) dp(if (left) 18 else -18).toFloat() else 0f
        path.reset(); path.moveTo(inner, y0); path.lineTo(outer, y0); path.lineTo(outer, y1); path.lineTo(inner, y1)
        measure.setPath(path, false)
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val current = HealthAtlasCirculation.stage(phase)
        for (index in HealthAtlasCirculation.legs.indices) {
            route(index)
            paint.color = if (HealthAtlasCirculation.legs[index].oxygenRich) high else low; paint.alpha = if (index == current) 255 else 115
            paint.style = Paint.Style.STROKE; paint.strokeWidth = density * if (index == current) 3f else 1.5f
            paint.strokeJoin = Paint.Join.ROUND; canvas.drawPath(path, paint)
            measure.getPosTan(measure.length, position, tangent)
            val x = position[0]; val y = position[1]; val dx = tangent[0]; val dy = tangent[1]
            arrow.apply {
                reset(); moveTo(x, y); lineTo(x - dx * dp(8) - dy * dp(4), y - dy * dp(8) + dx * dp(4))
                lineTo(x - dx * dp(8) + dy * dp(4), y - dy * dp(8) - dx * dp(4)); close()
            }
            paint.style = Paint.Style.FILL; canvas.drawPath(arrow, paint)
            if (index == current) {
                measure.getPosTan(measure.length * HealthAtlasCirculation.fraction(phase), position, null)
                canvas.drawCircle(position[0], position[1], dp(5).toFloat(), paint)
            }
        }
        paint.alpha = 255
    }
}
