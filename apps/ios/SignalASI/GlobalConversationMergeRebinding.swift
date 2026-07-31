import Foundation

extension GlobalConversationMergeLifecycle {
  static func rebindWorld(
    _ world: PersonalWorldModel,
    event: GlobalConversationEvent
  ) -> PersonalWorldModel {
    guard valid(event) else { return world }
    let source = sourceConversationId(event)
    let target = targetConversationId(event)
    let reboundItems = world.items.map { item -> GlobalWorldItem in
      var copy = item
      copy.conversationIds = replaceConversationIds(item.conversationIds, source: source, target: target)
      copy.evidenceProvenance = item.evidenceProvenance.map {
        $0.rebindingConversation(source: source, target: target)
      }
      return copy
    }
    let reboundLinks = world.links.compactMap { link -> GlobalConversationLink? in
      let left = link.leftConversationId == source ? target : link.leftConversationId
      let right = link.rightConversationId == source ? target : link.rightConversationId
      guard left != right else { return nil }
      var copy = link
      copy.leftConversationId = left
      copy.rightConversationId = right
      copy.evidenceProvenance = link.evidenceProvenance.map {
        $0.rebindingConversation(source: source, target: target)
      }
      return copy
    }
    return PersonalWorldModel(
      items: reboundItems,
      links: mergeConversationLinks(reboundLinks),
      processedEventIds: Array(distinctPreservingFirst(world.processedEventIds + [event.id]).suffix(4_000)),
      retractedEventIds: world.retractedEventIds,
      updatedAtMillis: max(world.updatedAtMillis, event.timestampMillis)
    )
  }

  static func rebindTopicGraph(
    _ graph: GlobalTopicProjectGraph,
    event: GlobalConversationEvent
  ) -> GlobalTopicProjectGraph {
    guard valid(event) else { return graph }
    let source = sourceConversationId(event)
    let target = targetConversationId(event)
    return GlobalTopicProjectGraph(
      nodes: graph.nodes.map { node in
        var copy = node
        copy.conversationIds = replaceConversationIds(node.conversationIds, source: source, target: target)
        copy.evidenceProvenance = node.evidenceProvenance.map {
          $0.rebindingConversation(source: source, target: target)
        }
        return copy
      },
      relations: graph.relations.map { relation in
        var copy = relation
        copy.evidenceProvenance = relation.evidenceProvenance.map {
          $0.rebindingConversation(source: source, target: target)
        }
        return copy
      },
      processedEventIds: graph.processedEventIds,
      retractedEventIds: graph.retractedEventIds,
      updatedAtMillis: max(graph.updatedAtMillis, event.timestampMillis)
    )
  }

  static func rebindResearchTasks(
    _ tasks: [GlobalResearchTask],
    event: GlobalConversationEvent
  ) -> [GlobalResearchTask] {
    rebind(event: event, values: tasks) { task, source, target in
      guard task.sourceConversationId == source else { return task }
      var copy = task
      copy.sourceConversationId = target
      copy.updatedAtMillis = max(task.updatedAtMillis, event.timestampMillis)
      return copy
    }
  }

  static func rebindCognitionTasks(
    _ tasks: [GlobalCognitionTask],
    event: GlobalConversationEvent
  ) -> [GlobalCognitionTask] {
    rebind(event: event, values: tasks) { task, source, target in
      let reboundEvent = rebindEvent(task.sourceEvent, sourceConversationId: source, targetConversationId: target)
      guard reboundEvent != task.sourceEvent else { return task }
      var copy = task
      copy.sourceEvent = reboundEvent
      copy.updatedAtMillis = max(task.updatedAtMillis, event.timestampMillis)
      return copy
    }
  }

  static func rebindAutonomousRuns(
    _ runs: [GlobalAutonomousRun],
    event: GlobalConversationEvent
  ) -> [GlobalAutonomousRun] {
    rebind(event: event, values: runs) { run, source, target in
      guard run.sourceConversationId == source else { return run }
      var copy = run
      copy.sourceConversationId = target
      copy.updatedAtMillis = max(run.updatedAtMillis, event.timestampMillis)
      return copy
    }
  }

