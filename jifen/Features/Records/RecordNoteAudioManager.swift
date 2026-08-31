//
//  RecordNoteAudioManager.swift
//  jifen
//
//  语音笔记录音/播放单例，1:1 对齐安卓 RecordNoteAudioManager：
//  AAC/m4a、最长 60 秒自动停止、不足 2 秒丢弃、振幅电平表、播放进度回调。
//

import AVFoundation
import Foundation

typealias RecordNoteRecordingFailureReason = String

struct RecordNoteRecordingResult {
    let success: Bool
    let relativePath: String?
    let durationMs: Int
    let reason: RecordNoteRecordingFailureReason?

    static func success(path: String, durationMs: Int) -> RecordNoteRecordingResult {
        RecordNoteRecordingResult(success: true, relativePath: path, durationMs: durationMs, reason: nil)
    }

    static func failure(_ reason: RecordNoteRecordingFailureReason) -> RecordNoteRecordingResult {
        RecordNoteRecordingResult(success: false, relativePath: nil, durationMs: 0, reason: reason)
    }
}

typealias RecordNotePlaybackFailureReason = String // missing_file | playback_error
typealias RecordNotePlaybackChanged = (_ isPlaying: Bool, _ failure: RecordNotePlaybackFailureReason?) -> Void
typealias RecordNoteRecordingFinished = (RecordNoteRecordingResult) -> Void

final class RecordNoteAudioManager: NSObject {
    static let shared = RecordNoteAudioManager()

    private var recorder: AVAudioRecorder?
    private var activeTempPath: String?
    private var activeRecordId: String?
    private var recordingStartedAt: Date?
    private var recordingFinished: RecordNoteRecordingFinished?
    private var finishingRecording = false

    private var player: AVAudioPlayer?
    private var playbackChanged: RecordNotePlaybackChanged?
    private var playbackPath: String?

    private let session = AVAudioSession.sharedInstance()

    private var isRecordingActive: Bool { recorder?.isRecording == true }
    var isRecording: Bool { isRecordingActive || finishingRecording }

    // ---- 录音 ----

    /// 开始录音；返回 false 表示已在录音或文件创建失败（原因经 completion 回调）。
    @discardableResult
    func startRecording(recordId: String, onFinished: @escaping RecordNoteRecordingFinished) -> Bool {
        if isRecordingActive || finishingRecording { return false }
        let tempPath: String
        do {
            tempPath = try ScoreboardRecordManager.createVoiceNoteTempFile(recordId: recordId)
        } catch {
            onFinished(.failure("file_create_failed"))
            return false
        }
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let url = ScoreboardRecordManager.voiceNoteFileURL(tempPath)
            let recorder = try AVAudioRecorder(
                url: url,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
            )
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            self.recorder = recorder
            activeTempPath = tempPath
            activeRecordId = recordId
            recordingStartedAt = Date()
            recordingFinished = onFinished
            guard recorder.record(forDuration: Double(ScoreboardRecordVoiceNoteLimits.maximumDurationMs) / 1_000) else {
                failActiveRecording("record_unavailable")
                return false
            }
            return true
        } catch {
            ScoreboardRecordManager.deleteVoiceNoteFile(tempPath)
            cleanupRecordingState()
            onFinished(.failure("record_unavailable"))
            return false
        }
    }

    /// 用户取消：先摘除回调所有权再 stop，阻断 delegate 重入；删除临时文件并回调 cancelled。
    func cancelRecording() {
        guard let recorder, finishingRecording == false else { return }
        finishingRecording = true
        let path = activeTempPath
        let callback = recordingFinished
        recordingFinished = nil
        recorder.delegate = nil
        recorder.stop()
        recorder.deleteRecording()
        if let path {
            ScoreboardRecordManager.deleteVoiceNoteFile(path)
        }
        cleanupRecordingState()
        deliver(callback, .failure("cancelled"))
    }

    /// 用户停止：同步收尾（stop 会关闭文件），不再依赖 delegate 回调。
    func stopRecording() {
        guard let recorder, recorder.isRecording else { return }
        finishingRecording = true
        let durationMs = currentRecordingDurationMs()
        let path = activeTempPath
        let recordId = activeRecordId
        let callback = recordingFinished
        recordingFinished = nil
        recorder.delegate = nil
        recorder.stop()
        cleanupRecordingState()
        finishRecording(path: path, recordId: recordId, durationMs: durationMs, success: true, callback: callback)
    }

    func currentRecordingDurationMs() -> Int {
        guard let startedAt = recordingStartedAt else { return 0 }
        let elapsed = Int(Date().timeIntervalSince(startedAt) * 1_000)
        return min(max(elapsed, 0), ScoreboardRecordVoiceNoteLimits.maximumDurationMs)
    }

    /// 归一化振幅 0...1（averagePower 由 -60dB 映射）。
    func readCurrentRecordingAmplitude() -> Float {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let normalized = (power + 60) / 60
        return min(max(normalized, 0), 1)
    }

    private func failActiveRecording(_ reason: RecordNoteRecordingFailureReason) {
        let path = activeTempPath
        let callback = recordingFinished
        recordingFinished = nil
        recorder?.delegate = nil
        recorder?.stop()
        if let path {
            ScoreboardRecordManager.deleteVoiceNoteFile(path)
        }
        cleanupRecordingState()
        deliver(callback, .failure(reason))
    }

    private func cleanupRecordingState() {
        recorder = nil
        activeTempPath = nil
        activeRecordId = nil
        recordingStartedAt = nil
        finishingRecording = false
    }

    /// 统一收尾：校验时长并经 ScoreboardRecordManager 落盘（delegate 与手动停止共用）。
    private func finishRecording(
        path: String?,
        recordId: String?,
        durationMs: Int,
        success: Bool,
        callback: RecordNoteRecordingFinished?
    ) {
        guard let path, let recordId, let callback else { return }
        guard success else {
            ScoreboardRecordManager.deleteVoiceNoteFile(path)
            deliver(callback, .failure("file_failed"))
            return
        }
        guard ScoreboardRecordVoiceNoteLimits.isDurationValid(durationMs) else {
            ScoreboardRecordManager.deleteVoiceNoteFile(path)
            deliver(callback, .failure("too_short"))
            return
        }
        do {
            try ScoreboardRecordManager.shared.updateRecordVoiceNote(
                id: recordId,
                tempRelativePath: path,
                durationMs: durationMs
            )
            deliver(callback, .success(path: path, durationMs: durationMs))
        } catch RecordNoteError.recordMissing {
            ScoreboardRecordManager.deleteVoiceNoteFile(path)
            deliver(callback, .failure("record_unavailable"))
        } catch {
            ScoreboardRecordManager.deleteVoiceNoteFile(path)
            deliver(callback, .failure("save_failed"))
        }
    }

    private func deliver(_ callback: RecordNoteRecordingFinished?, _ result: RecordNoteRecordingResult) {
        guard let callback else { return }
        if Thread.isMainThread {
            callback(result)
        } else {
            DispatchQueue.main.async { callback(result) }
        }
    }
}

