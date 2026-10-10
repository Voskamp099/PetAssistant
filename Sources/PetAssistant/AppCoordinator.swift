import AppKit
import Combine
import EventKit
import SwiftUI

/// 全局协调器：日历读取、播报、悬浮宠物、菜单栏的状态都走这里
@MainActor
final class AppCoordinator: NSObject, ObservableObject, NSApplicationDelegate {
    @Published var events: [CalendarEvent] = []
    @Published var authState: CalendarAuthState = .unknown
    @Published var isSpeaking: Bool = false
    @Published var lastSpokenText: String = ""
    @Published var todos: [TodoItem] = []
    @Published var isPetVisible = false
    @Published var petHotKeyAvailable = false

    private let store = EKEventStore()
    private let speaker = Speaker()
    private let todoStore = TodoStore()
    /// 启动只有猫；点击循环：schedule → todos → none → schedule ...
    private enum CaptionMode { case schedule, todos, none }
    private var captionMode: CaptionMode = .schedule
    private var todoEditorWindow: NSWindow?
    /// 当前载入的是哪一天的 To-do list 文件
    private var currentDayKey: String = TodoStore.key(for: Date())
    private var dayRolloverTimer: Timer?

    private var petPanel: PetPanel?
    private var petVisibilityHotKey: PetVisibilityHotKey?
    private var loginObserver: Any?
    private var wakeObserver: Any?

    override init() {
        super.init()
        self.todos = todoStore.load(for: Date())
        self.currentDayKey = TodoStore.key(for: Date())
        startDayRolloverWatcher()
        observeLogin()
    }

