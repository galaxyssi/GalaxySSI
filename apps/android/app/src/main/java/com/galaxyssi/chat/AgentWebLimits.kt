package com.galaxyssi.chat

internal const val AGENT_WEB_MAX_FETCH_BYTES = 10L * 1_048_576L

internal val AGENT_WEB_ADDITIONAL_REQUEST_HEADERS = setOf(
    "accept",
    "accept-language",
    "api-key",
    "authorization",
    "referer",
    "user-agent",
    "x-github-api-version",
    "x-subscription-token"
)
