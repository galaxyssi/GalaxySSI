# Android Health assistant follow-up

After calculating a local analysis, users can ask a text question about that
same snapshot. Each follow-up requires model selection and confirmation of
the exact outgoing payload. It includes the current question, already scoped
aggregates, and at most the previous answer's structured selections. It does
not attach raw records, notes, profile fields, record identifiers, originals,
or earlier questions. Text a user chooses to type is shown in the disclosure.

The model selects supported answer topics, fact IDs, and optional next actions.
The device validates the response and formats its own calculated numbers,
coverage and revision links. Partial and out-of-scope replies are explicit.
This is not an unrestricted health-chat or diagnosis route. There is no
automatic provider switch or consent reuse. Record, profile or permission
changes invalidate the relevant snapshot; leaving the assistant clears
questions and replies from its UI.

`HealthAnalysisFollowUpTest` checks the minimal payload, all three provider
envelopes and rejection of invented selections or free text.
`HealthAssistantFollowUpDeviceTest` uses a debug-only injected gateway with
isolated encrypted records on Tab Active3. It verifies exact consent against
the sent payload, cancel, continuation without resending earlier questions,
partial/out-of-scope and no-model states, stale permission/record rejection,
audit contents, and opening the exact source revision. Use
`-e healthFollowUpScreenshot true` to capture the populated synthetic UI.
The test sends no real network requests or personal health information.
