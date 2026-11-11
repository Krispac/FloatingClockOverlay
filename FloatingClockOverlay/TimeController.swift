import Foundation
import Combine
import UserNotifications
import AppKit

enum TimerRunState   { case idle, running, paused, finished, breakRunning, breakPaused }
enum StopwatchRunState { case idle, running, paused }

// Single source of truth for timer and stopwatch state.
// Accuracy: uses Date arithmetic, not tick-counting.
final class TimeController: ObservableObject {
    static let shared = TimeController()

    // MARK: - Timer
    @Published private(set) var timerState:     TimerRunState = .idle
    @Published private(set) var timerRemaining: TimeInterval  = 0
    // How long ago the countdown hit zero, so the user sees how late the break is.
    @Published private(set) var timerOvertime:  TimeInterval  = 0

    private var timerEndDate:           Date?
    private var timerFinishedAt:        Date?
    private var timerPausedRemaining:   TimeInterval = 0
    private var breakEndDate:           Date?
    private var breakPausedRemaining:   TimeInterval = 0

    // MARK: - Stopwatch
    @Published private(set) var stopwatchState:   StopwatchRunState = .idle
    @Published private(set) var stopwatchElapsed: TimeInterval      = 0
    @Published private(set) var laps:             [TimeInterval]    = []

    // startDate is adjusted so Date().timeIntervalSince(startDate) == total elapsed
    private var stopwatchStartDate: Date?

    // MARK: - Tick
    private var tickSink: AnyCancellable?
    private var soundSettingSink: AnyCancellable?

    private init() {
        let d = settingsDuration
        timerRemaining       = d
        timerPausedRemaining = d

        tickSink = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }

        soundSettingSink = ClockSettings.shared.$timerSoundEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { enabled in
                if !enabled { GentleGong.shared.stop() }
            }

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
                timerFinishedAt      = Date()
                timerOvertime        = 0
                timerState           = .finished
                sendTimerNotification()
                if ClockSettings.shared.timerSoundEnabled {
                    GentleGong.shared.play()
                }
            } else {
                timerRemaining = rem
            }
        } else if timerState == .breakRunning, let end = breakEndDate {
            let rem = end.timeIntervalSinceNow
            if rem <= 0 {
                finishBreak()
            } else {
                timerRemaining = rem
            }
        } else if timerState == .finished, let finished = timerFinishedAt {
            timerOvertime = Date().timeIntervalSince(finished)
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
        timerFinishedAt      = nil
        timerOvertime        = 0
        breakEndDate         = nil
        breakPausedRemaining = 0
        let d                = settingsDuration
        timerPausedRemaining = d
        timerRemaining       = d
        timerState           = .idle
        GentleGong.shared.stop()
    }

    // Called when the user edits the H/M/S fields (only takes effect when idle/finished).
    func updateTimerDuration() {
        guard timerState == .idle || timerState == .finished else { return }
        let wasFinished      = timerState == .finished
        let d                = settingsDuration
        timerPausedRemaining = d
        timerRemaining       = d
        timerFinishedAt      = nil
        timerOvertime        = 0
        if wasFinished {
            timerState = .idle
            GentleGong.shared.stop()
        }
    }

    private var settingsDuration: TimeInterval {
        let s = ClockSettings.shared
        return TimeInterval(s.timerHours * 3600 + s.timerMinutes * 60 + s.timerSeconds)
    }

    // MARK: - Break Controls

    var isOnBreak: Bool {
        timerState == .breakRunning || timerState == .breakPaused
    }

    var breakDuration: TimeInterval {
        TimeInterval(ClockSettings.shared.breakMinutes * 60)
    }

    // Started only by an explicit click on a finished timer. The finished
    // state is intentionally sticky so the user can finish what they were
    // doing before the break begins.
    func breakStart() {
        guard timerState == .finished else { return }
        let duration = breakDuration
        guard duration > 0 else {
            timerReset()
            return
        }
        GentleGong.shared.stop()
        timerFinishedAt      = nil
        timerOvertime        = 0
        breakPausedRemaining = duration
        timerRemaining       = duration
        breakEndDate         = Date().addingTimeInterval(duration)
        timerState           = .breakRunning
    }

    func breakPause() {
        guard timerState == .breakRunning, let end = breakEndDate else { return }
        breakPausedRemaining = max(0, end.timeIntervalSinceNow)
        breakEndDate         = nil
        timerRemaining       = breakPausedRemaining
        timerState           = .breakPaused
    }

    func breakResume() {
        guard timerState == .breakPaused else { return }
        guard breakPausedRemaining > 0 else {
            timerReset()
            return
        }
        breakEndDate = Date().addingTimeInterval(breakPausedRemaining)
        timerState   = .breakRunning
    }

    private func finishBreak() {
        breakEndDate         = nil
        breakPausedRemaining = 0
        let d                = settingsDuration
        timerPausedRemaining = d
        timerRemaining       = d
        timerState           = .idle
        // No gong by default: the problem is missed breaks, not long ones.
        if ClockSettings.shared.breakEndSoundEnabled {
            GentleGong.shared.play()
        }
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
        // The app plays its own gentle low gong. Keeping the system
        // notification silent avoids a second, harsher alert.
        content.sound     = nil
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - Gentle meditation gong

// Two low, warm yoga-room gong strikes (A2) separated by ten seconds. Each
// strike is built from a soft fundamental, a slowly beating twin and a few
// quietly decaying partials. The sound is synthesised once in memory, so the
// app carries no audio asset and nothing depends on the system alert sounds.
final class GentleGong {
    static let shared = GentleGong()

    private var sound: NSSound?
    private var secondStrike: DispatchWorkItem?
    private lazy var audioData = Self.makeWAVData()

    private init() {}

    func play() {
        stop()
        playStrike()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.secondStrike = nil
            self.playStrike()
        }
        secondStrike = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    private func playStrike() {
        sound?.stop()
        guard let sound = NSSound(data: audioData) else { return }
        sound.volume = 0.48
        sound.play()
        self.sound = sound
    }

    func stop() {
        secondStrike?.cancel()
        secondStrike = nil
        sound?.stop()
        sound = nil
    }

    // MARK: Synthesis

    private struct Strike {
        let frequency: Double
        let duration: Double

        // ratio, relative level, decay rate. The near-unison pair gives a slow,
        // gentle beat; the inharmonic upper partials add the gong shimmer.
        private static let partials: [(ratio: Double, amplitude: Double, decay: Double)] = [
            (1.000, 0.95, 0.42),
            (1.004, 0.28, 0.44),
            (2.000, 0.28, 0.60),
            (2.760, 0.12, 0.80),
            (4.070, 0.06, 1.05),
            (5.430, 0.03, 1.30),
        ]

        func sample(at time: Double) -> Double {
            guard time >= 0, time < duration else { return 0 }

            let attack  = 0.12
            let release = 0.90
            let fadeIn  = smoothstep(time / attack)
            let fadeOut = smoothstep((duration - time) / release)

            var body = 0.0
            for partial in Self.partials {
                let envelope = exp(-partial.decay * time)
                body += partial.amplitude * envelope
                    * sin(2 * .pi * frequency * partial.ratio * time)
            }
            return 0.16 * fadeIn * fadeOut * body
        }

        private func smoothstep(_ value: Double) -> Double {
            let t = min(max(value, 0), 1)
            return t * t * (3 - 2 * t)
        }
    }

    private static func makeWAVData() -> Data {
        let sampleRate = 44_100
        let strike = Strike(frequency: 110.00, duration: 6.0) // A2
        let totalDuration = strike.duration
        let frameCount = Int(totalDuration * Double(sampleRate))

        var samples = [Int16]()
        samples.reserveCapacity(frameCount)
        for frame in 0..<frameCount {
            let time = Double(frame) / Double(sampleRate)
            var value = strike.sample(at: time)
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