extension RecordNoteAudioManager: AVAudioRecorderDelegate {
    /// 只处理 record(forDuration:) 60s 到时的自动停止；用户停止/取消已摘除 delegate，不会进入此回调。
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard recordingFinished != nil, finishingRecording == false else { return }
        finishingRecording = true
        let durationMs = currentRecordingDurationMs()
        let path = activeTempPath
        let recordId = activeRecordId
        let callback = recordingFinished
        recordingFinished = nil
        recorder.delegate = nil
        recorder.stop()
        cleanupRecordingState()
        finishRecording(path: path, recordId: recordId, durationMs: durationMs, success: flag, callback: callback)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard recordingFinished != nil else { return }
        failActiveRecording("file_failed")
    }
}

// ---- 播放 ----

extension RecordNoteAudioManager: AVAudioPlayerDelegate {
    func togglePlayback(relativePath: String, onChanged: @escaping RecordNotePlaybackChanged) {
        if player?.isPlaying == true && playbackPath == relativePath {
            stopPlayback()
            return
        }
        stopPlayback()
        let url = ScoreboardRecordManager.voiceNoteFileURL(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            onChanged(false, "missing_file")
            return
        }
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            self.player = player
            playbackPath = relativePath
            playbackChanged = onChanged
            guard player.play() else {
                releasePlayer("playback_error")
                return
            }
            onChanged(true, nil)
        } catch {
            releasePlayer("playback_error")
        }
    }

    func stopPlayback() {
        guard player != nil else { return }
        player?.stop()
        releasePlayer(nil)
    }

    func currentPlaybackPositionMs() -> Int {
        Int((player?.currentTime ?? 0) * 1_000)
    }

    private func releasePlayer(_ failure: RecordNotePlaybackFailureReason?) {
        player = nil
        playbackPath = nil
        let callback = playbackChanged
        playbackChanged = nil
        if let callback {
            DispatchQueue.main.async { callback(false, failure) }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let callback = playbackChanged
        self.player = nil
        playbackPath = nil
        playbackChanged = nil
        if let callback {
            DispatchQueue.main.async { callback(false, nil) }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        releasePlayer("playback_error")
    }
}
