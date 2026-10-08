package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SharedWorkflowCoreDeviceTest {
    @Test fun decisionsMatchSharedCore() = SharedWorkflowCoreContract.decisionParity()
    @Test fun graphAndSavedIdsRemainCompatible() = SharedWorkflowCoreContract.graphAndLegacyIdentityParity()
    @Test fun ordinaryPlansKeepNoIoFastPath() = SharedWorkflowCoreContract.noWorkspaceForOrdinaryPlans()
}
