package com.galaxyssi.chat

import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat

enum class ControlCenterTone {
    NEUTRAL,
    GREEN,
    BLUE,
    AMBER,
    RED,
    VIOLET
}

enum class ControlCenterRoute(
    val wireValue: String,
    val isAvailable: Boolean = true
) {
    MODEL_HUB("model_hub"),
    DEVICE_HUB("device_hub"),
    MEMORY_HUB("memory_hub"),
    SKILLS_HUB("skills_hub"),
    SAFETY_HUB("safety_hub"),
    PROACTIVE_HUB("proactive_hub"),
    OBSIDIAN_HUB("obsidian_hub"),
    STORAGE_HUB("storage_hub"),
    NOTIFICATIONS_HUB("notifications_hub"),
    DIAGNOSTICS_HUB("diagnostics_hub"),
    PERMISSIONS_HUB("permissions_hub"),
    SYSTEM_STATUS("system_status", isAvailable = false),
    GLOBAL_AGENT("global_agent"),
    AGENT_CORE("agent_core"),
    SELF_EVOLUTION("self_evolution"),
    EXECUTION_POLICY("execution_policy"),
    RESOURCE_ROUTING("resource_routing"),
    MEMORY("memory"),
    LEARNING("learning"),
    KNOWLEDGE("knowledge"),
    MCP("mcp"),
    TASKS("tasks", isAvailable = false),
    PHONE_CAPABILITIES("phone_capabilities"),
    ON_DEVICE_RUNTIME("on_device_runtime"),
    SOFTWARE_CENTER("software_center"),
    SMART_SPACES("smart_spaces"),
    NODES("nodes", isAvailable = false),
    SECURITY("security", isAvailable = false),
    PRIVACY("privacy", isAvailable = false),
    PERMISSIONS_AUDIT("permissions_audit", isAvailable = false),
    VOICE("voice"),
    DATA_BACKUP("data_backup"),
    GENERAL("general"),
    ADVANCED("advanced"),
    RESET("reset");

    companion object {
        fun fromWireValue(value: String): ControlCenterRoute? = entries.firstOrNull {
            it.isAvailable && it.wireValue == value.trim().lowercase()
        }
    }
}

enum class ControlCenterHomeGroup { COMMON, SETTINGS }

object ControlCenterHomeGrouping {
    val orderedGroups = ControlCenterHomeGroup.entries.toList()
    private val routesByGroup = linkedMapOf(
        ControlCenterHomeGroup.COMMON to listOf(
            ControlCenterRoute.MODEL_HUB, ControlCenterRoute.DEVICE_HUB,
            ControlCenterRoute.VOICE, ControlCenterRoute.MEMORY_HUB,
            ControlCenterRoute.PROACTIVE_HUB, ControlCenterRoute.SKILLS_HUB
        ),
        ControlCenterHomeGroup.SETTINGS to listOf(
            ControlCenterRoute.SAFETY_HUB, ControlCenterRoute.GENERAL, ControlCenterRoute.ADVANCED
        )
    )
    fun routes(group: ControlCenterHomeGroup): List<ControlCenterRoute> = routesByGroup[group].orEmpty()
    fun groupFor(route: ControlCenterRoute): ControlCenterHomeGroup? =
        routesByGroup.entries.firstOrNull { route in it.value }?.key
}

data class ControlCenterBadgeSpec(
    val text: String,
    val tone: ControlCenterTone = ControlCenterTone.NEUTRAL
)

data class ControlCenterMetricSpec(
    val value: String,
    val label: String
)

data class ControlCenterHeroSpec(
    val title: String,
    val subtitle: String,
    val iconRes: Int,
    val badges: List<ControlCenterBadgeSpec> = emptyList(),
    val metrics: List<ControlCenterMetricSpec> = emptyList(),
    val actionId: String = "",
    val preserveIconColor: Boolean = false,
    val titleActionId: String = "",
    val trailingActionId: String = "",
    val trailingIconRes: Int = 0,
    val trailingContentDescription: String = ""
)

data class ControlCenterBannerSpec(
    val title: String,
    val subtitle: String,
    val iconRes: Int,
    val tone: ControlCenterTone = ControlCenterTone.BLUE,
    val actionId: String = ""
)

