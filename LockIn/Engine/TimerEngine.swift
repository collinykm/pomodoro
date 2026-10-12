import Foundation
import SwiftData
import SwiftUI
import AppKit
import UserNotifications

enum TimerPhase: Equatable {
    case focus
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    var isBreak: Bool { self != .focus }
}

enum TimerState: Equatable {
    case idle
    case running
    case paused
}

/// Drives the countdown. Wall-clock based (an end date), so it survives app sleep and
/// stays accurate even if the UI stops ticking for a while.
@Observable
@MainActor
final class TimerEngine {
    // Observable state
    private(set) var phase: TimerPhase = .focus
    private(set) var state: TimerState = .idle
    private(set) var remaining: Int = 25 * 60
    private(set) var total: Int = 25 * 60
    /// Focus blocks completed in the current cycle (resets after a long break).
    private(set) var cyclePosition: Int = 0
    /// Set when a focus block ends and the user should be asked how it went.
    var pendingReflection: FocusSession?
    /// Toggled briefly when a phase completes so the UI can flash.
    private(set) var justCompleted: Bool = false

    var intention: String = ""
    var selectedSubject: Subject?

    // Internals
    private var endDate: Date?
    private var sessionStart: Date?
    private var segmentStart: Date?
    private var accumulatedSeconds: Int = 0
    /// The phase length the idle display was last synced to, so manual ±5 tweaks survive ticks.
    private var syncedLength: Int = 0
    private var ticker: Timer?
    private var container: ModelContainer?
    private let settings = AppSettings.shared

    init() {
        total = settings.focusMinutes * 60
        remaining = total
        syncedLength = total
        startTicker()
    }

    func attach(container: ModelContainer) {
        self.container = container
    }

    // MARK: Derived

    var progress: Double {
        guard total > 0 else { return 0 }
        return 1 - Double(remaining) / Double(total)
    }

    var isRunning: Bool { state == .running }

    /// Seconds of real focus accumulated in the active focus block so far.
    var focusedSoFar: Int {
        guard phase == .focus else { return 0 }
        var secs = accumulatedSeconds
        if state == .running, let segmentStart {
            secs += Int(Date().timeIntervalSince(segmentStart))
        }
        return secs
    }

    var menuBarTitle: String {
        switch state {
        case .idle:
            return phase == .focus ? "LOCK IN" : Fmt.clock(remaining)
        case .running:
            return (phase == .focus ? "" : "☕ ") + Fmt.clock(remaining)
        case .paused:
            return "⏸ " + Fmt.clock(remaining)
        }
    }

    var accent: Color {
        switch phase {
        case .focus: return Ink.yellow
        case .shortBreak: return Ink.mint
        case .longBreak: return Ink.lavender
        }
    }

    // MARK: Controls

    func toggle() {
        switch state {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        }
    }

    func start() {
        guard state == .idle else { return }
        total = max(60, total)
        remaining = total
        accumulatedSeconds = 0
        let now = Date()
        sessionStart = now
        segmentStart = now
        endDate = now.addingTimeInterval(TimeInterval(total))
        state = .running
        Notifier.requestPermissionIfNeeded()
        tick()
    }

    func pause() {
        guard state == .running, let segmentStart, let endDate else { return }
        let now = Date()
        accumulatedSeconds += Int(now.timeIntervalSince(segmentStart))
        remaining = max(0, Int(ceil(endDate.timeIntervalSince(now))))
        self.segmentStart = nil
        self.endDate = nil
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        let now = Date()
        segmentStart = now
        endDate = now.addingTimeInterval(TimeInterval(remaining))
        state = .running
        tick()
    }

    /// Ends the current phase early. A focus block that already ran for at least a minute
    /// is still logged (as incomplete) so the time is not lost.
    func skip() {
        switch phase {
        case .focus:
            if state != .idle {
                finishFocus(completed: false)
            } else {
                advanceAfterFocus(autoStart: false)
            }
        case .shortBreak, .longBreak:
            cancelCountdown()
            beginPhase(.focus, autoStart: false)
        }
    }

    /// Stops and discards the current phase without logging anything.
    func reset() {
        cancelCountdown()
        beginPhase(phase, autoStart: false)
    }

    /// Jump straight to a phase (used by the menu bar quick actions).
    func jump(to newPhase: TimerPhase) {
        if phase == .focus && state != .idle {
            finishFocus(completed: false, thenStart: newPhase)
            return
        }
        cancelCountdown()
        beginPhase(newPhase, autoStart: false)
    }

