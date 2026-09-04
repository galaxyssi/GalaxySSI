import XCTest
@testable import GalaxySSI

final class GlobalLongHorizonGoalGraphTests: XCTestCase {
  func testGoalDependencyWaitsThenResumesWhenPrerequisiteCompletes() {
    let prerequisite = goal("runtime", title: "Build runtime")
    let dependent = goal("ship", title: "Ship mobile Agent")

    let linked = GlobalLongHorizonGoalGraphPolicy.applyDependencies(
      goals: [prerequisite, dependent],
      proposals: [GlobalGoalDependencyProposal(goal: "Ship mobile Agent", dependsOn: "Build runtime")],
      nowMillis: 1_000
    )
    let waiting = linked.first { $0.id == dependent.id }

    XCTAssertEqual(waiting?.dependencyGoalIds, Set([prerequisite.id]))
    XCTAssertEqual(waiting?.status, .waitingDependency)
    XCTAssertEqual(waiting?.blocker, "Waiting for 1 prerequisite goal(s)")
    XCTAssertEqual(waiting?.nextCheckAtMillis, 0)
    XCTAssertEqual(waiting?.completionCriteria, [
      "Verified evidence that Ship mobile Agent is complete"
    ])

    let released = GlobalLongHorizonGoalGraphPolicy.reconcile(
      goals: linked.map {
        var copy = $0
        if copy.id == prerequisite.id {
          copy.status = .completed
        }
        return copy
      },
      nowMillis: 2_000
    )
    let active = released.first { $0.id == dependent.id }

    XCTAssertEqual(active?.status, .active)
    XCTAssertEqual(active?.blocker, "")
    XCTAssertEqual(active?.nextCheckAtMillis, 2_000)
  }

  func testCyclicGoalDependencyProposalIsIgnored() {
    let first = goal("first", title: "First")
    let second = goal("second", title: "Second", dependencyGoalIds: [first.id])

    let updated = GlobalLongHorizonGoalGraphPolicy.applyDependencies(
      goals: [first, second],
      proposals: [GlobalGoalDependencyProposal(goal: "First", dependsOn: "Second")],
      nowMillis: 1_000
    )

    XCTAssertEqual(updated.first { $0.id == first.id }?.dependencyGoalIds, Set<String>())
    XCTAssertEqual(updated.first { $0.id == second.id }?.dependencyGoalIds, Set([first.id]))
  }

  func testAppliesOnlyBoundedUniqueDependencies() {
    let prerequisites = (0..<10).map {
      goal("prereq-\($0)", title: "Prerequisite \($0)")
    }
    let target = goal("target", title: "Ship")
    let proposals = prerequisites.map {
      GlobalGoalDependencyProposal(goal: "Ship", dependsOn: $0.title)
    } + [
      GlobalGoalDependencyProposal(goal: "Ship", dependsOn: prerequisites[0].title)
    ]

    let updated = GlobalLongHorizonGoalGraphPolicy.applyDependencies(
      goals: prerequisites + [target],
      proposals: proposals,
      nowMillis: 3_000
    )
    let linkedTarget = updated.first { $0.id == target.id }

    XCTAssertEqual(linkedTarget?.dependencyGoalIds.count, 8)
    XCTAssertEqual(linkedTarget?.status, .waitingDependency)
    XCTAssertEqual(linkedTarget?.updatedAtMillis, 3_000)
  }

  func testAssignProjectsUsesTopicAndConversationOverlap() {
    let runtimeProject = project(
      id: "project-runtime",
      name: "GalaxySSI runtime",
      conversations: ["conversation-a"],
      lastSeenAtMillis: 5_000
    )
    let archiveProject = project(
      id: "project-archive",
      name: "Archived runtime",
      status: .archived,
      conversations: ["conversation-a"],
      lastSeenAtMillis: 9_000
    )
    let unrelatedProject = project(
      id: "project-trip",
      name: "Trip planning",
      conversations: ["conversation-z"],
      lastSeenAtMillis: 10_000
    )
    let target = goal(
      "goal-runtime",
      title: "Keep runtime release moving",
      topic: "GalaxySSI runtime",
      conversations: ["conversation-a"]
    )

    let assigned = GlobalLongHorizonGoalGraphPolicy.assignProjects(
      goals: [target],
      graph: GlobalTopicProjectGraph(nodes: [archiveProject, unrelatedProject, runtimeProject]),
      nowMillis: 4_000
    )

    XCTAssertEqual(assigned.first?.projectNodeId, "project-runtime")
    XCTAssertEqual(assigned.first?.updatedAtMillis, 4_000)
  }

  func testReadyRequiresEveryDependencyCompletedAndPresent() {
    let completed = goal("completed", title: "Completed", status: .completed)
    let blocked = goal("blocked", title: "Blocked", status: .blocked)
    let readyGoal = goal("ready", title: "Ready", dependencyGoalIds: [completed.id])
    let notReadyGoal = goal("not-ready", title: "Not ready", dependencyGoalIds: [completed.id, blocked.id])
    let missingGoal = goal("missing", title: "Missing", dependencyGoalIds: ["missing-id"])

    XCTAssertTrue(GlobalLongHorizonGoalGraphPolicy.ready(goal: readyGoal, goals: [completed]))
    XCTAssertFalse(GlobalLongHorizonGoalGraphPolicy.ready(goal: notReadyGoal, goals: [completed, blocked]))
    XCTAssertFalse(GlobalLongHorizonGoalGraphPolicy.ready(goal: missingGoal, goals: [completed]))
  }

  func testDependencyProposalUsesAndroidWireNames() throws {
    let data = #"{"goal":"Ship","depends_on":"Verify"}"#.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(GlobalGoalDependencyProposal.self, from: data)
    let encoded = try JSONEncoder().encode(decoded)
    let object = try JSONSerialization.jsonObject(with: encoded) as? [String: String]

    XCTAssertEqual(decoded.goal, "Ship")
    XCTAssertEqual(decoded.dependsOn, "Verify")
    XCTAssertEqual(object?["depends_on"], "Verify")
  }

  private func goal(
    _ id: String,
    title: String,
    topic: String = "GalaxySSI",
    status: GlobalLongHorizonGoalStatus = .active,
    conversations: Set<String> = ["conversation-a"],
    dependencyGoalIds: Set<String> = [],
    projectNodeId: String = "",
    completionCriteria: [String] = []
  ) -> GlobalLongHorizonGoal {
    GlobalLongHorizonGoal(
      id: id,
      stableKey: "stable-\(id)",
      topic: topic,
      title: title,
      status: status,
      sourceConversationIds: conversations,
      projectNodeId: projectNodeId,
      dependencyGoalIds: dependencyGoalIds,
      completionCriteria: completionCriteria
    )
  }

  private func project(
    id: String,
    name: String,
    status: GlobalTopicNodeStatus = .active,
    conversations: Set<String>,
    lastSeenAtMillis: Int64
  ) -> GlobalTopicNode {
    GlobalTopicNode(
      id: id,
      stableKey: "stable-\(id)",
      name: name,
      kind: .project,
      status: status,
      conversationIds: conversations,
      lastSeenAtMillis: lastSeenAtMillis
    )
  }
}
