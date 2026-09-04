import Foundation

enum AgentClarificationMode: String, Codable, CaseIterable, Identifiable {
  case execute = "EXECUTE"
  case askLocally = "ASK_LOCALLY"
  case askWithModel = "ASK_WITH_MODEL"

  var id: String { rawValue }
}

enum AgentClarificationQuestion: String, Codable, CaseIterable, Identifiable {
  case none = "NONE"
  case taskGoal = "TASK_GOAL"
  case codeOutcome = "CODE_OUTCOME"
  case controlAction = "CONTROL_ACTION"
  case researchTopic = "RESEARCH_TOPIC"
  case fileAction = "FILE_ACTION"
  case memoryContent = "MEMORY_CONTENT"
  case automationDetails = "AUTOMATION_DETAILS"

  var id: String { rawValue }
}

struct AgentClarificationDecision: Codable, Equatable {
  var mode: AgentClarificationMode
  var question: AgentClarificationQuestion

  init(
    mode: AgentClarificationMode,
    question: AgentClarificationQuestion = .none
  ) {
    self.mode = mode
    self.question = question
  }

  var shouldAsk: Bool {
    mode != .execute
  }
}

enum AgentClarificationPolicy {
  static func decide(
    goal: String,
    hasAttachments: Bool = false,
    hasConversationContext: Bool = false,
    preferenceMode: AgentPreferenceMode = .cautious
  ) -> AgentClarificationDecision {
    AgentPreferenceModePolicy.resolveClarification(
      mode: preferenceMode,
      goal: goal,
      baseline: decideBaseline(
        goal: goal,
        hasAttachments: hasAttachments,
        hasConversationContext: hasConversationContext
      )
    )
  }

  private static func decideBaseline(
    goal: String,
    hasAttachments: Bool,
    hasConversationContext: Bool
  ) -> AgentClarificationDecision {
    let normalized = normalize(goal)
    if normalized.isEmpty {
      if hasAttachments {
        return AgentClarificationDecision(mode: .askWithModel, question: .fileAction)
      }
      return ask(.taskGoal)
    }
    if hasConversationContext && isContextualFollowUp(normalized) {
      return execute
    }
    if hasAttachments && vagueRequests.contains(normalized) {
      return AgentClarificationDecision(mode: .askWithModel, question: .fileAction)
    }
    if vagueRequests.contains(normalized) {
      return hasConversationContext ? execute : ask(.taskGoal)
    }
    if isQuestion(normalized) || greetings.contains(normalized) {
      return execute
    }

    let missingQuestion: AgentClarificationQuestion?
    if codeRequestsWithoutOutcome.contains(normalized) {
      missingQuestion = .codeOutcome
    } else if controlRequestsWithoutAction.contains(normalized) {
      missingQuestion = .controlAction
    } else if researchRequestsWithoutTopic.contains(normalized) {
      missingQuestion = .researchTopic
    } else if fileRequestsWithoutAction.contains(normalized) {
      missingQuestion = .fileAction
    } else if memoryRequestsWithoutContent.contains(normalized) {
      missingQuestion = .memoryContent
    } else if automationRequestsWithoutDetails.contains(normalized) {
      missingQuestion = .automationDetails
    } else {
      missingQuestion = nil
    }
    if let missingQuestion = missingQuestion, !hasConversationContext {
      return ask(missingQuestion)
    }
    return execute
  }

  private static func ask(_ question: AgentClarificationQuestion) -> AgentClarificationDecision {
    AgentClarificationDecision(mode: .askLocally, question: question)
  }

