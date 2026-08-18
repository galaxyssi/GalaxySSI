package com.signalasi.chat

import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRuntimeShellBootstrapTest {
    @Test
    fun shellTasksPrepareHomeAndTempBeforeUserSource() {
        val wrapped = AgentRuntimeShellBootstrap.wrap(
            source = "printf 'ready\\n'",
            guestToolBin = "/workspace/project/.signalasi-tools/bin"
        )

        val home = wrapped.indexOf("mkdir -p \"${'$'}HOME\"")
        val temp = wrapped.indexOf("mkdir -p \"${'$'}TMPDIR\"")
        val userSource = wrapped.indexOf("printf 'ready\\n'")
        assertTrue(home >= 0)
        assertTrue(temp > home)
        assertTrue(userSource > temp)
    }
}
