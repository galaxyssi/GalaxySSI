package com.signalasi.chat

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.View
import com.signalasi.chat.ui.ConnectingStartupView
import kotlin.concurrent.thread

class StartupActivity : Activity() {
    private var mainActivityLaunched = false
    private lateinit var connectingView: ConnectingStartupView
    private val launchMainActivityRunnable = Runnable(::launchMainActivity)

    override fun onCreate(savedInstanceState: Bundle?) {
        AppDisplaySettings.applyToResources(this)
        super.onCreate(savedInstanceState)
        configureWindow()

        connectingView = ConnectingStartupView(this).apply {
            setBackgroundColor(getColor(R.color.page_bg))
        }
        setContentView(connectingView)

        thread(name = "signalasi-startup-prewarm") {
            runCatching { AppStore.ensureInitialized(applicationContext) }
            runCatching { AgentEvalReliabilityHarness.initialize(applicationContext) }
        }
        connectingView.postDelayed(launchMainActivityRunnable, STARTUP_HANDOFF_DELAY_MILLIS)
    }

    override fun onDestroy() {
        if (::connectingView.isInitialized) {
            connectingView.removeCallbacks(launchMainActivityRunnable)
        }
        super.onDestroy()
    }

    private fun launchMainActivity() {
        if (mainActivityLaunched || isFinishing || isDestroyed) return
        mainActivityLaunched = true
        startActivity(Intent(this, MainActivity::class.java).apply {
            data = intent?.data
            intent?.extras?.let(::putExtras)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        })
        overridePendingTransition(0, 0)
        finish()
    }

    private fun configureWindow() {
        window.statusBarColor = getColor(R.color.bar_bg)
        window.navigationBarColor = getColor(R.color.bar_bg)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val isNight = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
                Configuration.UI_MODE_NIGHT_YES
            var flags = if (isNight) 0 else View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            if (!isNight && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                flags = flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
            }
            window.decorView.systemUiVisibility = flags
        }
    }

    private companion object {
        const val STARTUP_HANDOFF_DELAY_MILLIS = 300L
    }
}
