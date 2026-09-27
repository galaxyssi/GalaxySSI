package com.galaxyssi.chat

internal data class PhoneUiWindowCandidate(
    val id: Int, val packageName: String, val application: Boolean,
    val focused: Boolean, val active: Boolean, val layer: Int
)

internal object PhoneUiObservationPolicy {
    fun canMutatePackage(packageName: String): Boolean = packageName !in setOf(
        "com.android.permissioncontroller", "com.google.android.permissioncontroller",
        "com.samsung.android.permissioncontroller", "com.android.systemui"
    )

    fun select(windows: List<PhoneUiWindowCandidate>, ownPackage: String, externalOnly: Boolean): Int? =
        windows.asSequence()
            .filter { it.application && it.packageName.isNotBlank() }
            .filter { !externalOnly || it.packageName != ownPackage }
            .maxWithOrNull(compareBy<PhoneUiWindowCandidate> { it.focused }.thenBy { it.active }.thenBy { it.layer })
            ?.id

    fun accepts(windowId: Int, revision: String, currentWindow: Int, currentRevision: String): Boolean =
        windowId >= 0 && revision.isNotBlank() && windowId == currentWindow && revision == currentRevision
}