  static func rebindProactiveMessages(
    _ messages: [GlobalProactiveMessage],
    event: GlobalConversationEvent
  ) -> [GlobalProactiveMessage] {
    rebind(event: event, values: messages) { message, source, target in
      var copy = message
      copy.sourceConversationId = copy.sourceConversationId.replacingConversationId(source: source, target: target)
      copy.deliveryConversationId = copy.deliveryConversationId.replacingConversationId(source: source, target: target)
      copy.deliveredConversationId = copy.deliveredConversationId.replacingConversationId(source: source, target: target)
      return copy
    }
  }

  static func rebindLongHorizonGoals(
    _ goals: [GlobalLongHorizonGoal],
    event: GlobalConversationEvent
  ) -> [GlobalLongHorizonGoal] {
    rebind(event: event, values: goals) { goal, source, target in
      let conversations = replaceConversationIds(goal.sourceConversationIds, source: source, target: target)
      guard conversations != goal.sourceConversationIds else { return goal }
      var copy = goal
      copy.sourceConversationIds = conversations
      copy.updatedAtMillis = max(goal.updatedAtMillis, event.timestampMillis)
      return copy
    }
  }

  private static func rebind<T>(
    event: GlobalConversationEvent,
    values: [T],
    transform: (T, String, String) -> T
  ) -> [T] {
    guard valid(event) else { return values }
    return values.map {
      transform($0, sourceConversationId(event), targetConversationId(event))
    }
  }

  private static func replaceConversationIds(
    _ values: Set<String>,
    source: String,
    target: String
  ) -> Set<String> {
    Set(values.map { $0 == source ? target : $0 })
  }

  private static func mergeConversationLinks(
    _ links: [GlobalConversationLink]
  ) -> [GlobalConversationLink] {
    var groups: [String: [GlobalConversationLink]] = [:]
    for link in links {
      groups[conversationLinkMergeKey(link), default: []].append(link)
    }
    return groups.keys.sorted().compactMap { key in
      guard let matches = groups[key], let primary = newestLink(matches) else { return nil }
      let evidence = distinctEvidence(matches.flatMap(\.evidenceProvenance))
      var copy = primary
      copy.strength = matches.map(\.strength).max() ?? primary.strength
      copy.evidenceCount = max(evidence.count, matches.map(\.evidenceCount).max() ?? primary.evidenceCount)
      copy.evidenceProvenance = evidence
      copy.lastSeenAtMillis = matches.map(\.lastSeenAtMillis).max() ?? primary.lastSeenAtMillis
      return copy
    }
  }

  private static func conversationLinkMergeKey(_ link: GlobalConversationLink) -> String {
    let pair = [link.leftConversationId, link.rightConversationId].sorted().joined(separator: "|")
    return "\(pair)|\(GlobalAgentText.normalize(link.topic))"
  }

  private static func newestLink(_ links: [GlobalConversationLink]) -> GlobalConversationLink? {
    links.sorted {
      if $0.lastSeenAtMillis != $1.lastSeenAtMillis {
        return $0.lastSeenAtMillis > $1.lastSeenAtMillis
      }
      return $0.id < $1.id
    }.first
  }

  private static func distinctEvidence(_ values: [GlobalEvidenceRef]) -> [GlobalEvidenceRef] {
    var seen = Set<String>()
    let distinct = values.filter { evidence in
      seen.insert(evidence.eventId).inserted
    }
    return Array(distinct.suffix(24))
  }

  private static func distinctPreservingFirst(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter {
      seen.insert($0).inserted
    }
  }
}

private extension GlobalEvidenceRef {
  func rebindingConversation(source: String, target: String) -> GlobalEvidenceRef {
    guard conversationId == source else { return self }
    var copy = self
    copy.conversationId = target
    return copy
  }
}

private extension String {
  func replacingConversationId(source: String, target: String) -> String {
    self == source ? target : self
  }
}