data class ControlCenterRowSpec(
    val actionId: String,
    val title: String,
    val subtitle: String,
    val iconRes: Int,
    val status: String = "",
    val tone: ControlCenterTone = ControlCenterTone.NEUTRAL,
    val switchValue: Boolean? = null,
    val showChevron: Boolean = true,
    val enabled: Boolean = true,
    val preserveIconColor: Boolean = false,
    val badges: List<ControlCenterBadgeSpec> = emptyList()
)

data class ControlCenterSectionSpec(
    val title: String,
    val rows: List<ControlCenterRowSpec>,
    val collapsed: Boolean = false
)

data class ControlCenterPageSpec(
    val hero: ControlCenterHeroSpec? = null,
    val banner: ControlCenterBannerSpec? = null,
    val sections: List<ControlCenterSectionSpec>,
    val footer: String = ""
)

internal class ControlCenterPageRenderCache {
    private var renderedPage: ControlCenterPageSpec? = null

    fun shouldRender(page: ControlCenterPageSpec, hasContent: Boolean): Boolean {
        if (hasContent && renderedPage == page) return false
        renderedPage = page
        return true
    }
}

internal class ControlCenterHomeRefreshPolicy(private val maxAgeMillis: Long) {
    private var dirty = true
    private var renderedAt = 0L

    fun invalidate() {
        dirty = true
    }

    fun shouldRefresh(visible: Boolean, nowMillis: Long, force: Boolean = false): Boolean {
        if (!visible) {
            invalidate()
            return false
        }
        return force || dirty || renderedAt <= 0L || nowMillis - renderedAt >= maxAgeMillis
    }

    fun markRendered(nowMillis: Long) {
        dirty = false
        renderedAt = nowMillis
    }
}

internal fun controlCenterStatusViewTag(actionId: String): String =
    "control-center-status:$actionId"

