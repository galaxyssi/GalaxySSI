import Foundation

enum MicrosoftTTSVoiceCatalog {
  static let xiaoxiao = "zh-CN-XiaoxiaoNeural"
  static let xiaoxiaoDragonHDFlash = "zh-CN-Xiaoxiao:DragonHDFlashLatestNeural"
  static let xiaoxiao2DragonHDFlash = "zh-CN-Xiaoxiao2:DragonHDFlashLatestNeural"

  static let voices = [
    xiaoxiao,
    xiaoxiaoDragonHDFlash,
    xiaoxiao2DragonHDFlash,
  ]

  static func canonical(_ value: String?) -> String {
    let candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return voices.first { $0.caseInsensitiveCompare(candidate) == .orderedSame } ?? xiaoxiao
  }
}
