import SwiftUI
import SwiftData

struct TimerView: View {
    @Environment(TimerEngine.self) private var engine
    @Query(filter: #Predicate<Subject> { !$0.isArchived }, sort: \Subject.sortOrder)
    private var subjects: [Subject]
    @Query private var allSessions: [FocusSession]
    @State private var loggingBlock = false
    @State private var editingBlock: FocusSession?

    private let settings = AppSettings.shared

    var body: some View {
        @Bindable var engine = engine
        GeometryReader { geo in
            let wide = geo.size.width > 1040
            ScrollView {
                VStack(spacing: 32) {
                    if wide {
                        HStack(alignment: .top, spacing: 36) {
                            timerColumn
                                .frame(maxWidth: .infinity)
                            sideColumn
                                .frame(width: 360)
                        }
                    } else {
                        timerColumn
                        sideColumn
                    }
                    DayTimelineCard(allSessions: allSessions,
                                    activeStart: engine.activeFocusStart,
                                    activeColor: engine.accent) { session in
                        editingBlock = session
                    }
                }
                .padding(32)
            }
        }
        .sheet(item: $engine.pendingReflection) { session in
            ReflectionSheet(session: session)
        }
        .sheet(isPresented: $loggingBlock) {
            SessionEditor(session: nil, defaultSubject: engine.selectedSubject)
        }
        .sheet(item: $editingBlock) { session in
            SessionEditor(session: session)
        }
    }

    // MARK: Timer column

    private var timerColumn: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Phase header
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Tag(text: phaseTagText, fill: engine.phase.isBreak ? engine.accent : Ink.coral, rotation: -2)
                if engine.overtime {
                    Tag(text: "Overtime", fill: Ink.black, foreground: Ink.yellow, rotation: 2)
                }
                if let subject = engine.selectedSubject, engine.phase == .focus {
                    Tag(text: "\(subject.emoji) \(subject.name)", fill: subject.color)
                }
                Spacer()
                cycleDots
            }

            // Big clock slab
            ZStack(alignment: .topTrailing) {
                Text(engine.clockText)
                    .font(TypeStyle.mono(clockSize))
                    .tracking(-4)
                    .foregroundStyle(Ink.black)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .brutalCard(engine.justCompleted ? Ink.coral : engine.accent, border: 4, shadow: 10, rotation: -1.5)
                    .animation(.easeInOut(duration: 0.2), value: engine.justCompleted)

                Image(systemName: engine.phase.isBreak ? "cup.and.saucer.fill" : "lock.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(Ink.black)
                    .frame(width: 44, height: 44)
                    .background(Ink.white)
                    .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                    .offset(x: 10, y: -18)
            }
            .padding(.top, 8)

            // Progress
            VStack(alignment: .leading, spacing: 8) {
                BrutalProgressBar(progress: engine.progress, fill: engine.phase.isBreak ? engine.accent : Ink.coral)
                HStack {
                    Text(engine.state == .idle ? "READY" : (engine.state == .paused ? "PAUSED" : (engine.overtime ? "TARGET HIT · STILL COUNTING" : "IN PROGRESS")))
                    Spacer()
                    Text("\(Int(engine.progress * 100))% · \(Fmt.duration(engine.total)) BLOCK")
                }
                .font(TypeStyle.label(11))
                .tracking(1)
                .foregroundStyle(Ink.muted)
            }

            // Controls
            HStack(spacing: 14) {
                Button {
                    engine.toggle()
                } label: {
                    Label(primaryLabel, systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(BrutalButtonStyle(fill: engine.isRunning ? Ink.white : Ink.coral, size: 15, horizontalPadding: 30, verticalPadding: 15))
                .keyboardShortcut(.space, modifiers: [])

                Button {
                    engine.skip()
                } label: {
                    Label(engine.phase.isBreak ? "Skip break" : (engine.overtime ? "Finish block" : "Finish early"), systemImage: engine.overtime ? "checkmark" : "forward.fill")
                }
                .buttonStyle(BrutalButtonStyle(fill: engine.overtime ? Ink.coral : Ink.white, size: 13))

                Button {
                    engine.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(BrutalIconButtonStyle(fill: Ink.white, side: 44))
                .help("Reset this block")

                Spacer()

                HStack(spacing: 8) {
                    Button("−5") { engine.add(minutes: -5) }
                        .buttonStyle(BrutalButtonStyle(fill: Ink.white, size: 12, horizontalPadding: 12, verticalPadding: 10))
                    Button("+5") { engine.add(minutes: 5) }
                        .buttonStyle(BrutalButtonStyle(fill: Ink.yellow, size: 12, horizontalPadding: 12, verticalPadding: 10))
                }
            }

            // Intention
            intentionCard
        }
    }

    private func blockTime(_ s: FocusSession) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        var text = "\(f.string(from: s.startedAt)) – \(f.string(from: s.endedAt))".uppercased()
        if s.isManual { text += " · LOGGED" } else if s.wasEdited { text += " · EDITED" }
        return text
    }

    private var clockSize: CGFloat {
        engine.remaining >= 3600 ? 120 : 164
    }

    private var phaseTagText: String {
        switch engine.phase {
        case .focus: return "Focus block #\(engine.cyclePosition + 1)"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    private var primaryLabel: String {
        switch engine.state {
        case .idle: return engine.phase.isBreak ? "Start break" : "Lock in"
        case .running: return "Pause"
        case .paused: return "Resume"
        }
    }

    private var cycleDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(1, settings.sessionsBeforeLongBreak), id: \.self) { i in
                Rectangle()
                    .fill(i < engine.cyclePosition ? Ink.black : Ink.white)
                    .frame(width: 14, height: 14)
                    .overlay(Rectangle().stroke(Ink.black, lineWidth: 2.5))
            }
            Text("UNTIL LONG BREAK")
                .font(TypeStyle.label(10))
                .tracking(1)
                .foregroundStyle(Ink.muted)
                .padding(.leading, 4)
        }
    }

