import SwiftUI
import SwiftData

/// Shown right after a focus block ends. Mirrors Session's reflection step:
/// rate your focus, jot what you got done, fix the subject or times if needed, move on.
struct ReflectionSheet: View {
    @Bindable var session: FocusSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Subject> { !$0.isArchived }, sort: \Subject.sortOrder)
    private var subjects: [Subject]

    @State private var rating: Int = 0
    @State private var note: String = ""
    @State private var subject: Subject?
    @State private var start: Date = Date()
    @State private var end: Date = Date()
    @State private var timesEdited = false
    @State private var loaded = false

    private let faces = ["😵‍💫", "😕", "😐", "🙂", "🔥"]
    private let labels = ["Scattered", "Meh", "Okay", "Good", "Locked in"]

    /// Focused seconds shown in the header: the timer's real count until the times are touched,
    /// then simply end minus start.
    private var focusedSeconds: Int {
        timesEdited ? max(60, Int(end.timeIntervalSince(start))) : session.focusedSeconds
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(session.completed ? "BLOCK DONE." : "BLOCK ENDED.")
                            .font(TypeStyle.display(34))
                            .tracking(-1)
                            .foregroundStyle(Ink.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .brutalCard(Ink.yellow, border: 3, shadow: 6, rotation: -1.5)
                        Spacer()
                        Tag(text: "\(Fmt.duration(focusedSeconds)) FOCUSED", fill: Ink.white)
                    }

                    if !session.intention.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("YOUR INTENTION")
                                .font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                            Text(session.intention)
                                .font(TypeStyle.body(16))
                                .foregroundStyle(Ink.black)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .brutalCard(Ink.white, shadow: 4)
                    }

                    // Subject
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: subject == nil ? "What was this for?" : "Subject")
                        FlowLayout(spacing: 8) {
                            ForEach(subjects) { s in
                                SubjectChip(subject: s, selected: subject?.persistentModelID == s.persistentModelID) {
                                    subject = (subject?.persistentModelID == s.persistentModelID) ? nil : s
                                }
                            }
                        }
                        if subject == nil {
                            Text("No subject. The time still counts, it just shows as unassigned.")
                                .font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                        }
                    }

                    // Times
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "Times")
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("STARTED").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                                datePicker($start)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("ENDED").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                                datePicker($end)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("FOCUSED").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                                Text(Fmt.duration(focusedSeconds))
                                    .font(TypeStyle.mono(18))
                                    .foregroundStyle(Ink.black)
                                    .padding(.horizontal, 12)
                                    .frame(height: 38)
                                    .background(Ink.yellow)
                                    .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                            }
                        }
                        Text(timesEdited
                             ? "FOCUSED TIME FOLLOWS THE TIMES YOU SET"
                             : "FORGOT TO PAUSE? ADJUST THE TIMES AND THE FOCUSED TIME FOLLOWS")
                            .font(TypeStyle.label(9)).tracking(1).foregroundStyle(Ink.muted)
                    }

                    // Rating
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "How was your focus?")
                        HStack(spacing: 10) {
                            ForEach(0..<5, id: \.self) { i in
                                Button {
                                    rating = i + 1
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(faces[i]).font(.system(size: 26))
                                        Text(labels[i].uppercased())
                                            .font(TypeStyle.label(9)).tracking(0.5)
                                            .foregroundStyle(Ink.black)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background {
                                        ZStack {
                                            if rating == i + 1 { Rectangle().fill(Ink.black).offset(x: 4, y: 4) }
                                            Rectangle().fill(rating == i + 1 ? Ink.coral : Ink.white)
                                                .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "What did you get done?")
                        TextField("One line. What moved forward, what did you learn, what's next?", text: $note, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...6)
                            .font(TypeStyle.body(15))
                            .foregroundStyle(Ink.black)
                            .padding(14)
                            .background(Ink.white)
                            .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                    }

                    HStack {
                        Button("Skip") { saveQuietly(); dismiss() }
                            .buttonStyle(BrutalButtonStyle(fill: Ink.white))
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Save reflection") { save() }
                            .buttonStyle(BrutalButtonStyle(fill: Ink.coral))
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(32)
            }
        }
        .frame(width: 680, height: 760)
        .preferredColorScheme(.light)
        .onAppear(perform: load)
        .onChange(of: start) { _, _ in if loaded { timesEdited = true; clampEnd() } }
        .onChange(of: end) { _, _ in if loaded { timesEdited = true; clampEnd() } }
    }

    private func datePicker(_ date: Binding<Date>) -> some View {
        DatePicker("", selection: date, displayedComponents: [.date, .hourAndMinute])
            .labelsHidden()
            .datePickerStyle(.field)
            .font(TypeStyle.body(14))
            .padding(8)
            .background(Ink.white)
            .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
    }

    private func clampEnd() {
        if end <= start { end = start.addingTimeInterval(60) }
    }

    private func load() {
        guard !loaded else { return }
        rating = session.focusRating
        note = session.reflection
        subject = session.subject
        start = session.startedAt
        end = session.endedAt
        loaded = true
    }

    /// Subject and time changes are kept even on Skip; only the rating and note are optional.
    private func saveQuietly() {
        applySubjectAndTimes()
        try? context.save()
    }

    private func save() {
        applySubjectAndTimes()
        session.focusRating = rating
        session.reflection = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        dismiss()
    }

    private func applySubjectAndTimes() {
        session.subject = subject
        if timesEdited {
            session.startedAt = start
            session.endedAt = end
            session.focusedSeconds = focusedSeconds
            session.wasEdited = true
        }
    }
}
