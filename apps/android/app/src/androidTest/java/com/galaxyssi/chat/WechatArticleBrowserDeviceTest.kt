package com.galaxyssi.chat

import android.view.ViewGroup
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

@RunWith(AndroidJUnit4::class)
class WechatArticleBrowserDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val page = "https://mp.weixin.qq.com/s/galaxyssi-browser-test"

    @Test fun waitsForDynamicArticleAndLazyImageThenDeliversOnce() {
        val done = CountDownLatch(1)
        val calls = AtomicInteger()
        var result = ""
        withBrowser({ _, html -> result = html; calls.incrementAndGet(); done.countDown() }, { fail("Unexpected verification") }) { browser ->
            load(browser, """<html><body><h1 id="activity-name">Fixture article</h1><div id="js_content">First
                <img data-src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aEuoAAAAASUVORK5CYII="></div>
                <script>setTimeout(() => document.querySelector('#js_content').append(' LAST_PARAGRAPH'), 1000)</script></body></html>""")
            assertTrue("Browser did not deliver", done.await(15, TimeUnit.SECONDS))
            assertTrue(result.contains("LAST_PARAGRAPH"))
            assertTrue(result.contains("data:image/png"))
            Thread.sleep(1700)
            assertEquals(1, calls.get())
        }
    }

    @Test fun verificationPausesUntilExplicitContinueAndReusesDocument() {
        val verify = CountDownLatch(1)
        val done = CountDownLatch(1)
        withBrowser({ _, _ -> done.countDown() }, { verify.countDown() }) { browser ->
            load(browser, "<html><body><button id='js_verify'>Fixture verification</button></body></html>")
            assertTrue(verify.await(10, TimeUnit.SECONDS))
            assertFalse(done.await(1200, TimeUnit.MILLISECONDS))
            // A local fixture, not a real verification challenge.
            instrumentation.runOnMainSync {
                browser.view.loadDataWithBaseURL(page, "<h1 id='activity-name'>Verified fixture</h1><div id='js_content'>Full body</div>", "text/html", "UTF-8", page)
            }
            assertFalse(done.await(1200, TimeUnit.MILLISECONDS))
            instrumentation.runOnMainSync { browser.continueAfterVerification() }
            assertTrue(done.await(10, TimeUnit.SECONDS))
        }
    }

    @Test fun closingPreventsLateDelivery() {
        val done = CountDownLatch(1)
        withBrowser({ _, _ -> done.countDown() }, { done.countDown() }) { browser ->
            load(browser, "<h1 id='activity-name'>Fixture</h1><div id='js_content'>Body</div>")
            instrumentation.runOnMainSync {
                (browser.view.parent as? ViewGroup)?.removeView(browser.view)
                browser.close()
            }
            assertFalse(done.await(2500, TimeUnit.MILLISECONDS))
        }
    }

    private fun load(browser: WechatArticleBrowser, html: String) = instrumentation.runOnMainSync {
        browser.view.loadDataWithBaseURL(page, html, "text/html", "UTF-8", page)
        browser.observeLoadedPage()
    }

    private fun withBrowser(result: (String, String) -> Unit, verify: () -> Unit, test: (WechatArticleBrowser) -> Unit) {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var browser: WechatArticleBrowser
            scenario.onActivity { activity ->
                browser = WechatArticleBrowser(activity, result, verify) { fail("Browser failed") }
                activity.findViewById<ViewGroup>(android.R.id.content).addView(browser.view, ViewGroup.LayoutParams(800, 1000))
            }
            try { test(browser) } finally {
                instrumentation.runOnMainSync {
                    (browser.view.parent as? ViewGroup)?.removeView(browser.view)
                    browser.close()
                }
            }
        }
    }
}
