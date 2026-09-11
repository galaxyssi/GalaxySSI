package com.galaxyssi.chat

import android.app.Application
import android.content.Context
import android.os.Build
import android.webkit.WebView

class GalaxySSIApplication : Application() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            AgentWebRendererProcessPolicy.isRenderer(base.packageName, getProcessName())) {
            // Providers and services must not initialize WebView before its process-local directory.
            AgentWebRendererBootstrap.error = try {
                WebView.setDataDirectorySuffix(AgentWebRendererProcessPolicy.DIRECTORY_SUFFIX)
                null
            } catch (error: RuntimeException) {
                "renderer_initialization_failed:${error.javaClass.simpleName}"
            } catch (error: LinkageError) {
                "renderer_initialization_failed:${error.javaClass.simpleName}"
            }
        }
    }
}

internal object AgentWebRendererBootstrap {
    var error: String? = "renderer_process_not_configured"
        internal set
}
