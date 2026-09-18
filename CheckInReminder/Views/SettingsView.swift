//
//  SettingsView.swift
//  时间窗 / 提醒方式 / 重复提醒等
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {

    @StateObject private var settings = AppSettings.shared
    @StateObject private var location = LocationManager.shared
    @StateObject private var engine   = ReminderEngine.shared
    @StateObject private var sounds   = SoundStore.shared

    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var importMessage: String?

    private var startDate: Binding<Date> {
        Binding(
            get: { settings.dateToday(atMinute: settings.windowStartMinute) },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.windowStartMinute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                engine.refreshScheduling()
            }
        )
    }

    private var endDate: Binding<Date> {
        Binding(
            get: { settings.dateToday(atMinute: settings.windowEndMinute) },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.windowEndMinute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                engine.refreshScheduling()
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("开始时间", selection: startDate, displayedComponents: .hourAndMinute)
                    DatePicker("结束时间", selection: endDate, displayedComponents: .hourAndMinute)
                } header: {
                    Text("提醒时间窗")
                } footer: {
                    Text("只有在这个时间段内离开 A 区域才会提醒。默认 17:30 – 19:00。")
                }

                Section {
                    Picker("重复提醒间隔", selection: $settings.repeatMinutes) {
                        Text("不重复").tag(0)
                        Text("每 3 分钟").tag(3)
                        Text("每 5 分钟").tag(5)
                        Text("每 10 分钟").tag(10)
                        Text("每 15 分钟").tag(15)
                    }
                    Toggle("窗口结束前 10 分钟兜底提醒", isOn: $settings.tailReminderEnabled)
                } header: {
                    Text("提醒节奏")
                } footer: {
                    Text("开启重复后，离开 A 区域且未打卡时会按间隔继续提醒，直到打卡或时间窗结束。")
                }

                Section {
                    Toggle("铃声", isOn: $settings.soundEnabled)
                    Toggle("震动", isOn: $settings.vibrateEnabled)
                    Button { engine.testReminder() } label: {
                        Label("试听一次", systemImage: "speaker.wave.2")
                    }
                } header: {
                    Text("提醒方式")
                } footer: {
                    Text("手机处于静音模式（侧边拨杆）时本地通知不会响铃，但仍会震动。")
                }

                Section {
                    ForEach(sounds.builtIn) { item in
                        soundRow(item)
                    }
                } header: {
                    Text("内置铃声")
                }

                Section {
                    if sounds.custom.isEmpty {
                        Text("还没有导入。点下面的按钮，从「文件」App 里选一首你自己的音频。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sounds.custom) { item in
                            HStack {
                                soundRow(item)
                                Button {
                                    sounds.delete(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button { showImporter = true } label: {
                        Label("从「文件」导入音频", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("我的铃声")
                } footer: {
                    Text("支持 mp3 / m4a / wav 等常见格式，会自动转成单声道 16bit wav 并裁剪到前 30 秒，存进 App 自己的沙盒，不会改动你手机里的原文件。Apple Music 的歌受 DRM 保护，无法直接作为通知铃声。")
                }

                Section {
                    Button { location.requestAlwaysPermission() } label: {
                        Label("重新申请「始终」定位权限", systemImage: "location")
                    }
                    Button { location.openSystemSettings() } label: {
                        Label("打开系统设置", systemImage: "gear")
                    }
                    Text("当前权限：\(permissionText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("权限")
                }

                Section {
                    Button("重置今日状态（调试用）") {
                        settings.resetTodayForDebug()
                    }
                    .foregroundStyle(.red)
                } footer: {
                    Text("会清空「今日已到访 / 已打卡」，用于反复测试触发逻辑。")
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.audio],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .alert("导入结果",
                   isPresented: Binding(get: { importMessage != nil },
                                        set: { if !$0 { importMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    // MARK: - 铃声行

    private func soundRow(_ item: SoundStore.SoundItem) -> some View {
        Button {
            sounds.select(item)
        } label: {
            HStack {
                Text(item.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if sounds.selectedId == item.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 导入

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importMessage = error.localizedDescription

        case .success(let urls):
            guard let url = urls.first else { return }
            // 安全作用域内先把文件拷出来，作用域结束后原 URL 就不可访问了
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
            do {
                try FileManager.default.copyItem(at: url, to: tmp)
            } catch {
                importMessage = "读不到这个文件，请从「文件」App 里重新选择"
                return
            }
            let name = url.deletingPathExtension().lastPathComponent
            sounds.installAudioFile(at: tmp, displayName: name) { outcome in
                try? FileManager.default.removeItem(at: tmp)
                switch outcome {
                case .success(let item):
                    importMessage = "「\(item.displayName)」已导入并设为当前铃声"
                case .failure(let error):
                    importMessage = error.localizedDescription
                }
            }
        }
    }

    private var permissionText: String {
        switch location.authorizationStatus {
        case .authorizedAlways: return "始终 ✅"
        case .authorizedWhenInUse: return "仅使用期间 ⚠️"
        case .denied: return "已拒绝 ❌"
        case .restricted: return "受限制"
        case .notDetermined: return "未选择"
        @unknown default: return "未知"
        }
    }
}
