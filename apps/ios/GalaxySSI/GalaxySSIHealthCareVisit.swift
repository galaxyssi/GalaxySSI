import Foundation

enum GalaxySSIHealthCareVisit {
  enum Section: String, CaseIterable, Identifiable {
    case measurements, context, actions, questions, profile
    var id: String { rawValue }

    func title(_ language: String) -> String {
      let fallback: String
      switch self {
      case .measurements: fallback = "Measurements"
      case .context: fallback = "Measurement context"
      case .actions: fallback = "Confirmed actions"
      case .questions: fallback = "Questions for review"
      case .profile: fallback = "Selected profile details"
      }
      return GalaxySSIHealthCareVisit.text(rawValue, fallback, language)
    }
  }

  struct Item: Equatable, Identifiable {
    let id: String
    let section: Section
    let title: String
    let text: String
    var record: GalaxySSIHealthCare.Record?
  }

  struct Stamp: Equatable {
    let revision: Int
    let permission: UUID
    let records: [GalaxySSIHealthCare.Record]
    let questionVersion: String?
    let profile: GalaxySSIHealthCareProfileScope.Link?
  }

  struct Preview {
    let created: Date
    let sections: Set<Section>
    let stamp: Stamp
    let heading: String
    let introduction: String
    let limitations: String
    let items: [Item]

    func isFresh(at now: Date) -> Bool {
      now >= created && now.timeIntervalSince(created) < 600
    }

    func text(for selection: Set<String>) throws -> String {
      let keys = Set(items.map(\.id))
      guard !selection.isEmpty, selection.isSubset(of: keys), keys.count == items.count, keys.count <= 100 else {
        throw GalaxySSIHealthRecords.Failure.invalid
      }
      let result = ([heading, introduction] + items.filter { selection.contains($0.id) }
        .map { $0.title + "\n" + $0.text } + [limitations]).joined(separator: "\n\n")
      guard result.utf16.count <= 100_000 else { throw GalaxySSIHealthRecords.Failure.invalid }
      return result
    }

    func revalidate(_ current: Preview, at now: Date) throws {
      guard isFresh(at: now), sections == current.sections, stamp == current.stamp,
            items == current.items, limitations == current.limitations else { throw GalaxySSIHealthRecords.Failure.stale }
    }
  }

  static func text(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.visit." + key, fallback: fallback, language: language)
  }

