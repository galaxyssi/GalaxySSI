package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthProfileUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun fixture(test: (String, HealthProfileStore) -> Unit) {
        assumeFalse("Visible health profile acceptance requires an unlocked device", context.getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked)
        val name = "health-profile-test-${UUID.randomUUID()}.db"
        try { HealthProfileStore(context, name, privacyName(name)).use { test(name, it) } }
        finally { context.deleteDatabase(name); context.deleteDatabase(privacyName(name)) }
    }
    private fun privacyName(name: String) = name.replace("health-profile-test-", "health-privacy-test-")
    private fun <T : Activity> screen(name: String, type: Class<T>, kind: HealthBackgroundKind? = null, test: (ActivityScenario<T>) -> Unit) {
        val intent = Intent(context, type).putExtra("health_profile_test_db", name).putExtra("health_privacy_test_db", privacyName(name)); kind?.let { intent.putExtra("health_background", it.name) }
        val scenario = ActivityScenario.launch<T>(intent); lateinit var held: T
        try { scenario.onActivity { held = it }; test(scenario) }
        finally { scenario.close(); (type.getDeclaredField("worker").apply { isAccessible = true }.get(held) as ExecutorService).awaitTermination(10, TimeUnit.SECONDS) }
    }
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun <T : Activity> await(scenario: ActivityScenario<T>, condition: (T) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        do { var ready = false; scenario.onActivity { ready = condition(it) }; if (ready) return; SystemClock.sleep(40) } while (SystemClock.elapsedRealtime() < deadline)
        fail("Native health profile did not reach the expected state")
    }
    private fun tag(activity: Activity, value: String) = views(activity.window.decorView).singleOrNull { it.tag == value }
    private fun dialog(activity: HealthProfileActivity) = HealthProfileActivity::class.java.getDeclaredField("dialog").apply { isAccessible = true }.get(activity) as AlertDialog
    private fun editName(activity: HealthProfileActivity, text: String, done: Boolean = true) {
        requireNotNull(tag(activity, "health-profile-field-NAME")).performClick()
        val dialog = dialog(activity); val input = views(dialog.window!!.decorView).filterIsInstance<EditText>().single(); input.setText(text)
        if (done) dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
    }
    private fun basic(store: HealthProfileStore, field: HealthProfileField, text: String) {
        val s = store.snapshot(); store.saveBasics(HealthProfileDraft(s.generation, mapOf(field to HealthProfileInput(text)), mapOf(field to s.cells.getValue(field).token)))
    }
    @Test fun nativeProfileShowsSelfReportMissingFieldsAndNoBottomTabs(): Unit = fixture { name, _ ->
        screen(name, HealthProfileActivity::class.java) { scenario ->
            await(scenario) { tag(it, "health-profile-save") != null }
            scenario.onActivity { activity ->
                listOf(HealthProfileField.NAME, HealthProfileField.BIRTH_DATE, HealthProfileField.REFERENCE_SEX,
                    HealthProfileField.HEIGHT).forEach { assertNotNull(tag(activity, "health-profile-field-${it.name}")) }
                assertNull(tag(activity, "health-profile-field-PHYSIOLOGICAL_CONTEXT"))
                assertFalse(views(activity.window.decorView).filterIsInstance<android.widget.TextView>()
                    .any { it.text.toString() == activity.getString(R.string.health_profile_stage) })
                HealthBackgroundKind.entries.forEach { assertNotNull(tag(activity, "health-background-${it.name}")) }
                assertFalse(requireNotNull(tag(activity, "health-profile-save")).isEnabled)
                assertEquals(2, (activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup).childCount)
                assertTrue(views(activity.window.decorView).filterIsInstance<android.widget.TextView>().any { it.text.toString() == activity.getString(R.string.health_profile_source) })
            }
        }
    }
    @Test fun sexPickerOnlyOffersMaleAndFemaleAndRestoresTheSavedSelection(): Unit = fixture { name, store ->
        screen(name, HealthProfileActivity::class.java) { scenario ->
            listOf(HealthReferenceSex.MALE, HealthReferenceSex.FEMALE).forEachIndexed { index, sex ->
                await(scenario) { tag(it, "health-profile-save") != null }
                scenario.onActivity { activity ->
                    tag(activity, "health-profile-field-REFERENCE_SEX")!!.performClick()
                    val picker = dialog(activity)
                    assertEquals(2, picker.listView.adapter.count)
                    assertEquals(activity.getString(R.string.health_profile_male), picker.listView.adapter.getItem(0))
                    assertEquals(activity.getString(R.string.health_profile_female), picker.listView.adapter.getItem(1))
                    assertTrue(views(picker.window!!.decorView).filterIsInstance<android.widget.TextView>()
                        .any { it.text.toString() == activity.getString(R.string.health_profile_sex) })
                    picker.listView.performItemClick(null, index, index.toLong())
                }
                await(scenario) { tag(it, "health-profile-unsaved") != null }
                scenario.onActivity { tag(it, "health-profile-save")!!.performClick() }
                await(scenario) { tag(it, "health-profile-unsaved") == null }
                assertEquals(sex.name, store.snapshot().cells.getValue(HealthProfileField.REFERENCE_SEX).value?.text)
                scenario.recreate()
                await(scenario) { tag(it, "health-profile-save") != null }
                scenario.onActivity { activity ->
                    tag(activity, "health-profile-field-REFERENCE_SEX")!!.performClick()
                    assertEquals(index, dialog(activity).listView.checkedItemPosition)
                    dialog(activity).getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
                }
                assertNull(store.basicDraft())
            }
        }
    }
    @Test fun cancellingTheSexPickerPreservesTheExistingValue(): Unit = fixture { name, store ->
        basic(store, HealthProfileField.REFERENCE_SEX, HealthReferenceSex.FEMALE.name)
        screen(name, HealthProfileActivity::class.java) { scenario ->
            await(scenario) { tag(it, "health-profile-save") != null }
            scenario.onActivity { activity ->
                tag(activity, "health-profile-field-REFERENCE_SEX")!!.performClick()
                assertEquals(1, dialog(activity).listView.checkedItemPosition)
                dialog(activity).getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
            }
            assertNull(store.basicDraft())
            assertEquals(HealthReferenceSex.FEMALE.name, store.snapshot().cells.getValue(HealthProfileField.REFERENCE_SEX).value?.text)
        }
    }
    @Test fun editingVisibleFieldsPreservesLegacyDataWithoutRestoringRemovedSettings(): Unit = fixture { name, store ->
        basic(store, HealthProfileField.PHYSIOLOGICAL_CONTEXT, "Isolated legacy context")
        basic(store, HealthProfileField.REFERENCE_SEX, HealthReferenceSex.OTHER.name)
        screen(name, HealthProfileActivity::class.java) { scenario ->
            await(scenario) { tag(it, "health-profile-save") != null }
            scenario.onActivity { activity ->
                assertNull(tag(activity, "health-profile-field-PHYSIOLOGICAL_CONTEXT"))
                val row = tag(activity, "health-profile-field-REFERENCE_SEX")!!
                assertTrue(views(row).filterIsInstance<android.widget.TextView>()
                    .any { it.text.toString() == activity.getString(R.string.health_profile_missing) })
                row.performClick()
                assertEquals(2, dialog(activity).listView.adapter.count)
                assertEquals(-1, dialog(activity).listView.checkedItemPosition)
                dialog(activity).getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
                editName(activity, "Updated isolated profile")
            }
            await(scenario) { tag(it, "health-profile-unsaved") != null }
            scenario.onActivity { tag(it, "health-profile-save")!!.performClick() }
            await(scenario) { tag(it, "health-profile-unsaved") == null }
            val cells = store.snapshot().cells
            assertEquals("Updated isolated profile", cells.getValue(HealthProfileField.NAME).value?.text)
            assertEquals("Isolated legacy context", cells.getValue(HealthProfileField.PHYSIOLOGICAL_CONTEXT).value?.text)
            assertEquals(HealthReferenceSex.OTHER.name, cells.getValue(HealthProfileField.REFERENCE_SEX).value?.text)
        }
    }
    @Test fun stagedNameIsExplicitlySavedAndRestoredFromTheEncryptedProfile(): Unit = fixture { name, store ->
        screen(name, HealthProfileActivity::class.java) { scenario ->
            await(scenario) { tag(it, "health-profile-save") != null }; scenario.onActivity { editName(it, "Isolated profile test") }
            await(scenario) { tag(it, "health-profile-unsaved") != null }; assertNull(store.snapshot().cells.getValue(HealthProfileField.NAME).value)
            scenario.onActivity { tag(it, "health-profile-save")!!.performClick() }
            await(scenario) { tag(it, "health-profile-unsaved") == null && (tag(it, "health-profile-name") as? android.widget.TextView)?.text.toString() == "Isolated profile test" }
            assertEquals("Isolated profile test", store.snapshot().cells.getValue(HealthProfileField.NAME).value!!.text)
            scenario.recreate(); await(scenario) { (tag(it, "health-profile-name") as? android.widget.TextView)?.text.toString() == "Isolated profile test" }
        }
    }
    @Test fun cancelRestoresThePreviousDraftInsteadOfKeepingAutosavedCancelledText(): Unit = fixture { name, store ->
        basic(store, HealthProfileField.NAME, "Original")
        screen(name, HealthProfileActivity::class.java) { scenario ->
            await(scenario) { tag(it, "health-profile-save") != null }; scenario.onActivity { editName(it, "Cancelled edit", false) }; SystemClock.sleep(550)
            scenario.onActivity { dialog(it).getButton(AlertDialog.BUTTON_NEGATIVE).performClick() }
            await(scenario) { tag(it, "health-profile-unsaved") == null && (tag(it, "health-profile-name") as? android.widget.TextView)?.text.toString() == "Original" }
            assertNull(store.basicDraft()); assertEquals("Original", store.snapshot().cells.getValue(HealthProfileField.NAME).value!!.text)
        }
    }
    @Test fun backgroundClearsSensitiveViewsAndAnUntouchedEditorDoesNotCreateADraft(): Unit = fixture { name, store ->
        screen(name, HealthProfileActivity::class.java) { scenario ->
            await(scenario) { tag(it, "health-profile-save") != null }; scenario.onActivity { activity ->
                tag(activity, "health-profile-field-NAME")!!.performClick(); val input = views(dialog(activity).window!!.decorView).filterIsInstance<EditText>().single()
                assertFalse(input.isSaveEnabled); assertTrue(input.imeOptions and android.view.inputmethod.EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING != 0)
            }
            scenario.moveToState(Lifecycle.State.CREATED); scenario.onActivity { activity ->
                assertEquals(0, ((activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup).getChildAt(1) as ViewGroup).childCount)
            }
            scenario.moveToState(Lifecycle.State.RESUMED); await(scenario) { tag(it, "health-profile-save") != null }; assertNull(store.basicDraft())
        }
    }
    @Test fun medicationIsSavedThroughTheActualNativeEditorWithoutDoseCalculation(): Unit = fixture { name, store ->
        screen(name, HealthBackgroundActivity::class.java, HealthBackgroundKind.MEDICATION) { scenario ->
            await(scenario) { tag(it, "health-background-add") != null }; scenario.onActivity { tag(it, "health-background-add")!!.performClick() }
            await(scenario) { tag(it, "health-background-save") != null }; scenario.onActivity { activity ->
                (tag(activity, "health-background-name") as EditText).setText("Isolated supplement")
                (tag(activity, "health-background-dose") as EditText).setText("as prescribed")
                (tag(activity, "health-background-timing") as EditText).setText("after breakfast")
                tag(activity, "health-background-save")!!.performClick()
            }
            await(scenario) { tag(it, "health-background-add") != null && tag(it, "health-background-empty") == null }
            val entry = store.page(HealthBackgroundKind.MEDICATION).entries.single(); assertEquals("as prescribed", entry.dose); assertEquals("after breakfast", entry.timing)
        }
    }
    @Test fun deletingTheProfileClearsAnAlreadyOpenBackgroundEditorWithoutResurrection(): Unit = fixture { name, store ->
        val d = store.newEntry(HealthBackgroundKind.ALLERGY); store.saveEntry(d.copy(entry = d.entry.copy(name = "Isolated allergy")))
        screen(name, HealthBackgroundActivity::class.java, HealthBackgroundKind.ALLERGY) { scenario ->
            await(scenario) { tag(it, "health-background-add") != null }; scenario.onActivity { activity ->
                val title = views(activity.window.decorView).filterIsInstance<android.widget.TextView>().single { it.text.toString() == "Isolated allergy" }; (title.parent.parent as View).performClick()
            }
            await(scenario) { tag(it, "health-background-save") != null }; store.clear(store.deletePreview())
            await(scenario) { tag(it, "health-background-empty") != null && tag(it, "health-background-name") == null }
            assertEquals(0L, store.count(HealthBackgroundKind.ALLERGY)); assertEquals(0L, store.deletePreview().drafts)
        }
    }
    @Test fun nativeDeleteShowsTheScopeAndClearsOnlyTheIsolatedProfile(): Unit = fixture { name, store ->
        basic(store, HealthProfileField.NAME, "Isolated profile")
        val d = store.newEntry(HealthBackgroundKind.HISTORY); store.saveEntry(d.copy(entry = d.entry.copy(name = "Isolated history")))
        screen(name, HealthProfileActivity::class.java) { scenario ->
            await(scenario) { tag(it, "health-profile-delete") != null }; scenario.onActivity { tag(it, "health-profile-delete")!!.performClick() }
            await(scenario) { runCatching { dialog(it).isShowing }.getOrDefault(false) }
            scenario.onActivity { activity ->
                assertTrue(views(dialog(activity).window!!.decorView).filterIsInstance<android.widget.TextView>().any { it.text.toString().contains(activity.getString(R.string.health_profile_delete_preview, 1, 1L, 0L)) })
                dialog(activity).getButton(AlertDialog.BUTTON_POSITIVE).performClick()
            }
            await(scenario) { (tag(it, "health-profile-name") as? android.widget.TextView)?.text.toString() == it.getString(R.string.health_profile_self) }
            assertTrue(store.snapshot().cells.values.all { it.value == null }); assertEquals(0L, store.count(HealthBackgroundKind.HISTORY))
        }
    }
}
