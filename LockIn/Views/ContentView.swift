import SwiftUI
import SwiftData

enum Screen: String, CaseIterable, Identifiable {
    case focus = "Focus"
    case subjects = "Subjects"
    case stats = "Stats"
    case log = "Log"
    case tasks = "Tasks"
    case settings = "Settings"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(TimerEngine.self) private var engine
    @Query private var allSessions: [FocusSession]
    @State private var screen: Screen = .focus

    private var todaySeconds: Int { Stats.totalSeconds(Stats.today(allSessions)) }

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                MarqueeBar(items: marqueeItems)
                navBar
                Divider().frame(height: 3).overlay(Ink.black)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.light)
        .onReceive(NotificationCenter.default.publisher(for: .lockInShowScreen)) { note in
            if let raw = note.object as? String, let s = Screen(rawValue: raw) {
                screen = s
            }
        }
    }

    private var marqueeItems: [String] {
        var items = ["LOCK IN", "\(Fmt.duration(todaySeconds)) FOCUSED TODAY"]
        if engine.isRunning {
            items.append(engine.phase == .focus ? "FOCUS MODE ON" : "BREAK TIME")
        }
        let streak = Stats.streak(allSessions)
        if streak > 1 { items.append("\(streak) DAY STREAK") }
        items.append("ONE BLOCK AT A TIME")
        return items
    }

    private var navBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 10) {
                Text("L")
                    .font(TypeStyle.display(18))
                    .foregroundStyle(Ink.black)
                    .frame(width: 34, height: 34)
                    .background(Ink.yellow)
                    .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                Text("LOCKIN")
                    .font(TypeStyle.display(22))
                    .tracking(-0.5)
                    .foregroundStyle(Ink.black)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(Screen.allCases.filter { $0 != .settings }) { s in
                    navButton(s)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Tag(text: "TODAY \(Fmt.duration(todaySeconds))", fill: Ink.white)
                Button {
                    screen = .settings
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(BrutalIconButtonStyle(fill: screen == .settings ? Ink.coral : Ink.white, side: 36))
                .help("Settings")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Ink.paper)
    }

    private func navButton(_ s: Screen) -> some View {
        Button {
            screen = s
        } label: {
            Text(s.rawValue.uppercased())
                .font(.system(size: 13, weight: .black))
                .tracking(0.8)
                .foregroundStyle(Ink.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if screen == s {
                        Rectangle().fill(Ink.yellow).overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .focus: TimerView()
        case .subjects: SubjectsView()
        case .stats: StatsView()
        case .log: LogView()
        case .tasks: TasksView()
        case .settings: SettingsView()
        }
    }
}

extension Notification.Name {
    /// Post with a `Screen.rawValue` as object to switch the main window to that screen.
    static let lockInShowScreen = Notification.Name("lockInShowScreen")
}
