package com.galaxyssi.chat

/** Published guest API v1 identifiers are binary contracts, not product branding. */
internal object AgentRuntimeGuestAbi {
    const val CHANNEL = "org.signalasi.runtime"
    const val SESSION = "opt/com.signalasi/runtime-session"
    const val CONFIG = "opt/com.signalasi/runtime-config"
    const val WORKSPACE_MOUNT = "signalasi_workspaces"
    const val SYSTEM_ROOT = "/var/lib/signalasi"
    const val CONTROL_DIRECTORY = ".signalasi-runtime"
}
