import Foundation
import SwiftUI

/// User-tunable settings, backed by UserDefaults so they survive relaunches.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: "focusMinutes") } }
    var shortBreakMinutes: Int { didSet { defaults.set(shortBreakMinutes, forKey: "shortBreakMinutes") } }
    var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: "longBreakMinutes") } }
    var sessionsBeforeLongBreak: Int { didSet { defaults.set(sessionsBeforeLongBreak, forKey: "sessionsBeforeLongBreak") } }
    var autoStartBreaks: Bool { didSet { defaults.set(autoStartBreaks, forKey: "autoStartBreaks") } }
    var autoStartFocus: Bool { didSet { defaults.set(autoStartFocus, forKey: "autoStartFocus") } }
    var playSounds: Bool { didSet { defaults.set(playSounds, forKey: "playSounds") } }
    var showNotifications: Bool { didSet { defaults.set(showNotifications, forKey: "showNotifications") } }
    var askForReflection: Bool { didSet { defaults.set(askForReflection, forKey: "askForReflection") } }
    var logToCalendar: Bool { didSet { defaults.set(logToCalendar, forKey: "logToCalendar") } }
    var calendarIdentifier: String { didSet { defaults.set(calendarIdentifier, forKey: "calendarIdentifier") } }
    var showMenuBarCountdown: Bool { didSet { defaults.set(showMenuBarCountdown, forKey: "showMenuBarCountdown") } }
    var dailyGoalMinutes: Int { didSet { defaults.set(dailyGoalMinutes, forKey: "dailyGoalMinutes") } }
    /// Google OAuth client id for the Tasks integration (client secret lives in the Keychain).
    var googleClientID: String { didSet { defaults.set(googleClientID, forKey: "googleClientID") } }
    var googleTaskListID: String { didSet { defaults.set(googleTaskListID, forKey: "googleTaskListID") } }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "focusMinutes": 25,
            "shortBreakMinutes": 5,
            "longBreakMinutes": 15,
            "sessionsBeforeLongBreak": 4,
            "autoStartBreaks": true,
            "autoStartFocus": false,
            "playSounds": true,
            "showNotifications": true,
            "askForReflection": true,
            "logToCalendar": false,
            "calendarIdentifier": "",
            "showMenuBarCountdown": true,
            "dailyGoalMinutes": 120,
            "googleClientID": "",
            "googleTaskListID": "",
        ])
        focusMinutes = d.integer(forKey: "focusMinutes")
        shortBreakMinutes = d.integer(forKey: "shortBreakMinutes")
        longBreakMinutes = d.integer(forKey: "longBreakMinutes")
        sessionsBeforeLongBreak = d.integer(forKey: "sessionsBeforeLongBreak")
        autoStartBreaks = d.bool(forKey: "autoStartBreaks")
        autoStartFocus = d.bool(forKey: "autoStartFocus")
        playSounds = d.bool(forKey: "playSounds")
        showNotifications = d.bool(forKey: "showNotifications")
        askForReflection = d.bool(forKey: "askForReflection")
        logToCalendar = d.bool(forKey: "logToCalendar")
        calendarIdentifier = d.string(forKey: "calendarIdentifier") ?? ""
        showMenuBarCountdown = d.bool(forKey: "showMenuBarCountdown")
        dailyGoalMinutes = d.integer(forKey: "dailyGoalMinutes")
        googleClientID = d.string(forKey: "googleClientID") ?? ""
        googleTaskListID = d.string(forKey: "googleTaskListID") ?? ""
    }
}
