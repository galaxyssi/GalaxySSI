package com.galaxyssi.chat

import org.junit.Test

class SharedWorkflowCoreTest {
    @Test fun decisionsMatchSharedCore() = SharedWorkflowCoreContract.decisionParity()
    @Test fun graphAndSavedIdsRemainCompatible() = SharedWorkflowCoreContract.graphAndLegacyIdentityParity()
    @Test fun ordinaryPlansKeepNoIoFastPath() = SharedWorkflowCoreContract.noWorkspaceForOrdinaryPlans()
}