  private static func normalize(_ value: String) -> String {
    let punctuationScalars: Set<UnicodeScalar> = [
      "\u{3002}", "\u{ff0c}", "\u{ff01}", "\u{ff1f}", "\u{ff1a}",
      "\u{ff1b}", "\u{201c}", "\u{201d}", "\u{2018}", "\u{2019}"
    ]
    let mapped = value.lowercased().unicodeScalars.map { scalar -> String in
      if CharacterSet.punctuationCharacters.contains(scalar) || punctuationScalars.contains(scalar) {
        return " "
      }
      return String(scalar)
    }.joined()
    return mapped
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isQuestion(_ value: String) -> Bool {
    questionPrefixes.contains(where: value.hasPrefix) ||
      questionSuffixes.contains(where: value.hasSuffix)
  }

  private static func isContextualFollowUp(_ value: String) -> Bool {
    contextualFollowUps.contains(value) ||
      contextualReferences.contains(where: value.contains)
  }

  private static let execute = AgentClarificationDecision(mode: .execute)
  private static let greetings: Set<String> = [
    "hello", "hi", "hey", "good morning", "good afternoon", "good evening",
    "\u{4f60}\u{597d}", "\u{55e8}", "\u{65e9}\u{4e0a}\u{597d}",
    "\u{4e0b}\u{5348}\u{597d}", "\u{665a}\u{4e0a}\u{597d}"
  ]
  private static let questionPrefixes: Set<String> = [
    "what ", "why ", "how ", "when ", "where ", "which ", "who ",
    "can ", "could ", "would ", "is ", "are ", "do ", "does ",
    "\u{4ec0}\u{4e48}", "\u{4e3a}\u{4ec0}\u{4e48}", "\u{600e}\u{4e48}",
    "\u{5982}\u{4f55}", "\u{54ea}\u{4e2a}", "\u{54ea}\u{4e9b}",
    "\u{8c01}", "\u{80fd}\u{4e0d}\u{80fd}", "\u{53ef}\u{4ee5}"
  ]
  private static let questionSuffixes: Set<String> = [
    "\u{5417}", "\u{5462}", "\u{4e48}", "\u{600e}\u{4e48}\u{6837}",
    "\u{5982}\u{4f55}"
  ]
  private static let contextualFollowUps: Set<String> = [
    "continue", "go ahead", "do it", "try again", "retry", "keep going",
    "use this", "use that", "same as before", "make it better",
    "\u{7ee7}\u{7eed}", "\u{6267}\u{884c}", "\u{5c31}\u{8fd9}\u{6837}",
    "\u{6309}\u{8fd9}\u{4e2a}", "\u{518d}\u{8bd5}\u{8bd5}",
    "\u{91cd}\u{8bd5}", "\u{4fdd}\u{8bc1}\u{6b63}\u{786e}",
    "\u{7528}\u{8fd9}\u{4e2a}", "\u{548c}\u{4e4b}\u{524d}\u{4e00}\u{6837}",
    "\u{6309}\u{4e0a}\u{9762}\u{7684}\u{505a}"
  ]
  private static let contextualReferences: Set<String> = [
    " this", " that", " it", " above", " previous",
    "\u{8fd9}\u{4e2a}", "\u{90a3}\u{4e2a}", "\u{5b83}",
    "\u{4e0a}\u{9762}", "\u{4e4b}\u{524d}", "\u{521a}\u{624d}",
    "\u{524d}\u{9762}", "\u{8be5}\u{6587}\u{4ef6}", "\u{8fd9}\u{5f20}\u{56fe}"
  ]
  private static let vagueRequests: Set<String> = [
    "help me", "handle this", "do something", "take a look", "fix it",
    "improve it", "optimize it", "work on this", "please help",
    "\u{5e2e}\u{6211}", "\u{5e2e}\u{6211}\u{5f04}\u{4e00}\u{4e0b}",
    "\u{5904}\u{7406}\u{4e00}\u{4e0b}", "\u{5f04}\u{4e00}\u{4e0b}",
    "\u{770b}\u{770b}", "\u{5e2e}\u{6211}\u{770b}\u{770b}",
    "\u{4fee}\u{4e00}\u{4e0b}", "\u{4f18}\u{5316}\u{4e00}\u{4e0b}",
    "\u{6539}\u{8fdb}\u{4e00}\u{4e0b}", "\u{4f60}\u{770b}\u{7740}\u{529e}",
    "\u{7ed9}\u{6211}\u{7ed3}\u{679c}", "\u{5feb}\u{70b9}",
    "\u{4e0d}\u{884c}"
  ]
  private static let codeRequestsWithoutOutcome: Set<String> = [
    "write code", "write a program", "build an app", "create an app", "fix the code",
    "\u{5199}\u{4ee3}\u{7801}", "\u{5199}\u{4e2a}\u{7a0b}\u{5e8f}",
    "\u{5f00}\u{53d1}\u{4e00}\u{4e2a} app", "\u{505a}\u{4e00}\u{4e2a} app",
    "\u{4fee}\u{4ee3}\u{7801}"
  ]
  private static let controlRequestsWithoutAction: Set<String> = [
    "control my phone", "control the phone", "control my computer",
    "control the computer", "remote desktop",
    "\u{63a7}\u{5236}\u{624b}\u{673a}", "\u{64cd}\u{4f5c}\u{624b}\u{673a}",
    "\u{63a7}\u{5236}\u{7535}\u{8111}", "\u{64cd}\u{4f5c}\u{7535}\u{8111}",
    "\u{8fdc}\u{7a0b}\u{684c}\u{9762}"
  ]
  private static let researchRequestsWithoutTopic: Set<String> = [
    "research", "research this", "search", "search the web", "look it up",
    "\u{7814}\u{7a76}\u{4e00}\u{4e0b}", "\u{641c}\u{7d22}",
    "\u{641c}\u{4e00}\u{4e0b}", "\u{67e5}\u{4e00}\u{4e0b}",
    "\u{67e5}\u{8d44}\u{6599}"
  ]
  private static let fileRequestsWithoutAction: Set<String> = [
    "process the file", "handle the file", "work on the document",
    "\u{5904}\u{7406}\u{6587}\u{4ef6}", "\u{5904}\u{7406}\u{8fd9}\u{4e2a}\u{6587}\u{4ef6}",
    "\u{770b}\u{4e0b}\u{6587}\u{4ef6}"
  ]
  private static let memoryRequestsWithoutContent: Set<String> = [
    "remember this", "remember that", "save this to memory",
    "\u{8bb0}\u{4f4f}\u{8fd9}\u{4e2a}", "\u{8bb0}\u{4f4f}\u{8fd9}\u{4ef6}\u{4e8b}",
    "\u{5b58}\u{5230}\u{8bb0}\u{5fc6}"
  ]
  private static let automationRequestsWithoutDetails: Set<String> = [
    "create an automation", "make a workflow", "schedule a task", "remind me",
    "\u{521b}\u{5efa}\u{81ea}\u{52a8}\u{5316}", "\u{5efa}\u{4e00}\u{4e2a}\u{5de5}\u{4f5c}\u{6d41}",
    "\u{8bbe}\u{7f6e}\u{5b9a}\u{65f6}\u{4efb}\u{52a1}", "\u{63d0}\u{9192}\u{6211}"
  ]
}
