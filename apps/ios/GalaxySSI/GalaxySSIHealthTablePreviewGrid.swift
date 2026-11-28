import SwiftUI

@MainActor
struct GalaxySSIHealthTablePreviewGrid: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let sample: GalaxySSIHealthTableSourceSample
  @State private var selected: Cell?

  private struct Cell: Identifiable {
    let id = UUID()
    let title: String
    let text: String
  }

  var body: some View {
    ScrollView([.horizontal, .vertical]) {
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          header("#", width: 54)
          ForEach(sample.headers.indices, id: \.self) { column in
            let letter = String("ABCDEFGHIJKL".dropFirst(column).prefix(1))
            let title = sample.headers[column]
            Button {
              guard scene == .active, !title.isEmpty else { return }
              selected = Cell(title: letter, text: title)
            } label: {
              header(letter + (title.isEmpty ? "" : "\n" + title), width: 156)
            }
            .buttonStyle(.plain).disabled(title.isEmpty)
          }
        }
        ForEach(sample.rows.indices, id: \.self) { row in
          HStack(spacing: 0) {
            Text(String(sample.rowNumbers[row])).font(.caption.monospaced())
              .frame(width: 54, height: 86)
            ForEach(sample.headers.indices, id: \.self) { column in
              let text = sample.rows[row][column]
              Button {
                guard scene == .active, !text.isEmpty else { return }
                selected = Cell(title: String(sample.rowNumbers[row]) + " · " + String(column + 1), text: text)
              } label: {
                Text(text.isEmpty ? "\u{2014}" : text)
                  .font(.system(.body, design: .monospaced)).foregroundColor(.primary)
                  .lineLimit(3).multilineTextAlignment(.leading)
                  .padding(8).frame(width: 156, height: 86, alignment: .topLeading)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain).disabled(text.isEmpty)
              .accessibilityLabel(String(sample.rowNumbers[row]) + ", " + String(column + 1) + ": " +
                (text.isEmpty ? t("empty_cell", "Empty") : text))
              .overlay(Rectangle().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
            }
          }
          .background(row.isMultiple(of: 2) ? Color.secondary.opacity(0.05) : Color.clear)
        }
      }
      .textSelection(.disabled)
    }
    .frame(height: min(480, CGFloat(sample.rows.count) * 86 + 64))
    .sheet(item: $selected) { cell in
      if scene == .active {
        NavigationView {
          ScrollView { Text(cell.text).textSelection(.disabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
            .navigationTitle(cell.title)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button { selected = nil } label: { Image(systemName: "xmark") }
                  .accessibilityLabel(t("close_cell", "Close cell"))
              }
            }
        }
        .navigationViewStyle(.stack)
      }
    }
    .onChange(of: scene) { if $0 != .active { selected = nil } }
    .onDisappear { selected = nil }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in selected = nil }
  }

  private func header(_ title: String, width: CGFloat) -> some View {
    Text(title).font(.caption.weight(.semibold)).lineLimit(3)
      .frame(width: width, height: 64)
      .background(Color.secondary.opacity(0.1))
      .overlay(Rectangle().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.table_source." + key, fallback: fallback, language: language)
  }
}
