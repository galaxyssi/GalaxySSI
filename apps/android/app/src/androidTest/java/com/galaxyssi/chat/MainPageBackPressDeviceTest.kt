package com.galaxyssi.chat

import android.os.SystemClock
import android.view.MotionEvent
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MainPageBackPressDeviceTest {
    @Test fun onePressStaysAndTwoPressesBackgroundWithoutFinishing() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            prepare(scenario)
            scenario.onActivity { it.onBackPressed() }
            assertEquals(Lifecycle.State.RESUMED, scenario.state)
            scenario.onActivity {
                it.onBackPressed()
                assertFalse(it.isFinishing)
                assertFalse(it.isDestroyed)
            }
            awaitBackground(scenario)
        }
    }

    @Test fun aPressAfterHalfASecondDoesNotBackground() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            prepare(scenario)
            scenario.onActivity { it.onBackPressed() }
            Thread.sleep(600)
            scenario.onActivity { it.onBackPressed() }
            assertEquals(Lifecycle.State.RESUMED, scenario.state)
            scenario.onActivity { it.onBackPressed() }
            awaitBackground(scenario)
        }
    }

    @Test fun returningFromSettingsDoesNotCountAsTheFirstPress() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            prepare(scenario)
            scenario.onActivity {
                it.onBackPressed()
                it.showMainTab(PAGE_SETTINGS)
                it.onBackPressed()
                assertEquals(PAGE_AGENT, it.activeMainTab)
                it.onBackPressed()
            }
            assertEquals(Lifecycle.State.RESUMED, scenario.state)
        }
    }

    @Test fun closingTheActionTrayDoesNotCountAsTheFirstPress() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            prepare(scenario)
            scenario.onActivity {
                it.onBackPressed()
                it.setAgentActionTrayExpanded(true)
                it.onBackPressed()
                assertFalse(it.agentActionTrayExpanded)
                it.onBackPressed()
            }
            assertEquals(Lifecycle.State.RESUMED, scenario.state)
        }
    }

    @Test fun completedTouchClearsTheFirstPress() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            prepare(scenario)
            scenario.onActivity {
                it.onBackPressed()
                touch(it, MotionEvent.ACTION_UP)
                it.onBackPressed()
            }
            assertEquals(Lifecycle.State.RESUMED, scenario.state)
        }
    }

    @Test fun closingTheComposerDoesNotCountAsTheFirstPress() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            prepare(scenario)
            scenario.onActivity {
                it.onBackPressed()
                it.enterAgentComposerTextMode()
                it.onBackPressed()
                assertFalse(it.agentComposerTextMode)
                it.onBackPressed()
            }
            assertEquals(Lifecycle.State.RESUMED, scenario.state)
        }
    }

    @Test fun cancelledGestureDoesNotClearTheFirstPress() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            prepare(scenario)
            scenario.onActivity {
                it.onBackPressed()
                touch(it, MotionEvent.ACTION_CANCEL)
                it.onBackPressed()
            }
            awaitBackground(scenario)
        }
    }

    private fun prepare(scenario: ActivityScenario<MainActivity>) {
        val deadline = SystemClock.elapsedRealtime() + 15000
        var ready = false
        while (!ready && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { ready = !it.initialAgentHydrationPending && !it.runtimePlaintextCleared }
            if (!ready) Thread.sleep(50)
        }
        assertTrue("Initial transcript hydration must complete", ready)
        scenario.onActivity {
            it.showMainTab(PAGE_AGENT)
            it.setAgentActionTrayExpanded(false)
            it.exitAgentComposerTextMode(hideKeyboard = true)
            it.agentComposerKeyboardClosedAt = 0L
            it.chatComposerKeyboardClosedAt = 0L
            it.mainPageBackPressGate.reset()
        }
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    }

    private fun awaitBackground(scenario: ActivityScenario<MainActivity>) {
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (scenario.state == Lifecycle.State.RESUMED && SystemClock.elapsedRealtime() < deadline) Thread.sleep(50)
        assertTrue("The task must be backgrounded without finishing its Activity",
            scenario.state == Lifecycle.State.CREATED || scenario.state == Lifecycle.State.STARTED)
    }

    private fun touch(activity: MainActivity, end: Int) {
        val now = SystemClock.uptimeMillis()
        for (action in listOf(MotionEvent.ACTION_DOWN, end)) {
            val event = MotionEvent.obtain(now, now, action, 1f, 1f, 0)
            try { activity.dispatchTouchEvent(event) } finally { event.recycle() }
        }
    }
}
