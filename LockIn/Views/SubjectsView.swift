import SwiftUI
import SwiftData

struct SubjectsView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerEngine.self) private var engine
    @Query(sort: \Subject.sortOrder) private var subjects: [Subject]
    @Query private var allSessions: [FocusSession]

    @State private var editing: Subject?
    @State private var creating = false
    @State private var showArchived = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR SUBJECTS")
                            .font(TypeStyle.display(36))
                            .tracking(-1)
                            .foregroundStyle(Ink.black)
                        Text("Classes, side projects, and anything else worth a focus block. Each gets its own color and weekly goal.")
                            .font(TypeStyle.body(14))
                            .foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    Button {
                        creating = true
                    } label: {
                        Label("New subject", systemImage: "plus")
                    }
                    .buttonStyle(BrutalButtonStyle(fill: Ink.coral))
                }

                ForEach(SubjectKind.allCases) { kind in
                    let group = subjects.filter { $0.kind == kind && (showArchived || !$0.isArchived) }
                    if !group.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: kind.icon)
                                Text(kind.plural.uppercased())
                                    .tracking(1.2)
                                Spacer()
                            }
                            .font(TypeStyle.label(12))
                            .foregroundStyle(Ink.muted)

                            ForEach(group) { subject in
                                SubjectRow(subject: subject,
                                           weekSeconds: weekSeconds(for: subject),
                                           totalSeconds: totalSeconds(for: subject),
                                           isActive: engine.selectedSubject?.persistentModelID == subject.persistentModelID,
                                           onEdit: { editing = subject },
                                           onSelect: {
                                               engine.selectedSubject = subject
                                               NotificationCenter.default.post(name: .lockInShowScreen, object: Screen.focus.rawValue)
                                           },
                                           onArchive: { subject.isArchived.toggle(); try? context.save() },
                                           onDelete: { delete(subject) })
                            }
                        }
                    }
                }

                if subjects.isEmpty {
                    Text("Nothing here yet. Add your first class or project.")
                        .font(TypeStyle.body(15))
                        .foregroundStyle(Ink.black)
                        .padding(22)
                        .frame(maxWidth: .infinity)
                        .brutalCard(Ink.white)
                }

                if subjects.contains(where: { $0.isArchived }) {
                    Toggle(isOn: $showArchived) {
                        Text("Show archived")
                            .font(TypeStyle.body(13))
                            .foregroundStyle(Ink.black)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(32)
        }
        .sheet(isPresented: $creating) {
            SubjectEditor(subject: nil, nextSortOrder: (subjects.map(\.sortOrder).max() ?? -1) + 1)
        }
        .sheet(item: $editing) { subject in
            SubjectEditor(subject: subject, nextSortOrder: subject.sortOrder)
        }
    }

    private func weekSeconds(for subject: Subject) -> Int {
        let week = Stats.thisWeek(allSessions)
        return week.filter { $0.subject?.persistentModelID == subject.persistentModelID }
            .reduce(0) { $0 + $1.focusedSeconds }
    }

    private func totalSeconds(for subject: Subject) -> Int {
        allSessions.filter { $0.subject?.persistentModelID == subject.persistentModelID }
            .reduce(0) { $0 + $1.focusedSeconds }
    }

    private func delete(_ subject: Subject) {
        if engine.selectedSubject?.persistentModelID == subject.persistentModelID {
            engine.selectedSubject = nil
        }
        context.delete(subject)
        try? context.save()
    }
}

// MARK: - Row

struct SubjectRow: View {
    let subject: Subject
    let weekSeconds: Int
    let totalSeconds: Int
    let isActive: Bool
    let onEdit: () -> Void
    let onSelect: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 18) {
            Text(subject.emoji)
                .font(.system(size: 26))
                .frame(width: 54, height: 54)
                .background(subject.color)
                .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(subject.name)
                        .font(TypeStyle.heading(18))
                        .foregroundStyle(Ink.black)
                    Tag(text: subject.displayCode, fill: Ink.white)
                    if subject.isArchived { Tag(text: "Archived", fill: Ink.paper) }
                    if isActive { Tag(text: "Active", fill: Ink.yellow) }
                }
                HStack(spacing: 14) {
                    Text("THIS WEEK \(Fmt.duration(weekSeconds))")
                    Text("ALL TIME \(Fmt.duration(totalSeconds))")
                }
                .font(TypeStyle.label(10))
                .tracking(1)
                .foregroundStyle(Ink.muted)
            }

            Spacer()

            if subject.weeklyGoalMinutes > 0 {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(Int(min(100, Double(weekSeconds) / Double(subject.weeklyGoalMinutes * 60) * 100)))% OF \(Fmt.duration(subject.weeklyGoalMinutes * 60))")
                        .font(TypeStyle.label(10))
                        .tracking(1)
                        .foregroundStyle(Ink.muted)
                    BrutalProgressBar(progress: Double(weekSeconds) / Double(subject.weeklyGoalMinutes * 60), fill: subject.color, height: 14)
                        .frame(width: 160)
                }
            }

            HStack(spacing: 8) {
                Button { onSelect() } label: { Image(systemName: "play.fill") }
                    .buttonStyle(BrutalIconButtonStyle(fill: Ink.yellow, side: 36))
                    .help("Focus on this now")
                Button { onEdit() } label: { Image(systemName: "pencil") }
                    .buttonStyle(BrutalIconButtonStyle(fill: Ink.white, side: 36))
                    .help("Edit")
                Menu {
                    Button(subject.isArchived ? "Unarchive" : "Archive") { onArchive() }
                    Button("Delete…", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 36, height: 36)
                .background(Ink.white)
                .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
            }
        }
        .padding(16)
        .brutalCard(Ink.white, shadow: 5)
        .opacity(subject.isArchived ? 0.6 : 1)
        .confirmationDialog("Delete \(subject.name)?", isPresented: $confirmDelete) {
            Button("Delete subject", role: .destructive) { onDelete() }
        } message: {
            Text("Logged focus time is kept but becomes unassigned.")
        }
    }
}

