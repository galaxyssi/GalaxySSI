package com.galaxyssi.chat

import kotlin.math.floor
import kotlin.math.roundToInt

internal object HealthAtlasUreterDeliveryTeachingModel {
    const val PACKETS = 6
    private const val MAX_PACKET_ML = 3.0

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(HealthAtlasInput("ureter-delivery-pushes", 0..PACKETS, 3),
                R.string.health_atlas_ureter_delivery_pushes, "", digits = 0),
            HealthAtlasTeachingInput(HealthAtlasInput("ureter-delivery-volume", 5..30, 20, 10.0),
                R.string.health_atlas_ureter_delivery_per_push, "mL", digits = 1),
        ),
        axis = 0,
        unit = "mL",
        minimum = 0.0,
        maximum = PACKETS * MAX_PACKET_ML,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-2-gross-anatomy-of-urine-transport",
        title = R.string.health_atlas_ureter_delivery_title,
        scope = R.string.health_atlas_ureter_delivery_scope,
        formula = R.string.health_atlas_ureter_delivery_formula,
        companionTitle = R.string.health_atlas_ureter_delivery_remaining,
        entryIds = setOf("renal-pelvis", "ureters"),
        evaluate = { (count, amount) -> count.roundToInt() * amount },
        companionValue = { (count, amount) -> (PACKETS - count.roundToInt()) * amount },
    )

    data class Frame(val arrived: Int, val inTransit: Float?)

    fun frame(selected: Int, phase: Float): Frame {
        val position = selected * phase
        val whole = floor(position).toInt()
        return Frame(whole, if (whole < selected) position - whole else null)
    }
}
