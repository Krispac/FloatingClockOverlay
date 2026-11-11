import SwiftUI

// Controls embedded inside the Mode card in SettingsView.
struct TimerStopwatchControlsView: View {
    @ObservedObject private var settings = ClockSettings.shared
    @ObservedObject private var tc       = TimeController.shared

    var body: some View {
        switch settings.overlayMode {
        case .timer:     timerSection
        case .stopwatch: stopwatchSection
        default:         EmptyView()
        }
    }

    // MARK: - Timer

    private var timerSection: some View {
        VStack(spacing: 14) {
            // Duration fields (only editable when idle / finished)
            if tc.timerState == .idle || tc.timerState == .finished {
                HStack(spacing: 0) {
                    Spacer()
                    DurationField(label: "Hours",   value: $settings.timerHours,   range: 0...23)
                    colonSeparator
                    DurationField(label: "Minutes", value: $settings.timerMinutes, range: 0...59)
                    colonSeparator
                    DurationField(label: "Seconds", value: $settings.timerSeconds, range: 0...59)
                    Spacer()
                }
                .onChange(of: settings.timerHours)   { _ in tc.updateTimerDuration() }
                .onChange(of: settings.timerMinutes) { _ in tc.updateTimerDuration() }
                .onChange(of: settings.timerSeconds) { _ in tc.updateTimerDuration() }

                HStack {
                    Spacer()
                    DurationField(label: "Break min", value: $settings.breakMinutes, range: 0...59)
                    Spacer()
                }
                Text("Break after the timer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                // Live remaining display
                if tc.isOnBreak {
                    Text("Break")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(tc.timerRemaining.hmsString)
                    .font(.system(size: 34, weight: .light, design: .monospaced))
                    .foregroundStyle(tc.timerState == .finished ? Color.red : Color.primary)
            }

            ToggleRow(icon: "speaker.wave.2",
                      label: "Completion Gong",
                      value: $settings.timerSoundEnabled,
                      hint: "Two low gong strikes, 10 seconds apart")

            ToggleRow(icon: "speaker.slash",
                      label: "Gong when the break ends",
                      value: $settings.breakEndSoundEnabled,
                      hint: "Off by default — the break ending is not the problem")

            // Buttons
            HStack(spacing: 8) {
                timerActionButton
                Button("Reset", action: tc.timerReset)
                    .buttonStyle(.bordered)
                    .disabled(tc.timerState == .idle)
            }

            if tc.timerState == .finished {
                Text("Timer finished — click the overlay or Start Break.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if tc.timerState == .breakRunning {
                Text("Break in progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if tc.timerState == .breakPaused {
                Text("Break paused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var timerActionButton: some View {
        switch tc.timerState {
        case .idle:
            Button("Start", action: tc.timerStart)
                .buttonStyle(.borderedProminent)
                .disabled(settingsDuration == 0)
        case .running:
            Button("Pause", action: tc.timerPause)
                .buttonStyle(.bordered)
        case .paused:
            Button("Resume", action: tc.timerStart)
                .buttonStyle(.borderedProminent)
        case .finished:
            Button("Start Break") { tc.breakStart() }
                .buttonStyle(.borderedProminent)
        case .breakRunning:
            Button("Pause Break", action: tc.breakPause)
                .buttonStyle(.bordered)
        case .breakPaused:
            Button("Resume Break", action: tc.breakResume)
                .buttonStyle(.borderedProminent)
        }
    }

    private var settingsDuration: TimeInterval {
        TimeInterval(settings.timerHours * 3600 + settings.timerMinutes * 60 + settings.timerSeconds)
    }

    // MARK: - Stopwatch

    private var stopwatchSection: some View {
        VStack(spacing: 14) {
            // Live elapsed display
            Text(tc.stopwatchElapsed.hmsString)
                .font(.system(size: 34, weight: .light, design: .monospaced))

            // Buttons
            HStack(spacing: 8) {
                stopwatchActionButton

                Button("Reset", action: tc.stopwatchReset)
                    .buttonStyle(.bordered)
                    .disabled(tc.stopwatchState == .idle && tc.stopwatchElapsed == 0)
            }

            // Lap list
            if !tc.laps.isEmpty {
                lapList
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stopwatchActionButton: some View {
        switch tc.stopwatchState {
        case .idle:
            Button("Start", action: tc.stopwatchStart)
                .buttonStyle(.borderedProminent)
        case .running:
            HStack(spacing: 8) {
                Button("Pause", action: tc.stopwatchPause)
                    .buttonStyle(.bordered)
                Button("Lap", action: tc.stopwatchLap)
                    .buttonStyle(.bordered)
            }
        case .paused:
            Button("Resume", action: tc.stopwatchStart)
                .buttonStyle(.borderedProminent)
        }
    }

    private var lapList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tc.laps.enumerated()), id: \.offset) { idx, cumulative in
                let split = idx == 0 ? cumulative : cumulative - tc.laps[idx - 1]
                HStack {
                    Text("Lap \(idx + 1)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(split.mmssString)
                        .font(.caption.monospacedDigit())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)

                if idx < tc.laps.count - 1 {
                    Divider().padding(.leading, 10)
                }
            }
        }
        .background(Color(NSColor.separatorColor).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private var colonSeparator: some View {
        Text(":")
            .font(.system(size: 22, weight: .light, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.bottom, 14) // align with field (offset for label below)
    }
}

// MARK: - Duration Input Field

struct DurationField: View {
    let label:  LocalizedStringKey
    @Binding var value: Int
    let range:  ClosedRange<Int>

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 3) {
            TextField("00", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(.system(size: 22, weight: .light, design: .monospaced))
                .frame(width: 58)
                .focused($focused)
                .onAppear { text = String(format: "%02d", value) }
                .onChange(of: text) { newText in
                    // Keep the bound value current while typing so pressing Start
                    // immediately after editing can never use the previous duration.
                    guard let parsed = Int(newText) else { return }
                    value = min(range.upperBound, max(range.lowerBound, parsed))
                }
                .onChange(of: value) { newVal in
                    if !focused { text = String(format: "%02d", newVal) }
                }
                .onChange(of: focused) { isFocused in
                    if !isFocused { commit() }
                }
                .onSubmit { commit() }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func commit() {
        let clamped = min(range.upperBound, max(range.lowerBound, Int(text) ?? value))
        value = clamped
        text  = String(format: "%02d", clamped)
    }
}