    /// UI 用的当前日期 label
    var currentDateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日 · EEEE"
        return f.string(from: Date())
    }

    /// 每 60 秒检查一次跨日期；如果切换到新一天，重载当天文件
    private func startDayRolloverWatcher() {
        dayRolloverTimer?.invalidate()
        dayRolloverTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tickDayRollover() }
        }
    }

    @MainActor
    private func tickDayRollover() {
        let newKey = TodoStore.key(for: Date())
        guard newKey != currentDayKey else { return }
        currentDayKey = newKey
        todos = todoStore.load(for: Date())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hotKey = PetVisibilityHotKey { [weak self] in self?.togglePetVisibility() }
        petVisibilityHotKey = hotKey
        petHotKeyAvailable = hotKey.isRegistered
        Task { @MainActor in await bootstrap() }
    }

    // Finder / Spotlight 再次打开 App 时，把已隐藏的猫恢复，不触发播报。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPet()
        return false
    }

    // MARK: - 启动流程

    private func bootstrap() async {
        // 1. 权限
        let granted = await requestCalendarAccess()
        authState = granted ? .granted : .denied

        // 2. 拉今日日程
        if granted {
            await refreshToday()
        }

        // 3. 挂出桌面悬浮宠物
        installPetPanel()

        // 启动只显示原来的猫；只有用户点击时才显示字幕、朗读一次。
    }

    // MARK: - 日历权限

    private func requestCalendarAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            do {
                return try await store.requestFullAccessToEvents()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - 日程读取

    func refreshToday() async {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)
        events = ekEvents
            .sorted { $0.startDate < $1.startDate }
            .map { CalendarEvent(from: $0) }
    }

    // MARK: - 播报

    func speakGreeting() {
        tickDayRollover()
        captionMode = .todos
        let n = composeNarration(for: events)
        lastSpokenText = n.display
        speaker.speak(n.spoken) { [weak self] in
            self?.isSpeaking = false
        }
        isSpeaking = true
    }

    /// 点击宠物：3 态循环
    ///   click 1 → 播 schedule（下一次 todos）
    ///   click 2 → 播 todos（下一次 none）
    ///   click 3 → 清空字幕，不读（下一次 schedule）
    func speakScheduleNow() {
        switch captionMode {
        case .schedule:
            speakGreeting()
        case .todos:
            speakTodos()
        case .none:
            captionMode = .schedule
            clearCaption()
        }
    }

    /// To-do list 编辑面板直接念一次，下一次点击宠物收起字幕。
    func speakTodosDirectly() {
        speakTodos()
    }

    private func clearCaption() {
        speaker.stop()
        lastSpokenText = ""
        isSpeaking = false
    }

    private func speakTodos() {
        tickDayRollover()
        captionMode = .none
        let pending = todos.filter { !$0.done }
        if pending.isEmpty {
            let status = todos.isEmpty
                ? "今天的 To-do list 还没有待办事项。"
                : "今天的 To-do list 共 \(todos.count) 项，全部完成了！"
            let text = status
            lastSpokenText = text
            isSpeaking = true
            speaker.speak(text) { [weak self] in self?.isSpeaking = false }
            return
        }
        let header = "今天的 To-do list 还有 \(pending.count) 项待办。"
        let body = pending.enumerated().map { i, t in
            "第\(cnN(i + 1))项，\(t.title)。"
        }.joined(separator: "\n")
        let text = header + "\n" + body
        lastSpokenText = text
        isSpeaking = true
        speaker.speak(text) { [weak self] in self?.isSpeaking = false }
    }

    private func greetingForNow(at date: Date = Date()) -> String {
        DailyGreeting.text(at: date, allTodosComplete: !todos.isEmpty && todos.allSatisfy(\.done))
    }

    private func cnN(_ n: Int) -> String {
        switch n {
        case 1: return "一"
        case 2: return "二"
        case 3: return "三"
        case 4: return "四"
        case 5: return "五"
        case 6: return "六"
        case 7: return "七"
        case 8: return "八"
        case 9: return "九"
        case 10: return "十"
        default: return "\(n)"
        }
    }

    // MARK: - To-do list 增删改

    func addTodo(title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        todos.append(TodoItem(title: t))
        persistTodos()
    }

    func toggleDone(id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].done.toggle()
        persistTodos()
    }

    func deleteTodo(id: UUID) {
        todos.removeAll { $0.id == id }
        persistTodos()
    }

    private func persistTodos() {
        todoStore.save(todos, for: Date())
    }

    // MARK: - To-do list 编辑窗口

    func openTodoEditor() {
        if let w = todoEditorWindow {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let view = TodoEditorView(coordinator: self)
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "今日 To-do list · 总裁小助理"
        win.setContentSize(NSSize(width: 420, height: 480))
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        self.todoEditorWindow = win
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { [weak self, weak win] _ in
            Task { @MainActor in
                if self?.todoEditorWindow === win {
                    self?.todoEditorWindow = nil
                }
            }
        }
    }

    func stopSpeaking() {
        speaker.stop()
        isSpeaking = false
    }

    // MARK: - 声音切换（菜单栏调用）

    var availableVoices: [(id: String, label: String)] { speaker.availableVoices }
    var currentVoiceId: String { speaker.currentVoiceId }

    func switchVoice(to id: String) {
        objectWillChange.send()
        speaker.setVoice(id: id)
        let preview = "好，今天的日程我来给你念。"
        lastSpokenText = preview
        speaker.speak(preview) { [weak self] in
            self?.isSpeaking = false
        }
        isSpeaking = true
    }

    /// 让下一次点宠物直接念 To-do list（保留兼容老调用）
    func setNextToTodos() {
        speakTodosDirectly()
    }

    private func composeGreeting(for events: [CalendarEvent]) -> Narration {
        return composeNarration(for: events)
    }

    /// 双路径产出：display 给字幕用，spoken 给 TTS 用。
    /// display 用阿拉伯数字简洁；spoken 用中文汉字让 TTS 整段 zh 不切 voice。
    private func composeNarration(for events: [CalendarEvent]) -> Narration {
        let now = Date()
        let greeting = greetingForNow(at: now)
        if events.isEmpty {
            let text = greeting + "\n今天日历里没有安排。"
            return Narration(display: text, spoken: text)
        }

        let upcoming = events.filter { $0.endDate >= now }
        let displayed = upcoming.isEmpty ? events : upcoming
        let header = greeting + "\n" + (upcoming.isEmpty
            ? "今天的日程时间已结束，回顾一下安排。"
            : "今天的日程如下。")
        let displayLines = displayed.map { formatEventDisplay($0) }
        let spokenLines = displayed.map { formatEventSpoken($0) }
        return Narration(
            display: header + "\n" + displayLines.joined(separator: "\n"),
            spoken: header + "\n" + spokenLines.joined(separator: "\n")
        )
    }

    // MARK: - 字幕（display）路径：阿拉伯数字

    /// display 一行：`10:00 AM – 11:00 AM` + 标题 + 地点。备注首行。
    private func formatEventDisplay(_ e: CalendarEvent) -> String {
        var parts: [String] = []
        if e.isAllDay {
            parts.append("全天")
        } else {
            parts.append(EventTimeFormat.range(from: e.startDate, to: e.endDate))
        }
        parts.append(e.title)
        if let loc = e.location, !loc.isEmpty {
            parts.append("在 \(loc)")
        }
        var line = parts.joined(separator: "，")
        if let notes = e.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let first = notes.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            if !first.isEmpty { line += "。\(first)" }
        }
        return line + "。"
    }

    // MARK: - TTS（spoken）路径：时间用中文，英文标题交给英文 voice

    /// spoken 一行：上午十点到十一点，标题，地点。
    private func formatEventSpoken(_ e: CalendarEvent) -> String {
        let timeSpoken: String
        if e.isAllDay {
            timeSpoken = "今天全天"
        } else {
            timeSpoken = cnRange(start: e.startDate, end: e.endDate)
        }

        var parts: [String] = [timeSpoken, e.title]
        if let loc = e.location, !loc.isEmpty {
            parts.append("在 \(loc)")
        }
        var line = parts.joined(separator: "，")
        if let notes = e.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let first = notes.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            if !first.isEmpty { line += "。备注：\(first)" }
        }
        return line + "。"
    }

    private func cnRange(start: Date, end: Date) -> String {
        let cs = Calendar.current.dateComponents([.hour, .minute], from: start)
        let ce = Calendar.current.dateComponents([.hour, .minute], from: end)
        let sh = cs.hour ?? 0
        let sm = cs.minute ?? 0
        let eh = ce.hour ?? 0
        let em = ce.minute ?? 0

        // 起止时间各自标明时段，避免跨中午或午夜时念错。
        let sH12: Int
        let sPeriod: String
        switch sh {
        case 0:        sPeriod = "凌晨"; sH12 = 12
        case 1...5:    sPeriod = "凌晨"; sH12 = sh
        case 6:        sPeriod = "早上"; sH12 = 6
        case 7...11:   sPeriod = "上午"; sH12 = sh
        case 12:       sPeriod = "中午"; sH12 = 12
        case 13...17:  sPeriod = "下午"; sH12 = sh - 12
        case 18:       sPeriod = "傍晚"; sH12 = 6
        default:       sPeriod = "晚上"; sH12 = sh - 12
        }

        let eH12: Int = {
            if eh == 0 { return 12 }
            if eh <= 12 { return eh }
            return eh - 12
        }()

        let sText = "\(sPeriod)\(cnH(sH12))点" + (sm == 0 ? "" : cnM(sm))
        let ePeriod: String
        switch eh {
        case 0...5: ePeriod = "凌晨"
        case 6: ePeriod = "早上"
        case 7...11: ePeriod = "上午"
        case 12: ePeriod = "中午"
        case 13...17: ePeriod = "下午"
        case 18: ePeriod = "傍晚"
        default: ePeriod = "晚上"
        }
        let endDay = Calendar.current.isDate(start, inSameDayAs: end) ? "" : "次日"
        let endPeriod = ePeriod == sPeriod && endDay.isEmpty ? "" : ePeriod
        let eText = "\(endDay)\(endPeriod)\(cnH(eH12))点" + (em == 0 ? "" : cnM(em))
        return "\(sText)到\(eText)"
    }

    private func cnH(_ n: Int) -> String {
        switch n {
        case 0:  return "零"
        case 1:  return "一"
        case 2:  return "二"
        case 3:  return "三"
        case 4:  return "四"
        case 5:  return "五"
        case 6:  return "六"
        case 7:  return "七"
        case 8:  return "八"
        case 9:  return "九"
        case 10: return "十"
        case 11: return "十一"
        case 12: return "十二"
        default: return "\(n)"
        }
    }

    private func cnM(_ m: Int) -> String {
        if m < 10 {
            return ["零","一","二","三","四","五","六","七","八","九"][m] + "分"
        }
        if m == 10 { return "十分" }
        if m < 20 { return "十" + ["一","二","三","四","五","六","七","八","九"][m - 11] + "分" }
        if m == 20 { return "二十分" }
        let tens = m / 10
        let ones = m % 10
        if ones == 0 {
            return ["二","三","四","五"][tens - 2] + "十分"
        }
        return ["二","三","四","五"][tens - 2] + "十" +
               ["一","二","三","四","五","六","七","八","九"][ones - 1] + "分"
    }

    // MARK: - 悬浮宠物

    func installPetPanel() {
        if petPanel != nil { return }
        let panel = PetPanel()
        panel.attach(coordinator: self)
        panel.orderFrontRegardless()
        petPanel = panel
        isPetVisible = true
    }

    func showPet() {
        installPetPanel()
        petPanel?.orderFrontRegardless()
        isPetVisible = true
    }

    func hidePet() {
        stopSpeaking()
        petPanel?.orderOut(nil)
        isPetVisible = false
    }

    func togglePetVisibility() {
        if isPetVisible { hidePet() } else { showPet() }
    }

    // MARK: - 监听登录与唤醒，确保重新开机/唤醒后能再问候一次

    private func observeLogin() {
        loginObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // 占位：未来要做"系统刚登录完"的判定可借 sessionDidLaunch 通知
            _ = self
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // 唤醒可触发一次刷新与可选播报（默认不重播，免得吵）
            Task { @MainActor in await self?.refreshToday() }
        }
    }

    deinit {
        dayRolloverTimer?.invalidate()
        if let o = loginObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        if let o = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
    }
}

