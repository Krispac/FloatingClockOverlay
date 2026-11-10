import Foundation
import Combine
import UserNotifications
import AppKit

enum TimerRunState   { case idle, running, paused, finished }
enum StopwatchRunState { case idle, running, paused }

// Single source of truth for timer and stopwatch state.
// Accuracy: uses Date arithmetic, not tick-counting.
final class TimeController: ObservableObject {
    static let shared = TimeController()

    // MARK: - Timer
    @Published private(set) var timerState:     TimerRunState = .idle
    @Published private(set) var timerRemaining: TimeInterval  = 0

    private var timerEndDate:           Date?
    private var timerPausedRemaining:   TimeInterval = 0

    // MARK: - Stopwatch
    @Published private(set) var stopwatchState:   StopwatchRunState = .idle
    @Published private(set) var stopwatchElapsed: TimeInterval      = 0
    @Published private(set) var laps:             [TimeInterval]    = []

    // startDate is adjusted so Date().timeIntervalSince(startDate) == total elapsed
    private var stopwatchStartDate: Date?

    // MARK: - Tick
    private var tickSink: AnyCancellable?

    private init() {
        let d = settingsDuration
        timerRemaining       = d
        timerPausedRemaining = d

        tickSink = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }

        requestNotificationPermission()
    }

    private func tick() {
        // Timer
        if timerState == .running, let end = timerEndDate {
            let rem = end.timeIntervalSinceNow
            if rem <= 0 {
                timerRemaining       = 0
                timerPausedRemaining = 0
                timerEndDate         = nil
                timerState           = .finished
                sendTimerNotification()
                GentleChime.shared.play()
            } else {
                timerRemaining = rem
            }
        }
        // Stopwatch
        if stopwatchState == .running, let start = stopwatchStartDate {
            stopwatchElapsed = Date().timeIntervalSince(start)
        }
    }

    // MARK: - Timer Controls

    func timerStart() {
        guard timerState == .idle || timerState == .paused else { return }
        if timerState == .idle {
            // Read the fields at the moment of starting, not a value cached
            // before the last edit was committed by the text field.
            timerPausedRemaining = settingsDuration
            timerRemaining       = timerPausedRemaining
        }
        guard timerPausedRemaining > 0 else { return }
        timerEndDate = Date().addingTimeInterval(timerPausedRemaining)
        timerState   = .running
    }

    func timerPause() {
        guard timerState == .running, let end = timerEndDate else { return }
        timerPausedRemaining = max(0, end.timeIntervalSinceNow)
        timerEndDate         = nil
        timerState           = .paused
    }

    func timerReset() {
        timerEndDate         = nil
        let d                = settingsDuration
        timerPausedRemaining = d
        timerRemaining       = d
        timerState           = .idle
        GentleChime.shared.stop()
    }

    // Called when the user edits the H/M/S fields (only takes effect when idle/finished).
    func updateTimerDuration() {
        guard timerState == .idle || timerState == .finished else { return }
        let wasFinished      = timerState == .finished
        let d                = settingsDuration
        timerPausedRemaining = d
        timerRemaining       = d
        if wasFinished {
            timerState = .idle
            GentleChime.shared.stop()
        }
    }

    private var settingsDuration: TimeInterval {
        let s = ClockSettings.shared
        return TimeInterval(s.timerHours * 3600 + s.timerMinutes * 60 + s.timerSeconds)
    }

    // MARK: - Stopwatch Controls

    func stopwatchStart() {
        guard stopwatchState != .running else { return }
        // Shift the start date so that elapsed = Date() - startDate at any future moment
        stopwatchStartDate = Date().addingTimeInterval(-stopwatchElapsed)
        stopwatchState     = .running
    }

    func stopwatchPause() {
        guard stopwatchState == .running, let start = stopwatchStartDate else { return }
        stopwatchElapsed   = Date().timeIntervalSince(start)
        stopwatchStartDate = nil
        stopwatchState     = .paused
    }

    func stopwatchReset() {
        stopwatchStartDate = nil
        stopwatchElapsed   = 0
        laps               = []
        stopwatchState     = .idle
    }

    // Records elapsed time of the current lap split.
    func stopwatchLap() {
        guard stopwatchState == .running else { return }
        // Store cumulative; UI computes per-lap splits.
        laps.append(stopwatchElapsed)
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendTimerNotification() {
        let content       = UNMutableNotificationContent()
        content.title     = "Timer Finished"
        content.body      = "Your countdown timer has reached zero."
        // The app plays its own gentle two-note chime. Keeping the system
        // notification silent avoids a second, harsher alert.
        content.sound     = nil
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - Gentle completion chime

// Two slow, soft tones (E5 then C5) with a long attack and release. The sound
// is synthesised once in memory so the app carries no audio asset and nothing
// about the chime depends on the system alert sounds.
final class GentleChime {
    static let shared = GentleChime()

    private var sound: NSSound?
    private lazy var audioData = Self.makeWAVData()

    private init() {}

    func play() {
        stop()
        guard let sound = NSSound(data: audioData) else { return }
        sound.volume = 0.42
        sound.play()
        self.sound = sound
    }

    func stop() {
        sound?.stop()
        sound = nil
    }

    // MARK: Synthesis

    private struct Tone {
        let frequency: Double
        let duration: Double

        func sample(at time: Double) -> Double {
            guard time >= 0, time < duration else { return 0 }

            let attack  = 0.35
            let release = 1.40
            let fadeIn  = smoothstep(time / attack)
            let fadeOut = smoothstep((duration - time) / release)
            let decay   = exp(-1.1 * max(0, time - attack) / max(0.001, duration - attack))

            let fundamental = sin(2 * .pi * frequency * time)
            let harmonic    = 0.12 * sin(2 * .pi * frequency * 2 * time)
            return 0.24 * fadeIn * fadeOut * decay * (fundamental + harmonic)
        }

        private func smoothstep(_ value: Double) -> Double {
            let t = min(max(value, 0), 1)
            return t * t * (3 - 2 * t)
        }
    }

    private static func makeWAVData() -> Data {
        let sampleRate = 44_100
        let first  = Tone(frequency: 659.25, duration: 2.2) // E5
        let second = Tone(frequency: 523.25, duration: 2.4) // C5
        let gap = 0.8
        let totalDuration = first.duration + gap + second.duration
        let frameCount = Int(totalDuration * Double(sampleRate))

        var samples = [Int16]()
        samples.reserveCapacity(frameCount)
        for frame in 0..<frameCount {
            let time = Double(frame) / Double(sampleRate)
            var value = 0.0
            if time < first.duration {
                value = first.sample(at: time)
            } else if time >= first.duration + gap {
                value = second.sample(at: time - first.duration - gap)
            }
            value = min(max(value, -1), 1)
            samples.append(Int16(value * 32_767))
        }

        var data = Data()
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample

        func appendASCII(_ value: String) {
            data.append(value.data(using: .ascii)!)
        }
        func appendUInt16(_ value: UInt16) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        func appendUInt32(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(1) // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * bytesPerSample))
        appendUInt16(UInt16(bytesPerSample))
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(UInt32(dataSize))
        for sample in samples {
            var littleEndian = sample.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}

// MARK: - TimeInterval Display

extension TimeInterval {
    // HH:MM:SS (integer seconds)
    var hmsString: String {
        let t = Int(max(0, self))
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    // MM:SS (for laps < 1 hour)
    var mmssString: String {
        let t = Int(max(0, self))
        return t < 3600
            ? String(format: "%02d:%02d", t / 60, t % 60)
            : hmsString
    }
}
