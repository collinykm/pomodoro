import SwiftUI
import EventKit

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var service = GoogleTasksService.shared
    @State private var calendarLogger = CalendarLogger.shared
    @State private var clientSecret = ""
    @State private var calendars: [EKCalendar] = []

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("SETTINGS")
                        .font(TypeStyle.display(36))
                        .tracking(-1)
                        .foregroundStyle(Ink.black)

                    timerCard
                    behaviourCard
                    goalsCard
                    calendarCard
                    googleCard
                }
                .padding(32)
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            clientSecret = service.clientSecret
            if calendarLogger.authorized { calendars = calendarLogger.writableCalendars }
        }
    }

    // MARK: Timer

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "Timer")
            BrutalStepper(label: "Focus block", value: $settings.focusMinutes, range: 5...120, step: 5, unit: "min")
            BrutalStepper(label: "Short break", value: $settings.shortBreakMinutes, range: 1...30, step: 1, unit: "min")
            BrutalStepper(label: "Long break", value: $settings.longBreakMinutes, range: 5...60, step: 5, unit: "min")
            BrutalStepper(label: "Blocks before long break", value: $settings.sessionsBeforeLongBreak, range: 2...8, step: 1, unit: "")
            HStack(spacing: 8) {
                Text("PRESETS").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                preset("25 / 5", 25, 5, 15)
                preset("45 / 10", 45, 10, 20)
                preset("50 / 10", 50, 10, 30)
                preset("90 / 20", 90, 20, 30)
            }
        }
        .padding(22)
        .brutalCard(Ink.white)
    }

    private func preset(_ title: String, _ focus: Int, _ short: Int, _ long: Int) -> some View {
        Button(title) {
            settings.focusMinutes = focus
            settings.shortBreakMinutes = short
            settings.longBreakMinutes = long
        }
        .buttonStyle(BrutalButtonStyle(fill: settings.focusMinutes == focus && settings.shortBreakMinutes == short ? Ink.yellow : Ink.white,
                                       size: 11, horizontalPadding: 12, verticalPadding: 8))
    }

    // MARK: Behaviour

    private var behaviourCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Behaviour")
            BrutalToggle(label: "Auto-start breaks when a focus block ends", isOn: $settings.autoStartBreaks)
            BrutalToggle(label: "Auto-start the next focus block when a break ends", isOn: $settings.autoStartFocus)
            BrutalToggle(label: "Ask how it went after each focus block", isOn: $settings.askForReflection)
            BrutalToggle(label: "Play a sound when a phase ends", isOn: $settings.playSounds)
            BrutalToggle(label: "Show a notification when a phase ends", isOn: $settings.showNotifications)
            BrutalToggle(label: "Show the countdown in the menu bar", isOn: $settings.showMenuBarCountdown)
        }
        .padding(22)
        .brutalCard(Ink.white)
    }

    // MARK: Goals

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Goals")
            BrutalStepper(label: "Daily focus goal", value: $settings.dailyGoalMinutes, range: 30...720, step: 30, unit: "min")
            Text("Weekly goals per class or project live on each subject.")
                .font(TypeStyle.body(12))
                .foregroundStyle(Ink.muted)
        }
        .padding(22)
        .brutalCard(Ink.white)
    }

    // MARK: Calendar

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Calendar")
            Text("Write every finished focus block to an Apple Calendar. Notion Calendar, Fantastical and Google Calendar (via iCloud or a synced account) all pick it up from there, so your study time shows up next to your classes.")
                .font(TypeStyle.body(13))
                .foregroundStyle(Ink.black)

            BrutalToggle(label: "Log focus blocks to Calendar", isOn: Binding(
                get: { settings.logToCalendar },
                set: { on in
                    settings.logToCalendar = on
                    if on {
                        Task {
                            if await calendarLogger.requestAccess() {
                                calendars = calendarLogger.writableCalendars
                            } else {
                                settings.logToCalendar = false
                            }
                        }
                    }
                }
            ))

            if settings.logToCalendar {
                if calendars.isEmpty {
                    Text(calendarLogger.authorized
                         ? "No writable calendars found."
                         : "Calendar access was not granted. Allow LockIn under System Settings → Privacy & Security → Calendars.")
                        .font(TypeStyle.body(12))
                        .foregroundStyle(Ink.muted)
                } else {
                    HStack(spacing: 12) {
                        Text("CALENDAR").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                        Picker("", selection: $settings.calendarIdentifier) {
                            Text("Default").tag("")
                            ForEach(calendars, id: \.calendarIdentifier) { cal in
                                Text(cal.title).tag(cal.calendarIdentifier)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 260)
                    }
                }
            }
        }
        .padding(22)
        .brutalCard(Ink.white)
    }

    // MARK: Google

    private var googleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(text: "Google Tasks")
                Tag(text: service.isConnected ? "Connected" : "Not connected", fill: service.isConnected ? Ink.mint : Ink.white)
            }
            Text("Create a Desktop OAuth client in Google Cloud (the Tasks tab walks you through it) and paste its credentials here. The secret is stored in your Keychain.")
                .font(TypeStyle.body(13))
                .foregroundStyle(Ink.black)

            labelled("Client ID") {
                TextField("1234567890-abc.apps.googleusercontent.com", text: $settings.googleClientID)
            }
            labelled("Client secret") {
                SecureField("GOCSPX-…", text: $clientSecret)
                    .onChange(of: clientSecret) { _, new in service.clientSecret = new }
            }

            HStack(spacing: 12) {
                if service.isConnected {
                    Button("Disconnect") { service.disconnect() }
                        .buttonStyle(BrutalButtonStyle(fill: Ink.white))
                } else {
                    Button {
                        Task { await service.connect() }
                    } label: {
                        Label(service.isBusy ? "Waiting for Google…" : "Connect", systemImage: "link")
                    }
                    .buttonStyle(BrutalButtonStyle(fill: Ink.coral))
                    .disabled(service.isBusy || settings.googleClientID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error = service.errorMessage {
                    Text(error).font(TypeStyle.body(12)).foregroundStyle(Ink.coral)
                }
            }
        }
        .padding(22)
        .brutalCard(Ink.white)
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
            content()
                .textFieldStyle(.plain)
                .font(TypeStyle.body(14))
                .foregroundStyle(Ink.black)
                .padding(10)
                .background(Ink.paper)
                .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
        }
    }
}

// MARK: - Controls

struct BrutalStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String

    var body: some View {
        HStack {
            if !label.isEmpty {
                Text(label)
                    .font(TypeStyle.body(14))
                    .foregroundStyle(Ink.black)
                Spacer()
            }
            HStack(spacing: 0) {
                Button { value = max(range.lowerBound, value - step) } label: {
                    Image(systemName: "minus")
                        .frame(width: 32, height: 32)
                        .background(Ink.white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Rectangle().fill(Ink.black).frame(width: 3)
                Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                    .font(TypeStyle.label(13))
                    .foregroundStyle(Ink.black)
                    .frame(minWidth: 76)
                    .frame(height: 32)
                    .background(Ink.yellow)
                Rectangle().fill(Ink.black).frame(width: 3)
                Button { value = min(range.upperBound, value + step) } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                        .background(Ink.white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(Ink.black)
            .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
        }
    }
}

struct BrutalToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().fill(isOn ? Ink.coral : Ink.white)
                        .frame(width: 24, height: 24)
                        .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Ink.black)
                    }
                }
                Text(label)
                    .font(TypeStyle.body(14))
                    .foregroundStyle(Ink.black)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