    func add(minutes: Int) {
        let delta = minutes * 60
        total = max(60, total + delta)
        remaining = max(1, remaining + delta)
        if state == .running {
            endDate = Date().addingTimeInterval(TimeInterval(remaining))
        }
    }

    // MARK: Ticking

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
    }

    private func tick() {
        switch state {
        case .idle:
            // Keep the idle display in sync with the settings.
            let length = phaseLength(phase)
            if length != syncedLength { syncedLength = length; total = length; remaining = length }
        case .paused:
            break
        case .running:
            guard let endDate else { return }
            let left = Int(ceil(endDate.timeIntervalSince(Date())))
            remaining = max(0, left)
            if left <= 0 { phaseCompleted() }
        }
    }

    private func phaseCompleted() {
        switch phase {
        case .focus:
            finishFocus(completed: true)
        case .shortBreak, .longBreak:
            cancelCountdown()
            flash()
            Notifier.notify(title: "Break's over", body: "Time to lock back in.", sound: settings.playSounds, enabled: settings.showNotifications)
            beginPhase(.focus, autoStart: settings.autoStartFocus)
        }
    }

    // MARK: Session bookkeeping

    private func finishFocus(completed: Bool, thenStart forced: TimerPhase? = nil) {
        let now = Date()
        var focused = accumulatedSeconds
        if let segmentStart { focused += Int(now.timeIntervalSince(segmentStart)) }
        let planned = total
        let start = sessionStart ?? now.addingTimeInterval(-TimeInterval(focused))
        let subject = selectedSubject
        let intentionText = intention.trimmingCharacters(in: .whitespacesAndNewlines)

        cancelCountdown()

        // Only record blocks that were real (at least a minute of focus).
        if focused >= 60 {
            let session = FocusSession(startedAt: start,
                                       endedAt: now,
                                       focusedSeconds: focused,
                                       plannedSeconds: planned,
                                       intention: intentionText,
                                       completed: completed,
                                       subject: subject)
            if let context = container?.mainContext {
                context.insert(session)
                try? context.save()
            }
            if settings.askForReflection {
                pendingReflection = session
            }
            if settings.logToCalendar {
                CalendarLogger.shared.log(session: session, subjectName: subject?.name)
            }
        }

        if completed {
            cyclePosition += 1
            flash()
            let what = subject.map { " on \($0.name)" } ?? ""
            Notifier.notify(title: "Focus block done",
                            body: "Nice. \(Fmt.duration(focused)) locked in\(what). Take a break.",
                            sound: settings.playSounds,
                            enabled: settings.showNotifications)
        }

        if let forced {
            beginPhase(forced, autoStart: false)
        } else {
            advanceAfterFocus(autoStart: completed && settings.autoStartBreaks)
        }
    }

    private func advanceAfterFocus(autoStart: Bool) {
        let longDue = cyclePosition > 0 && cyclePosition % settings.sessionsBeforeLongBreak == 0
        let next: TimerPhase = longDue ? .longBreak : .shortBreak
        beginPhase(next, autoStart: autoStart)
    }

    private func beginPhase(_ newPhase: TimerPhase, autoStart: Bool) {
        if phase == .longBreak && newPhase == .focus { cyclePosition = 0 }
        phase = newPhase
        syncedLength = phaseLength(newPhase)
        total = syncedLength
        remaining = total
        state = .idle
        if autoStart { start() }
    }

    private func cancelCountdown() {
        endDate = nil
        segmentStart = nil
        sessionStart = nil
        accumulatedSeconds = 0
        state = .idle
    }

    private func phaseLength(_ p: TimerPhase) -> Int {
        switch p {
        case .focus: return max(1, settings.focusMinutes) * 60
        case .shortBreak: return max(1, settings.shortBreakMinutes) * 60
        case .longBreak: return max(1, settings.longBreakMinutes) * 60
        }
    }

    private func flash() {
        justCompleted = true
        if settings.playSounds { SoundPlayer.chime() }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            self.justCompleted = false
        }
    }
}

// MARK: - Sounds & notifications

enum SoundPlayer {
    static func chime() {
        (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play()
    }
}

enum Notifier {
    private static var asked = false

    static func requestPermissionIfNeeded() {
        guard !asked else { return }
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String, sound: Bool, enabled: Bool) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
