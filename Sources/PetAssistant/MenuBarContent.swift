import SwiftUI
import AppKit

struct MenuBarContent: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pawprint.fill")
                    .foregroundColor(.purple)
                Text("总裁小助理")
                    .font(.headline)
                Spacer()
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.plain)
                .help("置前台")
            }

            Divider()

            Button {
                coordinator.togglePetVisibility()
            } label: {
                HStack {
                    Label(coordinator.isPetVisible ? "隐藏宠物" : "显示宠物",
                          systemImage: coordinator.isPetVisible ? "eye.slash" : "eye")
                    Spacer()
                    if coordinator.petHotKeyAvailable {
                        Text("⌃⌥⌘P").font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            switch coordinator.authState {
            case .unknown:
                Label("正在请求日历权限…", systemImage: "hourglass")
            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Label("日历权限被拒绝", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Button("打开系统设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            case .granted:
                Text("今天一共 \(coordinator.events.count) 件事")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !coordinator.events.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(coordinator.events.prefix(8)) { e in
                        HStack(alignment: .top) {
                            Text(e.timeText)
                                .font(.caption.monospaced())
                                .frame(width: 138, alignment: .leading)
                                .foregroundColor(.secondary)
                            Text(e.title)
                                .font(.body)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if coordinator.authState == .granted {
                Text("今天没有安排。")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            }

            Divider()

            Button {
                coordinator.openTodoEditor()
            } label: {
                let pending = coordinator.todos.filter { !$0.done }.count
                Label(pending > 0 ? "To-do list · \(pending) 待办" : "To-do list · 列表", systemImage: "checklist")
            }

            Divider()

            // 声音子菜单（当场挑声音听感）
            Picker("声音", selection: Binding(
                get: { coordinator.currentVoiceId },
                set: { coordinator.switchVoice(to: $0) }
            )) {
                ForEach(coordinator.availableVoices, id: \.id) { v in
                    Text(v.label).tag(v.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Divider()

            HStack {
                Button {
                    Task { await coordinator.refreshToday() }
                } label: {
                    Label("刷新日程", systemImage: "arrow.clockwise")
                }
                Spacer()
                Button {
                    coordinator.speakGreeting()
                } label: {
                    Label(coordinator.isSpeaking ? "再说一遍" : "播报今日", systemImage: "play.circle")
                }
                .disabled(coordinator.isSpeaking || coordinator.events.isEmpty && coordinator.authState != .granted)
            }
            HStack {
                Button {
                    coordinator.stopSpeaking()
                } label: {
                    Label("闭嘴", systemImage: "stop.circle")
                }
                .disabled(!coordinator.isSpeaking)
                Spacer()
                Button("退出") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}
