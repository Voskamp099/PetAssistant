import AVFoundation
import Foundation

/// 保留英文词间空格，按中英语言分段；由系统队列顺序播放。
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()

    struct Segment: Equatable {
        let text: String
        let lang: String
    }

    private var pending: [AVSpeechUtterance] = []
    private var completion: (@MainActor () -> Void)?
    let voiceKey = "PetAssistant.voiceId"

    private static let preferredVoices: [(id: String, label: String)] = [
        ("com.apple.ttsbundle.siri_Yu-Shu_zh-CN_compact", "Yu-shu · 中文女 · 偏亮"),
        ("com.apple.ttsbundle.siri_Li-Mu_zh-CN_compact", "Li-Mu · 中文男 · 稳"),
        ("com.apple.voice.compact.zh-CN.Tingting", "Tingting · 中文经典"),
        ("com.apple.voice.compact.en-US.Samantha", "Samantha · 英文美音"),
        ("com.apple.voice.compact.en-GB.Daniel", "Daniel · 英文英音")
    ]

    /// 只显示已安装声音；系统版本变化时按名称匹配实际 identifier。
    let availableVoices: [(id: String, label: String)]
    private(set) var currentVoiceId: String

    override init() {
        let installed = AVSpeechSynthesisVoice.speechVoices()
        var choices: [(id: String, label: String)] = []
        for preferred in Self.preferredVoices {
            let name = preferred.label.components(separatedBy: " · ")[0]
            if let voice = installed.first(where: { $0.identifier == preferred.id })
                ?? installed.first(where: {
                    $0.name.replacingOccurrences(of: "-", with: "")
                        .caseInsensitiveCompare(name.replacingOccurrences(of: "-", with: "")) == .orderedSame
                }) {
                choices.append((voice.identifier, preferred.label))
            }
        }
        for language in ["zh-CN", "en-US"] where !choices.contains(where: { choice in
            installed.contains { $0.identifier == choice.id && $0.language == language }
        }) {
            if let voice = installed.first(where: { $0.language == language }) {
                choices.append((voice.identifier, "\(voice.name) · \(language)"))
            }
        }
        availableVoices = choices
        let saved = UserDefaults.standard.string(forKey: "PetAssistant.voiceId")
        currentVoiceId = saved.flatMap { id in choices.contains { $0.id == id } ? id : nil }
            ?? choices.first?.id ?? ""
        super.init()
        UserDefaults.standard.set(currentVoiceId, forKey: voiceKey)
        synth.delegate = self
    }

    func setVoice(id: String) {
        guard availableVoices.contains(where: { $0.id == id }) else { return }
        currentVoiceId = id
        UserDefaults.standard.set(id, forKey: voiceKey)
    }

    func speak(_ text: String, onFinish: @escaping @MainActor () -> Void = {}) {
        stop()
        let segments = Self.splitByLanguage(Self.speechText(text))
        guard !segments.isEmpty else { onFinish(); return }
        completion = onFinish
        pending = segments.map { segment in
            let utterance = AVSpeechUtterance(string: segment.text)
            utterance.voice = voiceForSegment(lang: segment.lang)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (segment.lang == "en" ? 0.85 : 0.92)
            utterance.pitchMultiplier = segment.lang == "en" ? 1.0 : 1.08
            utterance.postUtteranceDelay = 0.12
            return utterance
        }
        for utterance in pending { synth.speak(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finishUtterance(id) }
    }

    private func finishUtterance(_ id: ObjectIdentifier) {
        // 已取消的旧 utterance 回调不能清空新一轮播放或提前结束。
        guard let index = pending.firstIndex(where: { ObjectIdentifier($0) == id }) else { return }
        pending.remove(at: index)
        if pending.isEmpty {
            let finished = completion
            completion = nil
            finished?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.cancelUtterance(id) }
    }

    private func cancelUtterance(_ id: ObjectIdentifier) {
        guard pending.contains(where: { ObjectIdentifier($0) == id }) else { return }
        pending.removeAll()
        let finished = completion
        completion = nil
        finished?()
    }

    func stop() {
        // 先使旧回调失效，再清空系统队列。
        pending.removeAll()
        completion = nil
        synth.stopSpeaking(at: .immediate)
    }

    /// 缩写先展开成完整英文词组，避免把 TODO 念成一个单词。
    static func speechText(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\\bTODO\\b(?:\\s+list\\b)?",
            with: "to-do list",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// 字母决定语言；数字、空格及 ASCII 标点跟随当前语言。
    /// 因此「第 2 项」保持中文，「Weekly team sync v2.1」保持完整英文。
    static func splitByLanguage(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var buffer = ""
        var language: String?

        func flush() {
            if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(Segment(text: buffer, lang: language ?? "zh"))
            }
            buffer = ""
        }

        for character in text {
            let nextLanguage = languageForCharacter(character)
            if let nextLanguage {
                if let current = language, current != nextLanguage { flush() }
                language = nextLanguage
            }
            buffer.append(character)
        }
        flush()
        return segments
    }

    private static func languageForCharacter(_ character: Character) -> String? {
        if character.isLetter {
            let latin = character.unicodeScalars.allSatisfy {
                (0x0041...0x024F).contains($0.value) || (0x0300...0x036F).contains($0.value)
            }
            return latin ? "en" : "zh"
        }
        if "，。！？；：、（）【】\n".contains(character) { return "zh" }
        return nil
    }

    func voiceForSegment(lang: String) -> AVSpeechSynthesisVoice? {
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let selected = installed.first { $0.identifier == currentVoiceId }
        // 英文选择只覆盖英文段；中文选择只覆盖中文段。
        if let selected, selected.language.hasPrefix(lang) { return selected }
        if lang == "en" {
            return installed.first { $0.language == "en-US" && $0.name == "Samantha" }
                ?? AVSpeechSynthesisVoice(language: "en-US")
                ?? installed.first { $0.language.hasPrefix("en") }
        }
        return installed.first { $0.language == "zh-CN" && $0.name == "Yu-shu" }
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
            ?? installed.first { $0.language.hasPrefix("zh") }
    }
}
