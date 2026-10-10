import SwiftUI
import AppKit

@main
struct PetAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppCoordinator.self) private var coordinator

    var body: some Scene {
        // 菜单栏入口：图标常驻在屏幕顶部菜单栏，点击展开日程卡
        MenuBarExtra("总裁小助理", systemImage: "pawprint.fill") {
            MenuBarContent()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.window)

        // 主窗口 SwiftUI Scene：这里只是兜底，实际界面用 NSPanel 自己挂
        Settings {
            EmptyView()
        }
    }
}
