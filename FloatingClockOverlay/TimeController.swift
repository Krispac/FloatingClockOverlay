import Foundation
import Combine
import UserNotifications

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
    }

    // Called when the user edits the H/M/S fields (only takes effect when idle/finished).
    func updateTimerDuration() {
        guard timerState == .idle || timerState == .finished else { return }
        let d                = settingsDuration
        timerPausedRemaining = d
        timerRemaining       = d
        if timerState == .finished { timerState = .idle }
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
        content.sound     = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
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
