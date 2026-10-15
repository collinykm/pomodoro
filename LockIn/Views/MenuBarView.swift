import SwiftUI
import SwiftData
import AppKit

/// The compact panel under the menu bar countdown.
struct MenuBarView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<Subject> { !$0.isArchived }, sort: \Subject.sortOrder)
    private var subjects: [Subject]
    @Query private var allSessions: [FocusSession]

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Tag(text: engine.phase.title, fill: engine.phase.isBreak ? engine.accent : Ink.coral)
                    Spacer()
                    Text("TODAY \(Fmt.duration(Stats.totalSeconds(Stats.today(allSessions))))")
                        .font(TypeStyle.label(10)).tracking(1).foregroundStyle(Ink.muted)
                }

                Text(engine.clockText)
                    .font(TypeStyle.mono(56))
                    .tracking(-2)
                    .foregroundStyle(Ink.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .brutalCard(engine.accent, border: 3, shadow: 5, rotation: -1)

                BrutalProgressBar(progress: engine.progress, fill: engine.phase.isBreak ? engine.accent : Ink.coral, height: 12)

                if engine.phase == .focus {
                    Menu {
                        Button("No subject") { engine.selectedSubject = nil }
                        ForEach(subjects) { subject in
                            Button("\(subject.emoji) \(subject.name)") { engine.selectedSubject = subject }
                        }
                    } label: {
                        HStack {
                            Text(engine.selectedSubject.map { "\($0.emoji) \($0.name)" } ?? "Pick a subject")
                                .font(TypeStyle.body(13))
                                .foregroundStyle(Ink.black)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Ink.black)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(Ink.white)
                        .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }

                HStack(spacing: 8) {
                    Button {
                        engine.toggle()
                    } label: {
                        Label(engine.isRunning ? "Pause" : (engine.state == .paused ? "Resume" : "Start"),
                              systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(BrutalButtonStyle(fill: engine.isRunning ? Ink.white : Ink.coral, size: 12, horizontalPadding: 14, verticalPadding: 9))

                    Button { engine.skip() } label: { Image(systemName: "forward.fill") }
                        .buttonStyle(BrutalIconButtonStyle(fill: Ink.white, side: 34))
                        .help("Skip")
                    Button { engine.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(BrutalIconButtonStyle(fill: Ink.white, side: 34))
                        .help("Reset")
                    Spacer()
                    Button { engine.add(minutes: 5) } label: { Text("+5") }
                        .buttonStyle(BrutalIconButtonStyle(fill: Ink.yellow, side: 34))
                }

                Divider().frame(height: 2).overlay(Ink.black)

                HStack {
                    Button("Open LockIn") {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .buttonStyle(BrutalButtonStyle(fill: Ink.white, size: 11, horizontalPadding: 12, verticalPadding: 7))
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(TypeStyle.label(11))
                        .foregroundStyle(Ink.muted)
                }
            }
            .padding(18)
        }
        .frame(width: 320)
        .preferredColorScheme(.light)
    }
}