/// 每次播报读取电脑的当前时间和时区，不缓存启动时的问候。
enum DailyGreeting {
    static func text(at date: Date = Date(), calendar: Calendar = .current, allTodosComplete: Bool = false) -> String {
        switch calendar.component(.hour, from: date) {
        case 5...11:
            return "赵总早上好，新的一天又开始了！看看今天有哪些任务。"
        case 12...13:
            return "赵总中午好，记得好好吃饭。我们看看今天的任务。"
        case 14...17:
            return "赵总下午好，辛苦啦！看看接下来有哪些任务。"
        case 18...23:
            return allTodosComplete
                ? "赵总晚上好，今天太厉害了，To-do list 都完成了！"
                : "赵总晚上好，今天辛苦了！今天的任务都完成了吗？我们一起回顾一下。"
        default:
            return "赵总，夜深了，今天辛苦了。记得早点休息，我们再看看今天的任务。"
        }
    }
}

/// 双路径字符串：display 给字幕看，spoken 给 TTS 念。
struct Narration {
    let display: String
    let spoken: String
}

// MARK: - To-do list 编辑窗口视图

private struct TodoEditorView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var newTitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checklist").foregroundColor(.purple)
                Text("今日 To-do list").font(.headline)
                Spacer()
                Text("\(coordinator.todos.filter { !$0.done }.count) 待办 / 共 \(coordinator.todos.count) 项")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(coordinator.currentDateLabel)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                TextField("新增项…（回车添加）", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addNew() }
                Button("+") { addNew() }
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Divider()

            if coordinator.todos.isEmpty {
                Text("(列表为空)")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(coordinator.todos) { item in
                            HStack(spacing: 8) {
                                Button(action: { coordinator.toggleDone(id: item.id) }) {
                                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(item.done ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                Text(item.title)
                                    .strikethrough(item.done, color: .secondary)
                                    .foregroundColor(item.done ? .secondary : .primary)
                                Spacer()
                                Button(action: { coordinator.deleteTodo(id: item.id) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(item.done ? 0.04 : 0))
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                Spacer()
                Button("念 To-do list 给赵总") {
                    coordinator.speakTodosDirectly()
                }
                .disabled(coordinator.todos.filter { !$0.done }.isEmpty)
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 400, height: 460)
    }

    private func addNew() {
        let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        coordinator.addTodo(title: t)
        newTitle = ""
    }
}
