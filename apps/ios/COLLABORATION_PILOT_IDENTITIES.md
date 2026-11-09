# Collaboration pilot identities

`AgentCollaborationPilotIdentityTests` models the iOS counterpart of Android
#3495. Omitted or explicit `production` keeps the fixture graph unchanged.
`run_scoped` derives a stable node ID from the pilot, group, supervisor run and
original node. It rewrites dependency references and the primary node, without
replacing assignments, people, selected model IDs, conversation or goal.

The suite runs synthetic work through the existing team runtime. It reopens
the encrypted execution store between runs and checks that the second run
receives only its own dependency outputs. A single investigator remains one
assignment. This is a local XCTest fixture, not a production configuration or
proof of a fresh provider thread, retained learning, or better model output.
