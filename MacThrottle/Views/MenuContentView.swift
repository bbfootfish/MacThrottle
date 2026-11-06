import SwiftUI

func colorForTemperature(_ temp: Double) -> Color {
    switch temp {
    case ..<60: return .green
    case 60..<80: return .yellow
    case 80..<95: return .orange
    default: return .red
    }
}

struct MenuContentView: View {
    @Bindable var monitor: ThermalMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("热压状态：")
                Text(monitor.pressure.displayName)
                    .foregroundColor(monitor.pressure.color)
                    .fontWeight(.semibold)
                Spacer()
                if let temp = monitor.temperature {
                    Text("\(Int(temp.rounded()))°C")
                        .foregroundColor(colorForTemperature(temp))
                        .fontWeight(.semibold)
                        .help("来源：\(monitor.temperatureSource ?? "未知")")
                }
            }
            .font(.headline)

            if monitor.history.count >= 2 {
                HistoryGraphView(history: monitor.history, showFanSpeed: monitor.showFanSpeed)
            }

            if !monitor.timeInEachState.isEmpty {
                Divider()
                Text("统计")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TimeBreakdownView(
                    timeInEachState: monitor.timeInEachState,
                    totalDuration: monitor.totalHistoryDuration
                )
            }

            Divider()

            Text("设置")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("登录时启动", isOn: Binding(
                get: { LaunchAtLoginManager.shared.isEnabled },
                set: { _ in LaunchAtLoginManager.shared.toggle() }
            ))
            .controlSize(.small)

            if monitor.hasFans {
                Toggle("显示风扇转速", isOn: $monitor.showFanSpeed)
                    .controlSize(.small)
            }

            Toggle("在菜单栏显示温度", isOn: $monitor.showTemperatureInMenuBar)
                .controlSize(.small)

            Divider()

            Text("通知")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                Toggle("重度热压时提醒", isOn: $monitor.notifyOnHeavy)
                Toggle("临界热压时提醒", isOn: $monitor.notifyOnCritical)
                Toggle("恢复时提醒", isOn: $monitor.notifyOnRecovery)
                Toggle("提示音", isOn: $monitor.notificationSound)
            }
            .controlSize(.small)

            Divider()

            HStack {
                Button("关于") {
                    openAboutWindow()
                }
                .controlSize(.small)

                Spacer()

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private func openAboutWindow() {
        openWindow(id: "about")
        NSApp.activate(ignoringOtherApps: true)
    }
}