  @MainActor
  struct Presentation {
    let language: String
    func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthCareVisit.text(key, fallback, language) }
    func date(_ value: Date) -> String {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: language)
      formatter.dateStyle = .medium
      formatter.timeStyle = .short
      return formatter.string(from: value)
    }

    var unknown: String { t("unknown", "Unknown or not recorded") }
    func line(_ label: String, _ value: String) -> String { label + ": " + value.ifBlank(unknown) }

    func measurement(_ reading: GalaxySSIHealthReading, concern: GalaxySSIHealthCare.Concern,
                     latest: GalaxySSIHealthReading?) -> Item {
      let sample = GalaxySSIHealthCareComparison.Sample(reading)
      let source: String
      if reading.reportSource != nil { source = t("report", "Imported report") }
      else if reading.tableSource != nil { source = t("table", "Imported table") }
      else if reading.healthKitSource != nil { source = "Apple Health" }
      else if reading.bluetoothReceipt != nil { source = t("bluetooth", "Bluetooth device") }
      else { source = t("manual", "Manual entry") }
      let revision = String(format: t("revision", "Revision %lld"), Int64(reading.revision))
      var lines = [sample.result + (sample.unit.isEmpty ? "" : " " + sample.unit)]
      if let pulse = sample.pulse {
        lines.append(line(t("pulse", "Pulse"), GalaxySSIHealthCareComparison.Sample.number(pulse) + " bpm"))
      }
      lines += [line(t("reference", "Report reference interval"), sample.reference),
                line(t("collection", "Collection condition"), sample.condition),
                line(t("source", "Source"), source + " · " + revision)]
      if let latest, sample.record != .init(latest) {
        let previousContext = [concern.context, concern.comparison?.previousContext].compactMap { $0 }
          .first { $0.record == sample.record }
        let pair = GalaxySSIHealthCareComparison.Pair(before: sample, after: .init(latest), kind: .historyChanged,
          previousContext: previousContext, nearestAtCapture: nil)
        lines += pair.gaps(currentContext: concern.context).map {
          GalaxySSIHealthCareComparisonSection.gapLabel($0, language: language)
        }
      }
      return .init(id: "record:" + reading.id.uuidString, section: .measurements,
        title: reading.metric.title(language: language) + " · " + date(reading.measuredAt),
        text: lines.joined(separator: "\n"), record: sample.record)
    }

    func context(_ concern: GalaxySSIHealthCare.Concern) -> Item {
      let current = concern.context.flatMap { $0.record == concern.assessment.record ? $0.answers : nil }
      func truth(_ value: Bool?) -> String {
        guard let value else { return unknown }
        return value ? t("yes", "Yes") : t("no", "No")
      }
      var lines: [String] = []
      if concern.metric == .glucose {
        let specimen: String
        switch current?.specimen {
        case .labPlasma?: specimen = t("plasma", "Laboratory plasma")
        case .homeCapillary?: specimen = t("capillary", "Home capillary")
        case .interstitial?: specimen = t("interstitial", "Interstitial")
        case nil: specimen = unknown
        }
        lines = [line(t("adult", "Adult"), truth(current?.adult)),
          line(t("pregnant", "Pregnant at measurement"), truth(current?.pregnant)),
          line(t("diabetes", "Diagnosed diabetes"), truth(current?.diagnosedDiabetes)),
          line(t("specimen", "Sample type"), specimen),
          line(t("fasting", "Hours without calories"), current?.fastingHours.map(String.init) ?? unknown),
          line(t("illness", "Illness or glucose-affecting medication"), truth(current?.illnessOrMedication))]
      } else { lines = [t("no_context", "No structured clarification for this measurement.")] }
      lines.append(t("self_reported", "Self-reported; not independently verified."))
      return .init(id: "context", section: .context, title: Section.context.title(language),
        text: lines.joined(separator: "\n"))
    }

    func action(_ entry: GalaxySSIHealthCarePlan.AdoptedAction, concern: GalaxySSIHealthCare.Concern,
                stale: Bool) -> Item {
      var lines = [entry.outcome == nil ? t("confirmed", "Confirmed") : t("recorded", "Outcome recorded"),
                   t("action_notice", "A user-reviewed action, not a clinician instruction."),
                   line(t("source", "Source"), entry.source.title)]
      if stale { lines.append(t("stale_action", "The basis for this action has changed.")) }
      if let start = entry.action.dueFrom, let end = entry.action.dueUntil {
        lines.append(line(t("review_window", "Review window"), date(start) + " – " + date(end)))
      }
      if let feedback = entry.feedback, feedback.isInScope(concern) {
        let labels: [GalaxySSIHealthCareFollowUp.Feedback.Kind: String] = [
          .completed: t("feedback_completed", "Completed"), .partial: t("feedback_partial", "Partial"),
          .barrier: t("feedback_barrier", "Barrier")]
        lines += [line(labels[feedback.kind] ?? "", date(feedback.recordedAt)), feedback.note]
      } else if entry.feedback == nil, let outcome = entry.outcome {
        lines += [date(outcome.reportedAt), outcome.note]
      }
      return .init(id: "action:" + entry.id, section: .actions, title: entry.action.description,
        text: lines.filter { !$0.isBlank }.joined(separator: "\n"))
    }

    func question(_ row: GalaxySSIHealthCareQuestions.Row, page: GalaxySSIHealthCareQuestions.Page) -> Item {
      let state = page.state(row)
      let status: String
      switch state {
      case .open: status = t("question_open", "Open")
      case .answered: status = t("question_answered", "Answered")
      case .deferred: status = t("question_deferred", "Deferred")
      case .declined: status = t("question_declined", "Declined")
      case .conflict: status = t("question_conflict", "Conflicting information")
      case .stale: status = t("question_stale", "Based on older information")
      }
      var lines = [row.proposal.purpose, status]
      if page.known[row.proposal.key] != nil { lines.append(t("known", "A saved fact exists.")) }
      if state != .stale, let answer = row.answer { lines.append(answer) }
      lines.append(date(row.updatedAt))
      return .init(id: "question:" + row.id.uuidString, section: .questions, title: row.proposal.question,
        text: lines.joined(separator: "\n"))
    }

    func profile(_ profile: GalaxySSIHealthProfile?, link: GalaxySSIHealthCareProfileScope.Link?,
                 at measuredAt: Date) throws -> [Item] {
      let title = Section.profile.title(language)
      guard let profile, let link else {
        return [.init(id: "profile:none", section: .profile, title: title,
          text: t("profile_none", "No profile details are selected for this concern."))]
      }
      let payload = try link.snapshot(profile, measuredAt: measuredAt)
      let fields = payload["fields"]?.objectValue ?? [:]
      let notice = t("self_reported", "Self-reported; not independently verified.")
      var items = link.selection.fields.sorted { $0.rawValue < $1.rawValue }.map { field -> Item in
        let value = fields[field == .birthDate ? "age_at_measurement" : field.rawValue]?.objectValue?["value"]
        let display: String
        switch field {
        case .birthDate:
          if case .int(let years)? = value { display = String(years) } else { display = unknown }
        case .height:
          if let height = value?.objectValue?["value"]?.strictStringValue,
             let unit = value?.objectValue?["unit"]?.strictStringValue { display = height + " " + unit }
          else { display = unknown }
        case .referenceSex:
          switch value?.strictStringValue {
          case "female": display = t("female", "Female")
          case "male": display = t("male", "Male")
          case "other": display = t("other", "Other")
          default: display = unknown
          }
        case .context: display = value?.strictStringValue ?? unknown
        }
        return .init(id: "field:" + field.rawValue, section: .profile,
          title: field == .birthDate ? t("age", "Age at measurement") : field.title(language: language),
          text: display + "\n" + notice)
      }
      let entries = profile.background.filter { link.selection.entries.contains($0.id) }
        .sorted { $0.id.uuidString < $1.id.uuidString }
      items += entries.map { entry in
        .init(id: "profile:" + entry.id.uuidString, section: .profile,
          title: GalaxySSIHealthBackgroundPicker.title(entry.kind, language: language) + ": " + entry.title,
          text: [entry.notes, notice].filter { !$0.isBlank }.joined(separator: "\n"))
      }
      if entries.count != link.selection.entries.count {
        items.append(.init(id: "profile:missing", section: .profile, title: title,
          text: t("profile_missing", "Some selected profile entries are unavailable.")))
      }
      return items
    }
  }
}