// MARK: - Editor

struct SubjectEditor: View {
    let subject: Subject?
    let nextSortOrder: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var code = ""
    @State private var emoji = "📚"
    @State private var kind: SubjectKind = .course
    @State private var colorHex = "FF6B6B"
    @State private var weeklyGoalHours: Double = 3

    private let emojiChoices = ["📚", "📐", "💻", "🧪", "🧬", "📖", "✍️", "🎨", "🎵", "🏛️", "🌍", "⚖️", "💰", "🛠️", "🚀", "🧠", "🏃", "🎯"]

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(alignment: .leading, spacing: 22) {
                Text(subject == nil ? "NEW SUBJECT" : "EDIT SUBJECT")
                    .font(TypeStyle.display(30))
                    .tracking(-1)
                    .foregroundStyle(Ink.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .brutalCard(Ink.yellow, rotation: -1.5)

                field("Name") {
                    TextField("Organic Chemistry", text: $name)
                }
                field("Short code (optional)") {
                    TextField("CHEM 210", text: $code)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("TYPE").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                    HStack(spacing: 8) {
                        ForEach(SubjectKind.allCases) { k in
                            Button {
                                kind = k
                            } label: {
                                Label(k.rawValue, systemImage: k.icon)
                            }
                            .buttonStyle(BrutalButtonStyle(fill: kind == k ? Ink.coral : Ink.white, size: 12, horizontalPadding: 14, verticalPadding: 9))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("EMOJI").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                    FlowLayout(spacing: 6) {
                        ForEach(emojiChoices, id: \.self) { e in
                            Button { emoji = e } label: {
                                Text(e).font(.system(size: 20))
                                    .frame(width: 38, height: 38)
                                    .background(emoji == e ? Ink.yellow : Ink.white)
                                    .overlay(Rectangle().stroke(Ink.black, lineWidth: emoji == e ? 3 : 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("COLOR").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                    HStack(spacing: 8) {
                        ForEach(Ink.subjectPalette, id: \.self) { hex in
                            let str = String(format: "%06X", hex)
                            Button { colorHex = str } label: {
                                Rectangle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 36, height: 36)
                                    .overlay(Rectangle().stroke(Ink.black, lineWidth: colorHex == str ? 4 : 2))
                                    .overlay {
                                        if colorHex == str {
                                            Image(systemName: "checkmark").font(.system(size: 14, weight: .black)).foregroundStyle(Ink.black)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("WEEKLY GOAL · \(weeklyGoalHours == 0 ? "NONE" : String(format: "%.1fH", weeklyGoalHours))")
                        .font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                    Slider(value: $weeklyGoalHours, in: 0...20, step: 0.5)
                        .tint(Ink.coral)
                }

                HStack {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(BrutalButtonStyle(fill: Ink.white))
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(subject == nil ? "Add subject" : "Save") { save() }
                        .buttonStyle(BrutalButtonStyle(fill: Ink.coral))
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(30)
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(.light)
        .onAppear(perform: load)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
            content()
                .textFieldStyle(.plain)
                .font(TypeStyle.body(16))
                .foregroundStyle(Ink.black)
                .padding(12)
                .background(Ink.white)
                .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
        }
    }

    private func load() {
        guard let subject else { return }
        name = subject.name
        code = subject.code
        emoji = subject.emoji
        kind = subject.kind
        colorHex = subject.colorHex
        weeklyGoalHours = Double(subject.weeklyGoalMinutes) / 60
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let goal = Int(weeklyGoalHours * 60)
        if let subject {
            subject.name = trimmedName
            subject.code = code.trimmingCharacters(in: .whitespaces)
            subject.emoji = emoji
            subject.kind = kind
            subject.colorHex = colorHex
            subject.weeklyGoalMinutes = goal
        } else {
            let new = Subject(name: trimmedName,
                              code: code.trimmingCharacters(in: .whitespaces),
                              emoji: emoji,
                              colorHex: colorHex,
                              kind: kind,
                              weeklyGoalMinutes: goal,
                              sortOrder: nextSortOrder)
            context.insert(new)
        }
        try? context.save()
        dismiss()
    }
}
