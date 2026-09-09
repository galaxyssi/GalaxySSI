package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentPlanDispatchLoopTest {
    @Test fun hundredThousandContinuationsHaveConstantStackAndNoCountCutoff() {
        val loop = AgentPlanDispatchLoop<Int>()
        var completed = 0
        var depth = 0
        var maximumDepth = 0
        lateinit var dispatch: () -> Int
        dispatch = {
            loop.run({ completed }, { true }) {
                depth++
                maximumDepth = maxOf(maximumDepth, depth)
                try {
                    completed++
                    if (completed < 100_000) dispatch() else completed
                } finally { depth-- }
            }
        }
        assertEquals(100_000, dispatch())
        assertEquals(1, maximumDepth)
        assertEquals(0, depth)
    }

    @Test fun duplicateNextRequestsCoalesceInsteadOfDuplicatingWork() {
        val loop = AgentPlanDispatchLoop<Int>()
        var completed = 0
        lateinit var dispatch: () -> Int
        dispatch = {
            loop.run({ completed }, { true }) {
                completed++
                if (completed == 1) { assertEquals(1, dispatch()); assertEquals(1, dispatch()) }
                completed
            }
        }
        assertEquals(2, dispatch())
    }

    @Test fun pauseOrScopeChangeStopsRequestedWorkAndReturnsCurrentState() {
        val loop = AgentPlanDispatchLoop<String>()
        var current = "planning"
        var calls = 0
        lateinit var dispatch: () -> String
        dispatch = {
            loop.run({ current }, { current == "planning" }) {
                calls++
                dispatch()
                current = "paused"
                "stale planning snapshot"
            }
        }
        assertEquals("paused", dispatch())
        assertEquals(1, calls)
    }

    @Test fun waitingWithoutAnotherDispatchReturnsImmediately() {
        val loop = AgentPlanDispatchLoop<String>()
        var calls = 0
        assertEquals("waiting", loop.run({ "current" }, { error("No continuation was requested") }) {
            calls++
            "waiting"
        })
        assertEquals(1, calls)
    }

    @Test fun exceptionReleasesTheFrameWithoutReplayingPendingWork() {
        val loop = AgentPlanDispatchLoop<Int>()
        assertThrows(IllegalStateException::class.java) {
            loop.run({ 0 }, { true }) {
                loop.run({ 0 }, { true }) { fail("Must defer"); 0 }
                error("Actual tool failure")
            }
        }
        assertEquals(7, loop.run({ 0 }, { true }) { 7 })
    }

    @Test fun independentAgentsDoNotShareDispatchFrames() {
        val first = AgentPlanDispatchLoop<Int>()
        val second = AgentPlanDispatchLoop<Int>()
        var otherCalls = 0
        assertEquals(9, first.run({ 0 }, { true }) {
            second.run({ 0 }, { true }) { otherCalls++; 9 }
        })
        assertEquals(1, otherCalls)
    }
}
