package com.galaxyssi.chat

import android.app.Activity
import android.app.Dialog
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView

internal class HealthAtlasAnatomyDialog(
    private val activity: Activity,
    private val data: HealthBodyAtlas,
    private val currentId: String?,
    private val plate: HealthAtlasPlate,
    private val description: String,
    private val selected: (HealthAtlasItem) -> Unit,
) : Dialog(activity, android.R.style.Theme_Material_Light_NoActionBar) {
    private val ui = HealthCenterViews(activity)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val labeled = if (plate.hasLabels) {
            HealthAtlasLabeledImage(activity, plate, description, data, currentId) { item ->
                dismiss()
                selected(item)
            }.also { it.image.tag = "atlas-fullscreen-image" }
        } else null
        // At large text sizes a full rail can be taller than the dialog, particularly in landscape.
        val scroll = labeled?.let { display ->
            ScrollView(activity).apply {
                isFillViewport = true
                isVerticalScrollBarEnabled = false
                addView(display, android.widget.FrameLayout.LayoutParams(-1, -2))
            }
        }
        val target: View = scroll ?: ImageView(activity).apply {
            setImageResource(plate.drawable)
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = description
            tag = "atlas-fullscreen-image"
        }
        val viewport = GalaxySSIPinchZoomViewport(activity, keepZoomedTargetTaps = labeled != null).apply {
            tag = "atlas-fullscreen-viewport"
            attach(target)
        }
        val close = { dismiss() }
        val root = ui.column().apply {
            setBackgroundColor(activity.getColor(R.color.page_bg))
            addView(ui.toolbar(R.string.health_body_title, close))
            addView(HealthAtlasFigureFrame(activity, viewport, "atlas-fullscreen-figure",
                subject = labeled?.image ?: target as? ImageView).apply {
                HealthAtlasUi.illustrationNotes(activity, legend, description, null)
            }, LinearLayout.LayoutParams(-1, 0, 1f))
            addView(ui.line().apply {
                gravity = Gravity.END
                if (labeled != null) {
                    val toggle = ui.icon(R.drawable.ic_input_menu_layers, R.string.health_atlas_hide_labels) {
                        labeled.showLabels(!labeled.labelsShown)
                        updateLabelButton(findViewWithTag("atlas-fullscreen-labels"), labeled.labelsShown)
                    }
                    toggle.tag = "atlas-fullscreen-labels"
                    updateLabelButton(toggle, true)
                    addView(toggle)
                }
                addView(ui.icon(R.drawable.ic_reset_data, R.string.health_atlas_reset) {
                    viewport.resetZoom()
                    scroll?.scrollTo(0, 0)
                }.apply { tag = "atlas-fullscreen-reset" })
            })
        }
        setContentView(root)
    }

    override fun onStart() {
        super.onStart()
        window?.setLayout(-1, -1)
    }

    private fun updateLabelButton(button: View, labelsShown: Boolean) {
        button.isSelected = labelsShown
        button.contentDescription = activity.getString(
            if (labelsShown) R.string.health_atlas_hide_labels else R.string.health_atlas_show_labels,
        )
        button.tooltipText = button.contentDescription
    }
}
