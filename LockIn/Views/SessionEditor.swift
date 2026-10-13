import SwiftUI
import SwiftData

/// Add a focus block by hand, or fix one that already exists (forgot to start the timer,
/// forgot to pause it, picked the wrong subject, and so on).
struct SessionEditor: View {
    /// nil creates a new block.
    let session: FocusSession?
    var defaultSubject: Subject? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Subject> { !$0.isArchived }, sort: \Subject.sortOrder)
    private var subjects: [Subject]

    @State private var start: Date = Date()
    @State private var durationMinutes: Int = 25
    @State private var subject: Subject?
    @State private var intention = ""
    @State private var rating = 0
    @State private var note = ""
    @State private var confirmDelete = false
    @State private var loaded = false

    private let faces = ["😵‍💫", "😕", "😐", "🙂", "🔥"]

    private var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    private var isNew: Bool { session == nil }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(isNew ? "LOG A BLOCK" : "EDIT BLOCK")
                            .font(TypeStyle.display(30))
                            .tracking(-1)
                            .foregroundStyle(Ink.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .brutalCard(Ink.yellow, rotation: -1.5)
                        Spacer()
                        if let session, !isNew {
                            Tag(text: session.isManual ? "Logged by hand" : "From the timer", fill: Ink.white)
                        }
                    }

                    if isNew {
                        Text("Forgot to start the timer? Type the block in here and it counts exactly like the real thing.")
                            .font(TypeStyle.body(13))
                            .foregroundStyle(Ink.muted)
                    }

                    // Subject
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUBJECT").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                        FlowLayout(spacing: 8) {
                            ForEach(subjects) { s in
                                SubjectChip(subject: s, selected: subject?.persistentModelID == s.persistentModelID) {
                                    subject = (subject?.persistentModelID == s.persistentModelID) ? nil : s
                                }
                            }
                        }
                        if subject == nil {
                            Text("No subject picked. The time still counts, it just shows as unassigned.")
                                .font(TypeStyle.body(11)).foregroundStyle(Ink.muted)
                        }
                    }

                    // When
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("STARTED").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                            DatePicker("", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .font(TypeStyle.body(14))
                                .padding(8)
                                .background(Ink.white)
                                .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DURATION").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                            HStack(spacing: 10) {
                                BrutalStepper(label: "", value: $durationMinutes, range: 1...720, step: 5, unit: "min")
                                ForEach([25, 45, 60, 90], id: \.self) { m in
                                    Button("\(m)") { durationMinutes = m }
                                        .buttonStyle(BrutalButtonStyle(fill: durationMinutes == m ? Ink.yellow : Ink.white, size: 11, horizontalPadding: 10, verticalPadding: 7))
                                }
                            }
                        }
                    }

                    Text("ENDS \(end.formatted(date: .abbreviated, time: .shortened).uppercased()) · \(Fmt.duration(durationMinutes * 60)) FOCUSED")
                        .font(TypeStyle.label(10)).tracking(1).foregroundStyle(Ink.muted)

                    // Intention
                    VStack(alignment: .leading, spacing: 8) {
                        Text("INTENTION").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                        TextField("What was this block for?", text: $intention)
                            .textFieldStyle(.plain)
                            .font(TypeStyle.body(15))
                            .foregroundStyle(Ink.black)
                            .padding(12)
                            .background(Ink.white)
                            .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                    }

                    // Rating
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FOCUS RATING").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                        HStack(spacing: 8) {
                            ForEach(0..<5, id: \.self) { i in
                                Button {
                                    rating = (rating == i + 1) ? 0 : i + 1
                                } label: {
                                    Text(faces[i])
                                        .font(.system(size: 22))
                                        .frame(width: 44, height: 40)
                                        .background(rating == i + 1 ? Ink.coral : Ink.white)
                                        .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            if rating > 0 {
                                Text(String(repeating: "★", count: rating))
                                    .font(TypeStyle.label(13)).foregroundStyle(Ink.black)
                            }
                        }
                    }

                    // Reflection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOTES").font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                        TextField("What got done?", text: $note, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(2...5)
                            .font(TypeStyle.body(14))
                            .foregroundStyle(Ink.black)
                            .padding(12)
                            .background(Ink.white)
                            .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                    }

                    HStack {
                        if !isNew {
                            Button("Delete") { confirmDelete = true }
                                .buttonStyle(BrutalButtonStyle(fill: Ink.white, size: 12))
                        }
                        Button("Cancel") { dismiss() }
                            .buttonStyle(BrutalButtonStyle(fill: Ink.white, size: 12))
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button(isNew ? "Add block" : "Save changes") { save() }
                            .buttonStyle(BrutalButtonStyle(fill: Ink.coral))
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(30)
            }
        }
        .frame(width: 640, height: 720)
        .preferredColorScheme(.light)
        .onAppear(perform: load)
        .confirmationDialog("Delete this block?", isPresented: $confirmDelete) {
            Button("Delete block", role: .destructive) {
                if let session { context.delete(session); try? context.save() }
                dismiss()
            }
        } message: {
            Text("\(Fmt.duration(durationMinutes * 60)) of focus will be removed from your stats.")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let session {
            start = session.startedAt
            durationMinutes = max(1, session.focusedSeconds / 60)
            subject = session.subject
            intention = session.intention
            rating = session.focusRating
            note = session.reflection
        } else {
            // Default to a 25 minute block that just ended, snapped to 5 minutes.
            let now = Date()
            let snapped = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 300).rounded(.down) * 300)
            start = snapped.addingTimeInterval(-25 * 60)
            durationMinutes = 25
            subject = defaultSubject
        }
    }

    private func save() {
        let seconds = durationMinutes * 60
        let trimmedIntention = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let session {
            session.startedAt = start
            session.endedAt = end
            session.focusedSeconds = seconds
            session.subject = subject
            session.intention = trimmedIntention
            session.focusRating = rating
            session.reflection = trimmedNote
            session.wasEdited = true
        } else {
            let new = FocusSession(startedAt: start,
                                   endedAt: end,
                                   focusedSeconds: seconds,
                                   plannedSeconds: seconds,
                                   intention: trimmedIntention,
                                   completed: true,
                                   subject: subject,
                                   isManual: true)
            new.focusRating = rating
            new.reflection = trimmedNote
            context.insert(new)
        }
        try? context.save()
        dismiss()
    }
}
