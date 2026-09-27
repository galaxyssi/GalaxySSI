package com.galaxyssi.chat

internal object PhoneUiMutationRisk {
    private val sensitive = Regex("(?i)(\\b(?:send|delete|remove|pay|purchase|transfer|submit)\\b|\u53d1\u9001|\u5220\u9664|\u79fb\u9664|\u652f\u4ed8|\u8f6c\u8d26|\u4ed8\u6b3e|\u4e0b\u5355|\u786e\u8ba4\u8d2d\u4e70|\u63d0\u4ea4)")
    fun requiresConfirmation(operation: String, text: String, description: String): Boolean =
        operation in setOf("click", "long_click") && sensitive.containsMatchIn("$text $description")
}
