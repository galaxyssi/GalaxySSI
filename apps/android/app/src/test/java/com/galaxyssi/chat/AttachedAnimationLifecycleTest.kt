package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AttachedAnimationLifecycleTest {
    @Test
    fun repeatedAttachAndDetachEventsAreIdempotent() {
        var starts = 0
        var stops = 0
        val lifecycle = AttachedAnimationLifecycle(
            startAnimation = { starts += 1 },
            stopAnimation = { stops += 1 }
        )

        lifecycle.updateAttached(true)
        lifecycle.updateAttached(true)
        lifecycle.updateAttached(false)
        lifecycle.updateAttached(false)
        lifecycle.updateAttached(true)

        assertEquals(2, starts)
        assertEquals(1, stops)
    }

    @Test
    fun detachedInitialStateDoesNotInvokeAnimationCallbacks() {
        var callbacks = 0
        val lifecycle = AttachedAnimationLifecycle(
            startAnimation = { callbacks += 1 },
            stopAnimation = { callbacks += 1 }
        )

        lifecycle.updateAttached(false)

        assertEquals(0, callbacks)
    }
}
