package com.galaxyssi.chat

import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AboutPageUiDeviceTest {
    @Test fun productSectionStartsPageWithoutDuplicateHero() = withAboutPage { activity ->
        assertEquals(activity.getString(R.string.settings_about_galaxyssi), activity.featureTitle.text.toString())
        val texts = descendants(activity.featureContent).filterIsInstance<TextView>().map { it.text.toString() }
        assertEquals(activity.getString(R.string.about_section_product), texts.first())
        assertFalse(texts.contains(activity.getString(R.string.app_name)))
        assertFalse(texts.contains(activity.getString(R.string.about_product_subtitle)))
        assertTrue(texts.contains(activity.getString(R.string.about_section_trust)))
        assertTrue(texts.contains(activity.getString(R.string.about_open_source)))
        assertEquals(1, texts.count { it == installedVersion(activity) })
    }

    @Test fun installedVersionIsCompleteAndNotAnAction() = withAboutPage { activity ->
        val row = versionRow(activity)
        measureRow(row, activity.dp(360))
        val value = descendants(row).filterIsInstance<TextView>().single { it.text.toString() == installedVersion(activity) }
        assertFullyVisible(value)
        assertEquals(1, value.lineCount)
        assertFalse(row.isClickable)
        assertFalse(value.isClickable)
    }

    @Test fun narrowLayoutWithLargeTextKeepsEveryVersionCharacterVisible() = withAboutPage { activity ->
        val row = versionRow(activity)
        descendants(row).filterIsInstance<TextView>().forEach {
            it.setTextSize(TypedValue.COMPLEX_UNIT_PX, it.textSize * 2f)
        }
        measureRow(row, activity.dp(280))
        descendants(row).filterIsInstance<TextView>().forEach(::assertFullyVisible)
    }

    @Test fun protocolAndSecurityActionsRemainAvailable() = withAboutPage { activity ->
        val protocol = descendants(activity.featureContent).filterIsInstance<TextView>()
            .single { it.text.toString() == activity.getString(R.string.settings_signal_link_protocol) }
        val protocolRow = protocol.parent.parent as View
        assertTrue(protocolRow.isClickable)
        assertTrue(protocolRow.performClick())
        assertEquals("Signal Link Protocol", activity.featureTitle.text.toString())
        activity.showAboutGalaxySSIPage()
        val security = descendants(activity.featureContent).filterIsInstance<TextView>()
            .single { it.text.toString() == activity.getString(R.string.about_security) }
        val securityRow = security.parent.parent as View
        assertTrue(securityRow.isClickable)
        assertTrue(securityRow.performClick())
        activity.featureBackButton.performClick()
        assertEquals(activity.getString(R.string.settings_about_galaxyssi), activity.featureTitle.text.toString())
    }

    private fun withAboutPage(check: (MainActivity) -> Unit) {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.showMainTab(PAGE_SETTINGS)
                activity.showAboutGalaxySSIPage()
                check(activity)
            }
        }
    }

    private fun installedVersion(activity: MainActivity): String =
        "v${activity.packageManager.getPackageInfo(activity.packageName, 0).versionName}"

    private fun versionRow(activity: MainActivity): View =
        descendants(activity.featureContent).filterIsInstance<TextView>()
            .single { it.text.toString() == installedVersion(activity) }.parent as View

    private fun measureRow(row: View, width: Int) {
        row.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        row.layout(0, 0, row.measuredWidth, row.measuredHeight)
    }

    private fun assertFullyVisible(text: TextView) {
        val layout = requireNotNull(text.layout)
        assertTrue(layout.lineCount > 0)
        assertEquals(text.text.length, layout.getLineEnd(layout.lineCount - 1))
        assertTrue(layout.lineCount <= text.maxLines)
        assertTrue(layout.height <= text.height - text.compoundPaddingTop - text.compoundPaddingBottom)
        for (line in 0 until layout.lineCount) {
            assertEquals(0, layout.getEllipsisCount(line))
            assertTrue(layout.getLineMax(line) <= text.width - text.compoundPaddingLeft - text.compoundPaddingRight + 1)
        }
    }

    private fun descendants(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
