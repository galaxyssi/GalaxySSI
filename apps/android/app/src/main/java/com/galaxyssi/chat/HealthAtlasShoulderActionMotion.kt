package com.galaxyssi.chat

import com.galaxyssi.chat.HealthAtlasLatissimusActionAssignment as Latissimus
import com.galaxyssi.chat.HealthAtlasPectoralActionAssignment as Pectoral
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

private fun ease(t: Float) = t * t * (3f - 2f * t)

internal object HealthAtlasPectoralActionMotion {
    const val START_ANGLE = -12f
    const val SWEEP_ANGLE = 122f

    // Values describe drawing poses, not measured joint angles.
    fun angle(chapter: Int, fraction: Float): Float {
        val t = ease(fraction)
        val progress = when (chapter) {
            Pectoral.SWEEP -> .48f * t
            Pectoral.ACROSS -> .48f + .52f * t
            Pectoral.RETURN -> 1f - t
            else -> 0f
        }
        return START_ANGLE + SWEEP_ANGLE * progress
    }
}

internal object HealthAtlasLatissimusActionMotion {
    private const val FORWARD_ANGLE = 1.18f
    private const val BACK_ANGLE = -.12f
    private const val UPPER_LATERAL = .52f
    private const val LOWER_LATERAL = .10f
    private val anteriorRadius = sqrt(1f - UPPER_LATERAL * UPPER_LATERAL)
    private val backDepth = anteriorRadius * sin(BACK_ANGLE)

    fun pose(chapter: Int, fraction: Float) = when (chapter) {
        Latissimus.EXTEND -> ease(fraction)
        Latissimus.ADDUCT -> 1f + ease(fraction)
        Latissimus.RETURN -> if (fraction < .5f) 2f - ease(fraction * 2f) else 1f - ease(fraction * 2f - 1f)
        else -> 0f
    }

    fun project(pose: Float, out: FloatArray) {
        // Extension rotates in a sagittal slice. Adduction then rotates in a frontal slice.
        val lateral: Float
        val anterior: Float
        val down: Float
        if (pose <= 1f) {
            val angle = FORWARD_ANGLE + (BACK_ANGLE - FORWARD_ANGLE) * pose
            lateral = UPPER_LATERAL
            anterior = anteriorRadius * sin(angle)
            down = anteriorRadius * cos(angle)
        } else {
            lateral = UPPER_LATERAL + (LOWER_LATERAL - UPPER_LATERAL) * (pose - 1f)
            anterior = backDepth
            down = sqrt(1f - lateral * lateral - anterior * anterior)
        }
        out[0] = .65f * lateral + .76f * anterior
        out[1] = .98f * down + .15f * lateral - .13f * anterior
    }
}
