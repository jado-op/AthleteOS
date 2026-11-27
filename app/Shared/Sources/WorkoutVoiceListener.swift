#if os(iOS) && !APP_EXTENSION
import AVFoundation
import Speech
import SwiftUI

/// Listens during a workout (owner, 2026-11-27: "talk to it mid workout").
/// Speech is recognised on the phone only (`requiresOnDeviceRecognition`):
/// nothing the athlete says leaves the device, and a language the phone
/// can't recognise offline is simply not offered. Music keeps playing.
/// Each stretch of speech waits a moment before it counts, so "done… with
/// this one, skip it" isn't read as "done".
@MainActor
final class WorkoutVoiceListener: ObservableObject {
    enum Status: Equatable {
        case off, listening
        case unavailable(String)
    }

    @Published private(set) var status: Status = .off
    var onCommand: ((WorkoutVoiceCommand) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    /// Characters of the current transcript already used for a command.
    private var usedUpTo = 0
    private var latest = ""
    private var settle: Task<Void, Never>?
    private var restarts = 0
    /// Each recognition run's number: a cancelled run's last callback is ignored.
    private var generation = 0

    var isListening: Bool { status == .listening }

    func toggle() {
        if isListening { stop() } else { Task { await start() } }
    }

    func start() async {
        let speechAllowed = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard speechAllowed, micAllowed else {
            status = .unavailable("Allow the microphone and speech recognition for AthleteOS in Settings to talk to it.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.supportsOnDeviceRecognition else {
            status = .unavailable("Talking needs speech recognition that works on your phone, without the internet. Your language isn't there yet.")
            return
        }
        self.recognizer = recognizer
        restarts = 0
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            try begin()
            status = .listening
        } catch {
            status = .unavailable("The microphone couldn't start.")
            end()
        }
    }

    func stop() {
        status = .off
        end()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func begin() throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        usedUpTo = 0
        latest = ""
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.feed(request))
        engine.prepare()
        try engine.start()
        generation += 1
        let run = generation
        task = recognizer?.recognitionTask(with: request, resultHandler: Self.results { [weak self] text, ended in
            Task { @MainActor in self?.heard(text, ended: ended, run: run) }
        })
    }

    private func end() {
        settle?.cancel()
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    /// The audio tap and the recognition callback run off the main thread:
    /// built outside the main actor so they never assume it.
    nonisolated private static func feed(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func results(_ report: @escaping @Sendable (String?, Bool) -> Void)
        -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            report(result?.bestTranscription.formattedString, error != nil || (result?.isFinal ?? false))
        }
    }

    private func heard(_ text: String?, ended: Bool, run: Int) {
        guard isListening, run == generation else { return }
        if let text { latest = text }
        settle?.cancel()
        if ended {
            // Recognition stops after a minute or a long silence: read the
            // last words, then start a new one.
            read()
            restarts += 1
            guard restarts < 60 else { stop(); return }
            end()
            do { try begin() } catch { status = .unavailable("The microphone stopped."); end() }
            return
        }
        // A short pause after the last word: then read what's new.
        settle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.read()
        }
    }

    private func read() {
        guard latest.count > usedUpTo else { return }
        let fresh = String(latest.dropFirst(usedUpTo))
        guard let command = WorkoutVoiceCommand.parse(fresh) else { return }
        usedUpTo = latest.count
        onCommand?(command)
    }
}
#endif