class ControlCenterRenderer(
    private val context: Context,
    private val expandedSections: MutableSet<String> = mutableSetOf()
) {
    fun render(
        content: LinearLayout,
        page: ControlCenterPageSpec,
        onAction: (String) -> Unit
    ) {
        content.removeAllViews()
        content.orientation = LinearLayout.VERTICAL
        content.gravity = Gravity.NO_GRAVITY
        content.setPadding(0, 0, 0, dp(28))

        page.banner?.let { content.addView(banner(it, onAction)) }
        page.hero?.let {
            if (it.preserveIconColor) {
                content.addView(hero(it.copy(badges = emptyList(), metrics = emptyList()), onAction))
            } else if (it.actionId.isNotBlank()) {
                content.addView(banner(ControlCenterBannerSpec(it.title, it.subtitle, it.iconRes,
                    ControlCenterTone.NEUTRAL, it.actionId), onAction))
            }
        }
        page.sections.forEach { section ->
            if (section.rows.isEmpty()) return@forEach
            val rows = sectionCard(section.rows, onAction)
            if (section.title.isNotBlank()) {
                content.addView(sectionTitle(section.title).apply {
                    if (section.collapsed) {
                        val key = section.title + section.rows.joinToString { it.actionId }
                        rows.visibility = if (key in expandedSections) View.VISIBLE else View.GONE
                        minimumHeight = dp(48)
                        setCompoundDrawablesRelativeWithIntrinsicBounds(0, 0, R.drawable.ic_arrow_right, 0)
                        compoundDrawableTintList = ColorStateList.valueOf(color(R.color.icon_gray))
                        isClickable = true
                        isFocusable = true
                        setOnClickListener {
                            val expanded = rows.visibility != View.VISIBLE
                            if (expanded) expandedSections.add(key) else expandedSections.remove(key)
                            rows.visibility = if (expanded) View.VISIBLE else View.GONE
                            isSelected = expanded
                            contentDescription = section.title + if (expanded) " -" else " +"
                        }
                    }
                })
            }
            content.addView(rows)
        }
        if (page.footer.isNotBlank()) {
            content.addView(TextView(context).apply {
                text = page.footer
                textSize = 11f
                gravity = Gravity.CENTER
                setTextColor(color(R.color.text_secondary))
                setPadding(dp(14), dp(16), dp(14), dp(4))
            })
        }
    }

    private fun hero(spec: ControlCenterHeroSpec, onAction: (String) -> Unit): View =
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
            setBackgroundColor(color(R.color.surface_bg))
            isClickable = spec.actionId.isNotBlank()
            isFocusable = isClickable
            if (isClickable) setOnClickListener { onAction(spec.actionId) }

            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(iconView(spec.iconRes, ControlCenterTone.BLUE, 56, spec.preserveIconColor))
                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(dp(14), 0, dp(8), 0)
                    addView(TextView(context).apply {
                        text = spec.title
                        textSize = 18f
                        setTextColor(color(R.color.text_primary))
                        setTypeface(typeface, Typeface.BOLD)
                        if (spec.titleActionId.isNotBlank()) {
                            setCompoundDrawablesRelativeWithIntrinsicBounds(
                                0,
                                0,
                                R.drawable.ic_arrow_right,
                                0
                            )
                            compoundDrawablePadding = dp(2)
                            compoundDrawableTintList = ColorStateList.valueOf(color(R.color.icon_gray))
                            isClickable = true
                            isFocusable = true
                            setOnClickListener { onAction(spec.titleActionId) }
                        }
                    }, LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    ))
                    addView(TextView(context).apply {
                        text = spec.subtitle
                        textSize = 12f
                        maxLines = 2
                        ellipsize = TextUtils.TruncateAt.END
                        setTextColor(color(R.color.text_secondary))
                        setPadding(0, dp(4), 0, 0)
                    })
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                if (spec.trailingActionId.isNotBlank() && spec.trailingIconRes != 0) {
                    addView(ImageView(context).apply {
                        setImageResource(spec.trailingIconRes)
                        scaleType = ImageView.ScaleType.CENTER_INSIDE
                        setPadding(dp(7), dp(7), dp(7), dp(7))
                        background = selectableBorderlessBackground()
                        contentDescription = spec.trailingContentDescription
                        isClickable = true
                        isFocusable = true
                        setOnClickListener { onAction(spec.trailingActionId) }
                    }, LinearLayout.LayoutParams(dp(40), dp(40)))
                } else if (spec.actionId.isNotBlank()) {
                    addView(chevron())
                }
            })

            if (spec.badges.isNotEmpty()) {
                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(0, dp(12), 0, 0)
                    spec.badges.take(3).forEachIndexed { index, badge ->
                        addView(badge(badge), LinearLayout.LayoutParams(
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                            dp(24)
                        ).apply { if (index > 0) marginStart = dp(7) })
                    }
                })
            }

            if (spec.metrics.isNotEmpty()) {
                addView(View(context).apply { setBackgroundColor(dividerColor()) },
                    LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1).apply { topMargin = dp(13) })
                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER
                    setPadding(0, dp(12), 0, 0)
                    spec.metrics.take(3).forEachIndexed { index, metric ->
                        addView(LinearLayout(context).apply {
                            orientation = LinearLayout.VERTICAL
                            gravity = Gravity.CENTER
                            minimumHeight = dp(48)
                            setPadding(0, 0, 0, dp(4))
                            addView(TextView(context).apply {
                                text = metric.value
                                textSize = 16f
                                gravity = Gravity.CENTER
                                setTextColor(color(R.color.text_primary))
                                setTypeface(typeface, Typeface.BOLD)
                            })
                            addView(TextView(context).apply {
                                text = metric.label
                                textSize = 12f
                                gravity = Gravity.CENTER
                                maxLines = 2
                                ellipsize = TextUtils.TruncateAt.END
                                setTextColor(color(R.color.text_secondary))
                                setPadding(dp(2), dp(3), dp(2), 0)
                            })
                        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                        if (index < spec.metrics.take(3).lastIndex) {
                            addView(View(context).apply { setBackgroundColor(dividerColor()) },
                                LinearLayout.LayoutParams(1, dp(39)))
                        }
                    }
                })
            }
        }.also {
            it.layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(3) }
        }

    private fun banner(spec: ControlCenterBannerSpec, onAction: (String) -> Unit): View =
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), dp(14), dp(20), dp(14))
            val palette = palette(spec.tone)
            setBackgroundColor(color(R.color.surface_bg))
            isClickable = spec.actionId.isNotBlank()
            isFocusable = isClickable
            if (isClickable) setOnClickListener { onAction(spec.actionId) }
            addView(iconView(spec.iconRes, spec.tone, 34, false))
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(11), 0, dp(4), 0)
                addView(TextView(context).apply {
                    text = spec.title
                    textSize = 13.5f
                    setTextColor(color(R.color.text_primary))
                    setTypeface(typeface, Typeface.BOLD)
                })
                addView(TextView(context).apply {
                    text = spec.subtitle
                    textSize = 12f
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    setTextColor(color(R.color.text_secondary))
                    setPadding(0, dp(3), 0, 0)
                })
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            if (spec.actionId.isNotBlank()) addView(chevron())
        }.also {
            it.layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(10) }
        }

    private fun sectionTitle(title: String): TextView = TextView(context).apply {
        text = title
        textSize = 12f
        setTextColor(color(R.color.text_secondary))
        setTypeface(typeface, Typeface.NORMAL)
        setPadding(dp(20), dp(12), dp(20), dp(8))
    }

    private fun sectionCard(rows: List<ControlCenterRowSpec>, onAction: (String) -> Unit): View =
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(color(R.color.surface_bg))
            rows.forEachIndexed { index, spec ->
                addView(row(spec, onAction))
                if (index < rows.lastIndex) {
                    addView(View(context).apply { setBackgroundColor(dividerColor()) },
                        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1).apply {
                            marginStart = dp(20)
                            marginEnd = dp(20)
                        })
                }
            }
        }

    private fun row(spec: ControlCenterRowSpec, onAction: (String) -> Unit): View =
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(56)
            setPadding(dp(20), dp(13), dp(20), dp(13))
            alpha = if (spec.enabled) 1f else 0.48f
            isEnabled = spec.enabled
            isClickable = spec.enabled && spec.actionId.isNotBlank()
            isFocusable = isClickable
            if (isClickable) setOnClickListener { onAction(spec.actionId) }
            addView(iconView(spec.iconRes, spec.tone, 22, spec.preserveIconColor))
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(12), 0, dp(8), 0)
                addView(TextView(context).apply {
                    text = spec.title
                    textSize = 15f
                    setTextColor(color(R.color.text_primary))
                    setTypeface(typeface, Typeface.NORMAL)
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                })
                if (spec.subtitle.isNotBlank()) {
                    addView(TextView(context).apply {
                        text = spec.subtitle
                        textSize = 12f
                        setTextColor(color(R.color.text_secondary))
                        maxLines = 2
                        ellipsize = TextUtils.TruncateAt.END
                        setPadding(0, dp(3), 0, 0)
                    })
                }
                if (spec.badges.isNotEmpty()) {
                    addView(LinearLayout(context).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.CENTER_VERTICAL
                        setPadding(0, dp(6), 0, 0)
                        spec.badges.take(3).forEachIndexed { index, item ->
                            addView(
                                badge(item).apply {
                                    maxLines = 1
                                    ellipsize = TextUtils.TruncateAt.END
                                    maxWidth = dp(if (index == 2) 112 else 92)
                                },
                                LinearLayout.LayoutParams(
                                    ViewGroup.LayoutParams.WRAP_CONTENT,
                                    dp(21)
                                ).apply {
                                    if (index > 0) marginStart = dp(5)
                                }
                            )
                        }
                    })
                }
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

            if (spec.status.isNotBlank()) {
                addView(TextView(context).apply {
                    if (spec.actionId.isNotBlank()) tag = controlCenterStatusViewTag(spec.actionId)
                    text = spec.status
                    textSize = 12f
                    gravity = Gravity.END or Gravity.CENTER_VERTICAL
                    maxLines = 2
                    maxWidth = dp(108)
                    setTextColor(palette(spec.tone).strong)
                    setPadding(dp(4), 0, dp(3), 0)
                }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            }
            if (spec.switchValue != null) {
                addView(switchPill(spec.switchValue))
            } else if (spec.showChevron && spec.actionId.isNotBlank()) {
                addView(chevron())
            }
        }

    private fun iconView(
        iconRes: Int,
        tone: ControlCenterTone,
        sizeDp: Int,
        preserveColor: Boolean
    ): ImageView = ImageView(context).apply {
        setImageResource(iconRes)
        scaleType = ImageView.ScaleType.CENTER_INSIDE
        if (preserveColor) {
            background = null
            setPadding(0, 0, 0, 0)
            imageTintList = null
        } else {
            background = null
            setPadding(0, 0, 0, 0)
            imageTintList = ColorStateList.valueOf(color(R.color.text_primary))
        }
        layoutParams = LinearLayout.LayoutParams(dp(sizeDp), dp(sizeDp))
    }

    private fun badge(spec: ControlCenterBadgeSpec): TextView {
        val palette = palette(spec.tone)
        return TextView(context).apply {
            text = spec.text
            textSize = 10.5f
            includeFontPadding = false
            gravity = Gravity.CENTER
            setTextColor(palette.strong)
            setPadding(dp(8), 0, dp(8), 0)
            background = cardBackground(dp(8), palette.soft, Color.TRANSPARENT)
        }
    }

    private fun switchPill(checked: Boolean): View = FrameLayout(context).apply {
        background = cardBackground(
            dp(12),
            if (checked) Color.parseColor("#18B979") else Color.parseColor("#D0D5DD"),
            Color.TRANSPARENT
        )
        addView(View(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.WHITE)
            }
        }, FrameLayout.LayoutParams(dp(18), dp(18)).apply {
            gravity = (if (checked) Gravity.END else Gravity.START) or Gravity.CENTER_VERTICAL
            marginStart = dp(2)
            marginEnd = dp(2)
        })
        layoutParams = LinearLayout.LayoutParams(dp(38), dp(22))
    }

    private fun chevron(): ImageView = ImageView(context).apply {
        setImageResource(R.drawable.ic_arrow_right)
        imageTintList = ColorStateList.valueOf(color(R.color.icon_gray))
        scaleType = ImageView.ScaleType.CENTER
        layoutParams = LinearLayout.LayoutParams(dp(20), dp(24))
    }

    private fun selectableBorderlessBackground() = context.obtainStyledAttributes(
        intArrayOf(android.R.attr.selectableItemBackgroundBorderless)
    ).let { attributes ->
        attributes.getDrawable(0).also { attributes.recycle() }
    }

    private fun cardBackground(radius: Int, fill: Int, stroke: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius.toFloat()
            setColor(fill)
            if (Color.alpha(stroke) > 0) setStroke(1, stroke)
        }

    private data class Palette(val soft: Int, val strong: Int, val border: Int)

    private fun palette(tone: ControlCenterTone): Palette = if (isNight()) {
        when (tone) {
            ControlCenterTone.GREEN -> Palette(Color.parseColor("#18382A"), Color.parseColor("#54D89A"), Color.parseColor("#24553D"))
            ControlCenterTone.BLUE -> Palette(Color.parseColor("#1D2E4A"), Color.parseColor("#76A9FF"), Color.parseColor("#29436B"))
            ControlCenterTone.AMBER -> Palette(Color.parseColor("#3D2D14"), Color.parseColor("#F4B95D"), Color.parseColor("#5C4320"))
            ControlCenterTone.RED -> Palette(Color.parseColor("#44211F"), Color.parseColor("#FF8A83"), Color.parseColor("#62302D"))
            ControlCenterTone.VIOLET -> Palette(Color.parseColor("#30274A"), Color.parseColor("#B8A1FF"), Color.parseColor("#493A70"))
            ControlCenterTone.NEUTRAL -> Palette(Color.parseColor("#2D323A"), Color.parseColor("#C7CED8"), Color.parseColor("#3E4651"))
        }
    } else {
        when (tone) {
            ControlCenterTone.GREEN -> Palette(Color.parseColor("#E8F8F0"), Color.parseColor("#14875A"), Color.parseColor("#CBEBD9"))
            ControlCenterTone.BLUE -> Palette(Color.parseColor("#EAF2FF"), Color.parseColor("#286FD6"), Color.parseColor("#D2E2FB"))
            ControlCenterTone.AMBER -> Palette(Color.parseColor("#FFF4DE"), Color.parseColor("#B26B00"), Color.parseColor("#F3D9A6"))
            ControlCenterTone.RED -> Palette(Color.parseColor("#FFEDEC"), Color.parseColor("#C7372F"), Color.parseColor("#F5CECB"))
            ControlCenterTone.VIOLET -> Palette(Color.parseColor("#F0ECFF"), Color.parseColor("#7052CC"), Color.parseColor("#DDD4FA"))
            ControlCenterTone.NEUTRAL -> Palette(Color.parseColor("#F0F3F6"), Color.parseColor("#475467"), Color.parseColor("#E2E7ED"))
        }
    }

    private fun isNight(): Boolean =
        context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES

    private fun dividerColor(): Int = color(R.color.separator)

    private fun color(resourceId: Int): Int = ContextCompat.getColor(context, resourceId)
    private fun dp(value: Int): Int = (value * context.resources.displayMetrics.density + 0.5f).toInt()
}
