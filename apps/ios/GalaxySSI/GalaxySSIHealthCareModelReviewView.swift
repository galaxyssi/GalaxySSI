import SwiftUI

struct GalaxySSIHealthCareModelReviewView: View {
  let review: GalaxySSIHealthCareModelReview.Review
  let historical: Bool
  var onQuestions: (() -> Void)? = nil
  @Environment(\.galaxySSIInterfaceLanguage) private var language

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(t("title", "Model assessment")).font(.headline)
      if historical {
        Text(t("historical", "This assessment refers to earlier data or authorization.")).foregroundColor(.secondary)
      }
      Text(review.input.summary).textSelection(.enabled)
      field(t("reason", "Reasoning summary"), review.input.rationale)
      field(t("uncertainty", "Uncertainty"), review.input.uncertainty)
      field(t("next", "Proposed next step"), review.input.nextStep)
      field(t("decision", "Recommendation"), t("decision." + review.input.decision.rawValue, decision))
      if let onQuestions, let questions = review.input.questions, !questions.isEmpty {
        Button(action: onQuestions) {
          Label(String(format: t("questions", "Review questions (%d)"), questions.count), systemImage: "questionmark.bubble")
        }.buttonStyle(.borderless)
      }
      field(t("events", "Review conditions"), review.input.events.map { t("event." + $0.rawValue, event($0)) }.joined(separator: " / "))
      if review.input.attentionRequested {
        field(t("attention", "Suggested attention, not a sent notification"), review.input.attentionReason)
      }
      Text(t("notice", "A model opinion, not a diagnosis or verified clinical conclusion. No action or reminder was executed."))
        .font(.footnote).foregroundColor(.secondary)
    }
    .padding(.vertical, 6)
  }

  private var decision: String {
    switch review.input.decision {
    case .observe: return "Continue observation"
    case .clarify: return "Clarify missing context"
    case .research: return "Review additional sources"
    case .proposePlan: return "Review the proposed draft"
    case .clinicianReview: return "Seek clinician review"
    }
  }
  private func event(_ value: GalaxySSIHealthCareModelReview.Event) -> String {
    switch value {
    case .sourceChange: return "Source data changes"
    case .userFeedback: return "New user feedback"
    case .confirmedActionDue: return "A confirmed action becomes due"
    }
  }
  private func field(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.subheadline).fontWeight(.semibold)
      Text(value).textSelection(.enabled)
    }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.model_review." + key, fallback: fallback, language: language)
  }
}
