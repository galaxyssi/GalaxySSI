package com.galaxyssi.chat

import android.util.Log
import androidx.test.runner.AndroidJUnitRunner
import androidx.work.Configuration
import androidx.work.testing.WorkManagerTestInitHelper

/** Only compiled by isolated.init.gradle; never included in the shipping APK. */
class MqttIsolatedTestRunner : AndroidJUnitRunner() {
    override fun onStart() {
        check(targetContext.packageName == "com.galaxyssi.chat.mqttverification") {
            "Isolated verification must not initialize work in production app storage"
        }
        WorkManagerTestInitHelper.initializeTestWorkManager(
            targetContext,
            Configuration.Builder().setMinimumLoggingLevel(Log.INFO).build(),
            WorkManagerTestInitHelper.ExecutorsMode.PRESERVE_EXECUTORS
        )
        super.onStart()
    }
}
