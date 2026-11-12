import SwiftUI
import UIKit

struct GalaxySSIHealthInstructionPagePreview: View {
  let image: CGImage
  let highlights: [CGRect]

  var body: some View {
    GeometryReader { geometry in
      let scale = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
      let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
      ZStack(alignment: .topLeading) {
        Image(uiImage: UIImage(cgImage: image)).resizable().frame(width: width, height: height)
        ForEach(highlights.indices, id: \.self) { index in
          let rect = highlights[index]
          Rectangle().fill(Color.yellow.opacity(0.28))
            .overlay(Rectangle().strokeBorder(Color.orange, lineWidth: 1))
            .frame(width: rect.width * width, height: rect.height * height)
            .offset(x: rect.minX * width, y: rect.minY * height)
            .accessibilityHidden(true)
        }
      }
      .frame(width: width, height: height)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(height: 260)
  }
}

struct GalaxySSIHealthInstructionQuote: View {
  let source: GalaxySSIHealthInstruction.Source
  let language: String

  var body: some View {
    Section(t("quotation", "Original quotation")) {
      Text(source.quote).textSelection(.enabled)
      Text(String(format: t("page", "Page %lld of %lld"), Int64(source.page), Int64(source.pageCount)))
        .font(.footnote).foregroundColor(.secondary)
      Text(source.recognition == .pdfText ? t("pdf_text", "PDF text layer") : t("ocr", "On-device OCR"))
        .font(.footnote).foregroundColor(.secondary)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthInstruction.text(key, fallback, language)
  }
}

struct GalaxySSIHealthInstructionEditor: View {
  typealias Review = GalaxySSIHealthInstruction
  @Binding var draft: Review.Draft
  let source: Review.Source
  let language: String
  let save: (Review.Draft) -> Void

  var body: some View {
    Form {
      GalaxySSIHealthInstructionQuote(source: source, language: language)
      Picker(t("kind", "Instruction type"), selection: Binding(get: { draft.kind }, set: { draft.changeKind($0) })) {
        ForEach(Review.Kind.allCases) { kind in Text(Review.kindTitle(kind, language)).tag(kind) }
      }
      ForEach(draft.kind.fields) { field in
        Section(Review.fieldTitle(field, language)) {
          if field == .details {
            TextEditor(text: text(field)).frame(minHeight: 80)
              .accessibilityLabel(Review.fieldTitle(field, language))
          } else {
            TextField(Review.fieldTitle(field, language), text: text(field))
          }
          Picker(t("review_state", "Review status"), selection: Binding(get: { draft.value(field).review }, set: {
            draft.review(field, as: $0)
          })) {
            ForEach(Review.Review.allCases) { state in
              Text(Review.reviewTitle(state, language)).tag(state)
                .disabled(state == .transcribed && draft.value(field).text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
          }
          .pickerStyle(.menu)
        }
      }
      Section {
        Button(t("save", "Save draft")) { save(draft) }
      } footer: {
        Text(t("notice", "User transcription only. This is not clinician verification or a treatment plan."))
      }
    }
  }

  private func text(_ field: Review.Field) -> Binding<String> {
    Binding(get: { draft.value(field).text }, set: { draft.edit(field, text: $0) })
  }
  private func t(_ key: String, _ fallback: String) -> String { Review.text(key, fallback, language) }
}

extension GalaxySSIHealthInstruction {
  static func text(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.instruction." + key, fallback: fallback, language: language)
  }

  static func kindTitle(_ kind: Kind, _ language: String) -> String {
    let fallback: String
    switch kind {
    case .medication: fallback = "Medication"
    case .test: fallback = "Test"
    case .followUp: fallback = "Follow-up"
    case .rehabilitation: fallback = "Rehabilitation"
    case .lifestyle: fallback = "Lifestyle"
    case .other: fallback = "Other"
    }
    return text("kind_" + kind.rawValue, fallback, language)
  }

  static func fieldTitle(_ field: Field, _ language: String) -> String {
    let fallback: String
    switch field {
    case .name: fallback = "Name"
    case .dose: fallback = "Dose"
    case .unit: fallback = "Unit"
    case .route: fallback = "Route"
    case .frequency: fallback = "Frequency"
    case .start: fallback = "Start"
    case .end: fallback = "End"
    case .details: fallback = "Details"
    }
    return text("field_" + field.rawValue, fallback, language)
  }

  static func reviewTitle(_ review: Review, _ language: String) -> String {
    switch review {
    case .unreviewed: return text("unreviewed", "Unreviewed", language)
    case .transcribed: return text("transcribed", "Transcribed from source", language)
    case .notStated: return text("not_stated", "Not stated in source", language)
    }
  }
}
