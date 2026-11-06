import SwiftUI

struct AboutView: View {
    @State private var updateChecker = UpdateChecker()

    var body: some View {
        VStack(spacing: 16) {
            if #available(macOS 26.0, *) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .cornerRadius(24)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))
            } else {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .cornerRadius(24)
            }

            Text("MacThrottle")
                .font(.title)
                .fontWeight(.bold)

            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("监控 Mac 的热压状态\n在发生降频时收到通知。")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            updateSection

            if let url = URL(string: "https://github.com/angristan/MacThrottle") {
                if #available(macOS 26.0, *) {
                    Link("在 GitHub 上查看", destination: url)
                        .font(.caption)
                        .glassEffect()
                } else {
                    Link("在 GitHub 上查看", destination: url)
                        .font(.caption)
                }
            }
        }
        .padding(32)
        .frame(width: 320)
    }

    @ViewBuilder
    private var updateSection: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await updateChecker.checkForUpdates()
                }
            } label: {
                if updateChecker.isChecking {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("检查中…")
                    }
                } else {
                    Label("检查更新", systemImage: "arrow.clockwise")
                }
            }
            .disabled(updateChecker.isChecking)
            .controlSize(.small)
            .frame(minWidth: 150)

            updateStatus
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateChecker.status {
        case .idle:
            EmptyView()
        case .checking:
            Text("正在检查最新版本…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .updateAvailable(let update):
            VStack(spacing: 6) {
                Text("发现新版本 \(update.version)。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(destination: update.releaseURL) {
                    Label("打开发布页", systemImage: "arrow.up.forward.square")
                }
                .font(.caption)
            }
        case .upToDate:
            Text("已是最新版本。")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text("检查更新失败：\(message)")
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }
}
