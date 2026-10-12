import SwiftUI
import SwiftData

@main
struct LockInApp: App {
    let container: ModelContainer
    @State private var engine: TimerEngine
    @Bindable private var settings = AppSettings.shared

    init() {
        let schema = Schema([Subject.self, FocusSession.self])
        let config = ModelConfiguration("LockIn", schema: schema)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not open the LockIn database: \(error)")
        }
        let engine = TimerEngine()
        engine.attach(container: container)
        _engine = State(initialValue: engine)
        SeedData.seedIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(engine)
                .frame(minWidth: 980, minHeight: 680)
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandMenu("Timer") {
                Button(engine.isRunning ? "Pause" : "Start") { engine.toggle() }
                    .keyboardShortcut(.return, modifiers: [.command])
                Button("Skip Phase") { engine.skip() }
                    .keyboardShortcut("k", modifiers: [.command])
                Button("Reset") { engine.reset() }
                    .keyboardShortcut("r", modifiers: [.command])
                Divider()
                Button("Add 5 Minutes") { engine.add(minutes: 5) }
                    .keyboardShortcut("=", modifiers: [.command])
                Button("Remove 5 Minutes") { engine.add(minutes: -5) }
                    .keyboardShortcut("-", modifiers: [.command])
            }
        }

        MenuBarExtra(isInserted: $settings.showMenuBarCountdown) {
            MenuBarView()
                .environment(engine)
                .modelContainer(container)
        } label: {
            Label {
                Text(engine.menuBarTitle)
                    .monospacedDigit()
            } icon: {
                Image(systemName: engine.isRunning ? "lock.fill" : "lock.open.fill")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(engine)
                .frame(width: 720, height: 760)
        }
    }
}
