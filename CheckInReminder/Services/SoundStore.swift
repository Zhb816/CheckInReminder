//
//  SoundStore.swift
//  铃声管理：内置多款铃声 + 从「文件」App 导入自己的音频
//
//  说明：iOS 的通知铃声只能是 App 包内或 App 容器 Library/Sounds 目录下的
//  wav / caf / aiff 文件，且不超过 30 秒。Apple Music 的歌曲受 DRM 保护，
//  系统不允许第三方 App 直接拿来当铃声，所以这里走「文件 App 导入 + 转码裁剪」。
//

import Foundation
import AVFoundation
import CoreAudioTypes

final class SoundStore: ObservableObject {

    static let shared = SoundStore()

    struct SoundItem: Identifiable, Codable, Equatable {
        var id: String            // 文件名（含扩展名）
        var displayName: String
        var isBuiltIn: Bool
    }

    enum ImportError: LocalizedError {
        case noAudioTrack
        case exportFailed
        case unreadable

        var errorDescription: String? {
            switch self {
            case .noAudioTrack:   return "这个文件里没有找到音频轨道"
            case .exportFailed:   return "转码失败，换个更常见的音频文件试试（mp3 / m4a / wav）"
            case .unreadable:     return "读不到这个文件，请从「文件」App 里重新选择"
            }
        }
    }

    private let ud = UserDefaults.standard
    private let settings = AppSettings.shared
    private let customKey = "sounds.custom"

    /// 内置铃声（文件放在 Resources 目录，随 App 打包）
    private(set) var builtIn: [SoundItem] = [
        .init(id: "reminder.wav", displayName: "清脆三连音", isBuiltIn: true),
        .init(id: "chime.wav",    displayName: "柔和钟琴",   isBuiltIn: true),
        .init(id: "radar.wav",    displayName: "雷达滴答",   isBuiltIn: true),
        .init(id: "bell.wav",     displayName: "门铃叮咚",   isBuiltIn: true)
    ]

    /// 用户导入的铃声
    @Published private(set) var custom: [SoundItem] = []

    private var player: AVAudioPlayer?

    init() { load() }

    // MARK: - 存储目录

    /// 自定义铃声存放位置：App 容器 Library/Sounds（系统通知会来这里找）
    var soundsDirectory: URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let dir = lib.appendingPathComponent("Sounds", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var all: [SoundItem] { builtIn + custom }

    var selectedId: String { settings.selectedSound }

    // MARK: - 选择

    func select(_ item: SoundItem) {
        settings.selectedSound = item.id
        objectWillChange.send()
        preview(item)
    }

    func url(for item: SoundItem) -> URL? {
        if item.isBuiltIn {
            let name = (item.id as NSString).deletingPathExtension
            let ext = (item.id as NSString).pathExtension
            return Bundle.main.url(forResource: name, withExtension: ext)
        }
        let u = soundsDirectory.appendingPathComponent(item.id)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// 通知用文件名（系统先在包内找，再到 Library/Sounds 找）
    var notificationSoundName: String { settings.selectedSound }

    // MARK: - 试听

    func preview(_ item: SoundItem) {
        guard let url = url(for: item) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.player?.stop()
            self?.player = try? AVAudioPlayer(contentsOf: url)
            self?.player?.prepareToPlay()
            self?.player?.play()
        }
    }

    // MARK: - 导入

    /// 导入任意音频文件：转成 16bit / 44.1kHz / 单声道 的 wav，并裁剪到 30 秒内
    func installAudioFile(at source: URL,
                          displayName: String,
                          completion: @escaping (Result<SoundItem, Error>) -> Void) {
        let destURL = soundsDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        let limit: Double = 30

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fail: (Error) -> Void = { error in
                DispatchQueue.main.async { completion(.failure(error)) }
            }

            let asset = AVURLAsset(url: source)
            guard let track = asset.tracks(withMediaType: .audio).first else {
                fail(ImportError.noAudioTrack); return
            }
            let duration = CMTimeGetSeconds(asset.duration)
            guard duration > 0.1 else { fail(ImportError.unreadable); return }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleavedKey: false
            ]

            guard let reader = try? AVAssetReader(asset: asset) else { fail(ImportError.unreadable); return }
            let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            reader.timeRange = CMTimeRange(start: .zero,
                                           end: CMTime(seconds: min(duration, limit), preferredTimescale: 600))
            reader.add(readerOutput)

            if FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.removeItem(at: destURL)
            }
            guard let writer = try? AVAssetWriter(outputURL: destURL, fileType: .wav) else {
                fail(ImportError.exportFailed); return
            }
            let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
            writerInput.expectsMediaDataInRealTime = false
            writer.add(writerInput)

            guard reader.startReading() else { fail(ImportError.unreadable); return }
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)

            while writerInput.isReadyForMoreMediaData {
                if let sample = readerOutput.copyNextSampleBuffer() {
                    writerInput.append(sample)
                } else {
                    writerInput.markAsFinished()
                    writer.finishWriting { [weak self] in
                        guard let self = self else { return }
                        guard writer.status == .completed,
                              FileManager.default.fileExists(atPath: destURL.path) else {
                            DispatchQueue.main.async { completion(.failure(ImportError.exportFailed)) }
                            return
                        }
                        let item = SoundItem(id: destURL.lastPathComponent,
                                             displayName: displayName,
                                             isBuiltIn: false)
                        DispatchQueue.main.async {
                            self.custom.append(item)
                            self.save()
                            self.settings.selectedSound = item.id
                            completion(.success(item))
                        }
                    }
                    return
                }
            }
            fail(ImportError.exportFailed)
        }
    }

    // MARK: - 删除

    func delete(_ item: SoundItem) {
        if let url = url(for: item) { try? FileManager.default.removeItem(at: url) }
        custom.removeAll { $0.id == item.id }
        if settings.selectedSound == item.id { settings.selectedSound = "reminder.wav" }
        save()
        objectWillChange.send()
    }

    // MARK: - 持久化

    private func save() {
        if let data = try? JSONEncoder().encode(custom) {
            ud.set(data, forKey: customKey)
        }
    }

    private func load() {
        guard let data = ud.data(forKey: customKey),
              let items = try? JSONDecoder().decode([SoundItem].self, from: data) else { return }
        // 文件被清掉的记录直接丢弃
        custom = items.filter { item in
            FileManager.default.fileExists(atPath: soundsDirectory.appendingPathComponent(item.id).path)
        }
    }
}
