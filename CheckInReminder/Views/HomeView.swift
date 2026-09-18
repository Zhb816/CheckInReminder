//
//  HomeView.swift
//  主界面：状态 + 地图选点 + 半径 + 快捷操作
//

import SwiftUI
import CoreLocation

struct HomeView: View {

    @StateObject private var settings = AppSettings.shared
    @StateObject private var location = LocationManager.shared
    @StateObject private var engine   = ReminderEngine.shared
    @StateObject private var search   = LocationSearchViewModel()

    @State private var recenter = 0
    @State private var searchFailed = false
    @State private var showSettings = false
    @State private var showPermissionTip = false

    private var centerBinding: Binding<CLLocationCoordinate2D?> {
        Binding(
            get: { settings.zoneCenter },
            set: { newValue in
                if let c = newValue {
                    settings.setZone(c)
                    location.rebuildRegion()
                    location.reevaluate()
                } else {
                    settings.clearZone()
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                mapSection
                zoneSection
                taskSection
                actionSection
                logSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("打卡提醒")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onAppear {
                engine.bind()
                if location.authorizationStatus == .notDetermined {
                    location.requestAlwaysPermission()
                }
                location.start()
                // 有定位就把搜索范围收到身边，搜到的地址更准
                if let loc = location.currentLocation {
                    search.focusOnCurrentLocation(loc.coordinate)
                }
            }
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: settings.visitedToday ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(settings.visitedToday ? .green : .secondary)
                    Text("今日是否到过 A 区域：\(settings.visitedToday ? "已到访" : "未到访")")
                        .font(.subheadline)
                }
                HStack {
                    Image(systemName: settings.checkedInToday ? "checkmark.seal.fill" : "seal")
                        .foregroundStyle(settings.checkedInToday ? .blue : .secondary)
                    Text("今日打卡状态：\(settings.checkedInToday ? "已打卡" : "未打卡")")
                        .font(.subheadline)
                }
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(settings.isInTimeWindow() ? .orange : .secondary)
                    Text("提醒时间窗：\(settings.windowText)（当前\(settings.isInTimeWindow() ? "窗口内" : "窗口外")）")
                        .font(.subheadline)
                }
                if let d = location.distanceToZone {
                    HStack {
                        Image(systemName: "location")
                            .foregroundStyle(location.isInsideZone ? .green : .red)
                        Text("距 A 中心：\(Int(d)) 米（\(location.isInsideZone ? "区域内" : "区域外")）")
                            .font(.subheadline)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("今日状态")
        } footer: {
            Text("规则：当天进入过 A 区域 → 在 \(settings.windowText) 之间离开 A 区域 \(Int(settings.radius)) 米以上 → 铃声 + 震动提醒打卡。当天没去过 A 区域则完全不提醒。")
        }
    }

    // MARK: - 地图

    private var mapSection: some View {
        Section {
            searchBar

            if !search.results.isEmpty {
                searchResults
            }

            ZStack(alignment: .topTrailing) {
                ZoneMapView(center: centerBinding,
                            radius: settings.radius,
                            recenterTrigger: recenter,
                            onLongPress: { coordinate in
                                settings.setZone(coordinate)
                                location.rebuildRegion()
                                location.reevaluate()
                            })
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    recenter += 1
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(8)
            }
        } header: {
            Text("A 区域（搜索地址 / 长按地图选点）")
        } footer: {
            Text(settings.zoneCenter == nil
                 ? "还没有设置 A 区域，搜索地址或长按地图任意位置即可设定。"
                 : "\(settings.zoneName)　\(settings.coordinateText)")
        }
        .alert("没搜到这个地点", isPresented: $searchFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("换个更完整的名字试试，比如加上城市或区名。")
        }
    }

    // MARK: - 地址搜索

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索地点，如「科技园地铁站」", text: $search.query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit { searchByText() }
            if !search.query.isEmpty {
                Button { search.clear() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    private var searchResults: some View {
        VStack(spacing: 0) {
            ForEach(search.results) { result in
                Button { pick(result) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if result.id != search.results.last?.id { Divider() }
            }
        }
        .padding(.horizontal, 10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func pick(_ result: SearchResult) {
        search.resolve(result) { coordinate, name in
            guard let coordinate = coordinate else { searchFailed = true; return }
            applyZone(coordinate, name: name)
        }
    }

    private func searchByText() {
        guard !search.query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        search.search(text: search.query) { coordinate, name in
            guard let coordinate = coordinate else { searchFailed = true; return }
            applyZone(coordinate, name: name)
        }
    }

    /// 统一入口：写入坐标 → 重建围栏 → 清空搜索
    private func applyZone(_ coordinate: CLLocationCoordinate2D, name: String?) {
        settings.setZone(coordinate, name: name)
        location.rebuildRegion()
        location.reevaluate()
        search.clear()
    }

    // MARK: - 区域设置

    private var zoneSection: some View {
        Section {
            HStack {
                Text("离开半径")
                Spacer()
                Text("\(Int(settings.radius)) 米").foregroundStyle(.secondary)
            }
            Slider(value: $settings.radius, in: 10...200, step: 5)
                .onChange(of: settings.radius) { _ in
                    location.rebuildRegion()
                    location.reevaluate()
                }

            Button {
                if let loc = location.currentLocation {
                    applyZone(loc.coordinate, name: "当前位置")
                } else {
                    showPermissionTip = true
                }
            } label: {
                Label("用当前位置设为 A 区域", systemImage: "mappin.and.ellipse")
            }

            if settings.zoneCenter != nil {
                Button(role: .destructive) {
                    settings.clearZone()
                    location.rebuildRegion()
                } label: {
                    Label("清除 A 区域", systemImage: "trash")
                }
            }
        } header: {
            Text("区域设置")
        } footer: {
            Text("iOS 系统围栏对 30 米这种小半径会有一定延迟（GPS 误差通常 5–20 米），App 已额外用实时坐标做二次判定，实测出圈后几十秒内会响。")
        }
        .alert("还没拿到定位", isPresented: $showPermissionTip) {
            Button("去设置") { location.openSystemSettings() }
            Button("好", role: .cancel) {}
        } message: {
            Text("请允许「始终」定位权限后再试。")
        }
    }

    // MARK: - 任务开关

    private var taskSection: some View {
        Section {
            Toggle(isOn: $settings.enabled) {
                Label("启用打卡提醒", systemImage: "bell.badge")
            }
            .onChange(of: settings.enabled) { on in
                if on { location.start(); engine.refreshScheduling() }
            }

            if !location.hasAlwaysPermission {
                VStack(alignment: .leading, spacing: 8) {
                    Label("需要「始终」定位权限", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("只有 Always 权限才能在锁屏 / 切走 App 后继续监听进出 A 区域。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("去开启") {
                        if location.authorizationStatus == .notDetermined {
                            location.requestAlwaysPermission()
                        } else {
                            location.openSystemSettings()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("任务")
        }
    }

    // MARK: - 操作

    private var actionSection: some View {
        Section {
            Button { engine.testReminder() } label: {
                Label("测试提醒（铃声 + 震动）", systemImage: "waveform")
            }
            Button { engine.checkIn() } label: {
                Label("我已打卡（停止今日提醒）", systemImage: "checkmark")
            }
            .disabled(settings.checkedInToday)
        } header: {
            Text("操作")
        }
    }

    // MARK: - 日志

    private var logSection: some View {
        Section {
            if engine.logs.isEmpty {
                Text("暂无记录。设置好 A 区域后，进出区域、触发/跳过提醒都会写在这里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(engine.logs, id: \.self) { line in
                    Text(line).font(.caption.monospacedDigit())
                }
            }
        } header: {
            Text("运行日志")
        }
    }
}
