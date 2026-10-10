import Foundation

struct TodoItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var done: Bool = false
    var createdAt: Date = Date()
}

/// 按日期分文件存：~/Library/Application Support/PetAssistant/todos/YYYY-MM-DD.json
/// 自动建目录。每天开始打开 App 看到的是当天文件，跨过零点时主进程每 60s 检测一次自动切换。
final class TodoStore {
    static var directoryURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PetAssistant/todos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func key(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func fileURL(for date: Date) -> URL {
        directoryURL.appendingPathComponent("\(key(for: date)).json")
    }

    func load(for date: Date) -> [TodoItem] {
        guard let data = try? Data(contentsOf: Self.fileURL(for: date)) else { return [] }
        return (try? JSONDecoder().decode([TodoItem].self, from: data)) ?? []
    }

    func save(_ items: [TodoItem], for date: Date) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(items) {
            try? data.write(to: Self.fileURL(for: date), options: .atomic)
        }
    }

    /// 历史日期列表（用于将来"翻看某天的 TODO"功能预留）
    func availableDays() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: Self.directoryURL.path) else { return [] }
        return files.filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted(by: >)
    }
}
