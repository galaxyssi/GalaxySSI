import Foundation

struct VoiceMessageSpeechEvidence: Equatable {
  let confirmed: Bool
  let choice: Int
  static func capture(_ spoken: String) -> Self {
    func lexicon(_ key: String) -> [String] {
      guard let path = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"), let bundle = Bundle(path: path),
        let bytes = bundle.localizedString(forKey: "galaxyssi.voice_message." + key, value: "[]", table: nil).data(using: .utf8)
      else { return [] }
      return (try? JSONDecoder().decode([String].self, from: bytes)) ?? []
    }
    return parse(spoken, confirmations: ["confirm send", "send it", "yes, send it"] + lexicon("confirmation_phrases"),
      ordinals: lexicon("choice_ordinals"), prefixes: lexicon("choice_prefixes"), suffixes: lexicon("choice_suffixes"))
  }
  static func parse(_ spoken: String, confirmations: [String], ordinals: [String], prefixes: [String], suffixes: [String]) -> Self {
    let punctuation = CharacterSet(charactersIn: ".!,").union(CharacterSet(charactersIn:
      [0x3002, 0xFF01, 0xFF0C].compactMap { UnicodeScalar($0) }.map { String($0) }.joined()))
    let clean = spoken.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: punctuation)
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    var number = clean
    for prefix in prefixes + ["option "] where number.hasPrefix(prefix) { number.removeFirst(prefix.count) }
    for suffix in suffixes where number.hasSuffix(suffix) { number.removeLast(suffix.count) }
    number = number.trimmingCharacters(in: .whitespacesAndNewlines)
    let english = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
    let ordinal = clean.replacingOccurrences(of: #"^the | one$"#, with: "", options: .regularExpression)
    let choice = Int(number).flatMap { (1...500).contains($0) ? $0 : nil } ?? ordinals.firstIndex(of: number).map { $0 + 1 } ??
      english.firstIndex(of: ordinal).map { $0 + 1 } ?? 0
    return .init(confirmed: confirmations.contains(clean), choice: choice)
  }
}
