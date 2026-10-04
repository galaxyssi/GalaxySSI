package com.galaxyssi.chat

internal object CollaborationRetentionProtocol {
    fun instructions() = """
        Preserve demonstrated capabilities across improvements. Freeze retained experiment cases in capability_suite; compare new methods
        against the active version AND original measured anchors. Do not discard old tasks, loosen criteria or reset a moving baseline.
        capability_channel records select exact reviewed implementations; new work may bind that channel, while existing work stays pinned.
        Regression means investigate, revise or select a preserved version, not stop the user's goal. No retry count selects a strategy.
    """.trimIndent()

    fun rules() = """
        capability_suite:{lesson:exact retained capability_lesson,scope,limitations,previous_suite?:exact capability_suite}.
        Every case in the lesson's experiment must have dataset:exact immutable artifact; every original sample carries dataset_sha256.
        The host freezes ALL measured cases, original candidate means, directions, tolerances and repetition counts. This is a scoped
        regression bank, not proof of general intelligence. Initial limitations describe untested domains and representative coverage gaps.
        experiment_plan.retention_suite:exact suiteRef requires its entire bank as regression cases with unchanged dataset/metric/direction,
        no fewer repetitions or larger tolerance, and unchanged environment/budget_unit. Add distinct new target cases for growth.
        The host compares both relative gain and the ORIGINAL anchor, rejecting cumulative regression despite a weak recent baseline.
        After independent retention, extend the bank with previous_suite; old anchors persist and all new measured cases are added.
        capability_channel:{operation:initialize|promote,reason,implementation:exact procedure_skill|workflow_method|tool_release,
          lesson:exact retained lesson,suite:exact new suite}. Only its author can revise it using object_id/base_revision (atomic CAS).
        Procedure implementation must come from the same lesson. Workflow/tool innovations must link the exact implementation through
        innovation.workflow_method or innovation.tool_release. Tool releases still require independent source/test/runtime review.
        Promotion requires an experiment against the active innovation and its complete suite, independent retention and an extended suite.
        Rollback uses {operation:rollback,reason,target_revision:exact historical revision of this SAME channel}. It preserves every revision
        and the newest protection bank; older implementation may need revalidation for newly learned capabilities. It does not undo or rerun
        effects, stop running tasks, install code/Skills globally, grant permissions or change private/cross-group access.
        Add capability_channel:exact channelRef to procedure_use or every workflow_step with its matching procedure/method. New work requires
        the active revision. Admitted work keeps its exact selection through pause/recovery; do not relabel or rerun it after a promotion.
        For native runtime tools use collaboration_tool:{mode:run,capability_channel:exact channelRef,parameters:{...}} instead of tool_release.
        Existing runtime permissions, input schema, tested runtime and process limits still apply. Direct experimental work remains available;
        it must not be described as a selected/retained implementation unless these checks pass. Scope changes need separate validation.
    """.trimIndent()
}
