import SwiftUI
import AppKit

/// 桌面宠物：真猫 PNG + 上方字幕气泡。**完全静止**，不晃不眨。
/// 点击整窗/任意位置触发 `coordinator.speakScheduleNow()`（由 PetPanel.mouseDown 拦截）。
struct PetView: View {
    @ObservedObject var coordinator: AppCoordinator
    var onSizeChange: ((CGSize) -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            // 字幕气泡
            CaptionBubble(
                text: coordinator.lastSpokenText,
                isSpeaking: coordinator.isSpeaking
            )
            .frame(maxWidth: 340)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)

            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 130, height: 14)
                    .blur(radius: 6)
                    .offset(y: 4)

                // 保留当前猫图尺寸，只收紧窗口和字幕间距。
                CatImage()
                    .frame(width: 240, height: 180)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { onSizeChange?(geometry.size) }
                    .onChange(of: geometry.size) { _, size in onSizeChange?(size) }
            }
        }
    }
}

// MARK: - 显式加载猫图（防 SwiftUI Image("name") 找不到资源时静默空白）

private struct CatImage: View {
    var body: some View {
        let nsImage = catNSImage()
        if let img = nsImage {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // 资源加载失败 fallback
            VStack(spacing: 4) {
                Text("🐱")
                    .font(.system(size: 96))
                Text("（图未加载）")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func catNSImage() -> NSImage? {
        let name = "cat_idle"
        let ext = "png"
        if let url = Bundle.main.url(forResource: name, withExtension: ext),
           let img = NSImage(contentsOf: url) {
            return img
        }
        let fallback = Bundle.main.bundlePath + "/Contents/Resources/\(name).\(ext)"
        if let img = NSImage(contentsOf: URL(fileURLWithPath: fallback)) {
            return img
        }
        return nil
    }
}

// MARK: - 字幕气泡

private struct CaptionBubble: View {
    let text: String
    let isSpeaking: Bool

    var body: some View {
        if text.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 4) {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.82))
                    .multilineTextAlignment(.leading)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.86))
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                        }
                    )
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                if isSpeaking {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle().fill(Color.gray.opacity(0.55))
                                .frame(width: 4, height: 4)
                                .scaleEffect(isSpeaking ? 1.2 : 0.6)
                                .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: isSpeaking)
                        }
                    }
                }
            }
            .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
        }
    }
}
