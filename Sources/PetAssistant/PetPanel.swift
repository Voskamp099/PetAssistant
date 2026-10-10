import AppKit
import SwiftUI

/// 桌面悬浮宠物窗：浮在桌面、不进 Dock、可拖动、右键菜单、点击发日程。
/// 起始位置 / 移动后位置都持久化到 UserDefaults，多次启动不漂移。
final class PetPanel: NSPanel {
    weak var coordinator: AppCoordinator?
    private var hosting: NSHostingView<AnyView>?
    private var mouseDownTime: Date?
    private var mouseDownLocation: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var didDrag = false
    private var eventMonitor: Any?
    private static let frameKey = "PetAssistant.panelFrame"

    init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 360, height: 216)

        // 起始位置：用户拖过的位置优先，没有就右上
        let saved = (UserDefaults.standard.string(forKey: Self.frameKey))
            .flatMap { NSRectFromString($0) }
        let origin: NSPoint
        if let r = saved, r.width > 200, r.height >= 180 {
            origin = r.origin
        } else {
            origin = NSPoint(
                x: screenFrame.maxX - size.width - 60,
                y: screenFrame.maxY - size.height - 80
            )
        }
        let rect = NSRect(origin: origin, size: size)

        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle
        ]
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isOpaque = false
        self.becomesKeyOnlyIfNeeded = true
        self.acceptsMouseMovedEvents = true
        self.minSize = NSSize(width: 360, height: 196)

        // 占位 NSView，等 attach() 替换为真宿主视图
        let placeholder = NSView(frame: NSRect(origin: .zero, size: size))
        placeholder.wantsLayer = true
        placeholder.layer?.backgroundColor = .clear
        self.contentView = placeholder

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistFrame),
            name: NSWindow.didMoveNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistFrame),
            name: NSWindow.didResizeNotification,
            object: self
        )

        // 宿主视图会吞鼠标事件；统一处理点击和拖动，避免两套事件路径竞争。
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .rightMouseDown, .leftMouseDown, .leftMouseDragged, .leftMouseUp
        ]) { [weak self] event in
            guard let self, event.window === self else { return event }
            switch event.type {
            case .rightMouseDown:
                self.showContextMenu(at: event.locationInWindow)
            case .leftMouseDown:
                self.mouseDownTime = Date()
                self.mouseDownLocation = self.convertPoint(toScreen: event.locationInWindow)
                self.dragStartOrigin = self.frame.origin
                self.didDrag = false
            case .leftMouseDragged:
                self.moveWithPointer(at: self.convertPoint(toScreen: event.locationInWindow))
            case .leftMouseUp:
                self.moveWithPointer(at: self.convertPoint(toScreen: event.locationInWindow))
                if !self.didDrag, let down = self.mouseDownTime,
                   Date().timeIntervalSince(down) < 0.4 {
                    self.coordinator?.speakScheduleNow()
                }
                self.mouseDownTime = nil
            default:
                return event
            }
            return nil
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        NotificationCenter.default.removeObserver(self)
    }

    private func moveWithPointer(at cursor: NSPoint) {
        guard mouseDownTime != nil else { return }
        let dx = cursor.x - mouseDownLocation.x
        let dy = cursor.y - mouseDownLocation.y
        guard didDrag || abs(dx) >= 4 || abs(dy) >= 4 else { return }
        didDrag = true
        var origin = NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy)
        let destination = NSScreen.screens.first { $0.frame.contains(cursor) } ?? screen ?? NSScreen.main
        if let visible = destination?.visibleFrame {
            origin.x = max(visible.minX, min(origin.x, visible.maxX - frame.width))
            origin.y = max(visible.minY, min(origin.y, visible.maxY - frame.height))
        }
        setFrameOrigin(origin)
    }

    func attach(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let view = AnyView(PetView(coordinator: coordinator, onSizeChange: { [weak self] size in
            self?.fitContent(to: size)
        }))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: self.frame.size)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        self.contentView = host
        self.hosting = host
    }

    /// 字幕增减时保持猫的底部位置，只向上扩展紧凑窗口。
    private func fitContent(to size: CGSize) {
        let contentSize = NSSize(width: 360, height: max(196, ceil(size.height)))
        guard abs(frame.height - contentSize.height) > 0.5 else { return }
        var rect = NSRect(origin: frame.origin, size: contentSize)
        let screen = self.screen ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            rect.origin.x = max(visible.minX, min(rect.minX, visible.maxX - rect.width))
            rect.origin.y = max(visible.minY, min(rect.minY, visible.maxY - rect.height))
        }
        setFrame(rect, display: true)
    }

    @objc private func persistFrame() {
        UserDefaults.standard.set(NSStringFromRect(self.frame), forKey: Self.frameKey)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - 鼠标事件：单击播报 / 拖动窗口 / 右键菜单

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(at: event.locationInWindow)
    }

    private func showContextMenu(at location: NSPoint) {
        let menu = NSMenu()
        let hide = NSMenuItem(
            title: "🐱  隐藏宠物",
            action: #selector(hidePet),
            keyEquivalent: "h"
        )
        hide.target = self
        menu.addItem(hide)

        menu.addItem(NSMenuItem.separator())

        let openTodo = NSMenuItem(
            title: "📝  打开 To-do list 编辑",
            action: #selector(openTodo),
            keyEquivalent: "t"
        )
        openTodo.target = self
        menu.addItem(openTodo)

        let quit = NSMenuItem(
            title: "✕  退出总裁小助理",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        menu.popUp(positioning: nil, at: location, in: self.contentView)
    }

    @objc private func hidePet() {
        coordinator?.hidePet()
    }

    @objc private func openTodo() {
        coordinator?.openTodoEditor()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

}