    private var intentionCard: some View {
        @Bindable var engine = engine
        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "What are you locking in on?")
            TextField("e.g. Finish problem set 4, questions 1–6", text: $engine.intention)
                .textFieldStyle(.plain)
                .font(TypeStyle.body(18))
                .foregroundStyle(Ink.black)
                .padding(14)
                .background(Ink.paper)
                .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
            Text("Session asks for an intention before every block. Write one sentence you could tick off at the end.")
                .font(TypeStyle.body(12))
                .foregroundStyle(Ink.muted)
        }
        .padding(22)
        .brutalCard(Ink.white)
    }

    // MARK: Side column

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 28) {
            subjectPicker
            todayCard
        }
    }

    private var subjectPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle(text: "Subject")
                Button {
                    NotificationCenter.default.post(name: .lockInShowScreen, object: Screen.subjects.rawValue)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(BrutalIconButtonStyle(fill: Ink.white, side: 30))
                .help("Manage subjects")
            }

            if subjects.isEmpty {
                Text("No subjects yet. Add your classes and projects under Subjects.")
                    .font(TypeStyle.body(13))
                    .foregroundStyle(Ink.black)
            }

            ForEach(SubjectKind.allCases) { kind in
                let group = subjects.filter { $0.kind == kind }
                if !group.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(kind.plural.uppercased())
                            .font(TypeStyle.label(10))
                            .tracking(1.2)
                            .foregroundStyle(Ink.muted)
                        FlowLayout(spacing: 8) {
                            ForEach(group) { subject in
                                SubjectChip(subject: subject, selected: engine.selectedSubject?.persistentModelID == subject.persistentModelID) {
                                    if engine.selectedSubject?.persistentModelID == subject.persistentModelID {
                                        engine.selectedSubject = nil
                                    } else {
                                        engine.selectedSubject = subject
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(22)
        .brutalCard(Ink.lavender)
    }

    private var todayCard: some View {
        let today = Stats.today(allSessions)
        let seconds = Stats.totalSeconds(today)
        let goal = max(1, settings.dailyGoalMinutes * 60)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(text: "Today")
                Button {
                    loggingBlock = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(BrutalIconButtonStyle(fill: Ink.white, side: 30))
                .help("Log a block you forgot to time")
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.duration(seconds))
                    .font(TypeStyle.display(40))
                    .tracking(-1)
                    .foregroundStyle(Ink.black)
                Spacer()
                Text("\(today.count) BLOCK\(today.count == 1 ? "" : "S")")
                    .font(TypeStyle.label(11))
                    .tracking(1)
                    .foregroundStyle(Ink.muted)
            }
            BrutalProgressBar(progress: Double(seconds) / Double(goal), fill: Ink.yellow, height: 16)
            Text("GOAL \(Fmt.duration(goal))")
                .font(TypeStyle.label(10))
                .tracking(1)
                .foregroundStyle(Ink.muted)

            if !today.isEmpty {
                Divider().frame(height: 2).overlay(Ink.black)
                HStack {
                    Text("BLOCKS · CLICK TO EDIT")
                        .font(TypeStyle.label(9)).tracking(1).foregroundStyle(Ink.muted)
                    Spacer()
                    if today.count > 6 {
                        Button("ALL \(today.count) IN LOG") {
                            NotificationCenter.default.post(name: .lockInShowScreen, object: Screen.log.rawValue)
                        }
                        .buttonStyle(.plain)
                        .font(TypeStyle.label(9)).tracking(1).foregroundStyle(Ink.black)
                    }
                }
                ForEach(today.sorted { $0.startedAt > $1.startedAt }.prefix(6)) { s in
                    Button {
                        editingBlock = s
                    } label: {
                        HStack(spacing: 10) {
                            Rectangle()
                                .fill(s.subject?.color ?? Color(hex: 0xBDBDBD))
                                .frame(width: 12, height: 12)
                                .overlay(Rectangle().stroke(Ink.black, lineWidth: 2))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.subject?.name ?? "Unassigned")
                                    .font(TypeStyle.body(13))
                                    .foregroundStyle(Ink.black)
                                    .lineLimit(1)
                                Text(blockTime(s))
                                    .font(TypeStyle.label(9)).tracking(0.8).foregroundStyle(Ink.muted)
                            }
                            Spacer()
                            Text(Fmt.duration(s.focusedSeconds))
                                .font(TypeStyle.label(12))
                                .foregroundStyle(Ink.black)
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Ink.muted)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(22)
        .brutalCard(Ink.white)
    }
}

// MARK: - Subject chip

struct SubjectChip: View {
    let subject: Subject
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(subject.emoji)
                Text(subject.name)
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Ink.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                ZStack {
                    if selected { Rectangle().fill(Ink.black).offset(x: 3, y: 3) }
                    Rectangle().fill(selected ? subject.color : Ink.white)
                        .overlay(Rectangle().stroke(Ink.black, lineWidth: 2.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow layout (wrapping chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
