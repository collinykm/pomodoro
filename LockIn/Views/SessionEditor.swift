import SwiftUI
import SwiftData

/// Add a focus block by hand, or fix one that already exists (forgot to start the timer,
/// forgot to pause it, picked the wrong subject, and so on).
///
/// Start, end and focused time are all editable. Changing the focused time moves the end
/// (start stays put); changing the end recomputes the focused time; moving the start keeps
/// the focused time and shifts the end along with it.
struct SessionEditor: View {
    /// nil creates a new block.
    let session: FocusSession?
    var defaultSubject: Subject? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Subject> { !$0.isArchived }, sort: \Subject.sortOrder)
    private var subjects: [Subject]

    @State private var start: Date = Date()
    @State private var end: Date = Date()
    @State private var focusedMinutes: Int = 25
    @State private var focusedText: String = "25"
    @State private var subject: Subject?
    @State private var intention = ""
    @State private var rating = 0
    @State private var note = ""
    @State private var confirmDelete = false
    @State private var loaded = false
    /// Guards the start/end/focused observers so one edit does not ping-pong into the others.
    @State private var syncing = false

    private let faces = ["😵‍💫", "😕", "😐", "🙂", "🔥"]

    private var isNew: Bool { session == nil }
    private var spanSeconds: Int { max(0, Int(end.timeIntervalSince(start))) }
    private var pausedSeconds: Int { max(0, spanSeconds - focusedMinutes * 60) }

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

                    subjectSection
                    timeSection
                    intentionSection
                    ratingSection
                    notesSection

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
                            .disabled(focusedMinutes < 1)
                    }
                }
                .padding(30)
            }
        }
        .frame(width: 660, height: 760)
        .preferredColorScheme(.light)
        .onAppear(perform: load)
        .onChange(of: start) { _, newStart in
            guard !syncing else { return }
            sync { end = newStart.addingTimeInterval(TimeInterval(focusedMinutes * 60)) }
        }
        .onChange(of: end) { _, newEnd in
            guard !syncing else { return }
            let minutes = Int(newEnd.timeIntervalSince(start) / 60)
            if minutes >= 1 {
                sync { setFocused(minutes) }
            } else {
                // End before start makes no sense; push it one minute past the start.
                sync {
                    setFocused(1)
                    end = start.addingTimeInterval(60)
                }
            }
        }
        .onChange(of: focusedText) { _, text in
            guard !syncing else { return }
            guard let minutes = Self.parseMinutes(text), minutes >= 1 else { return }
            sync {
                focusedMinutes = minutes
                end = start.addingTimeInterval(TimeInterval(minutes * 60))
            }
        }
        .confirmationDialog("Delete this block?", isPresented: $confirmDelete) {
            Button("Delete block", role: .destructive) {
                if let session { context.delete(session); try? context.save() }
                dismiss()
            }
        } message: {
            Text("\(Fmt.duration(focusedMinutes * 60)) of focus will be removed from your stats.")
        }
    }

    // MARK: Sections

    private var subjectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Subject")
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
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    label("Started")
                    datePicker($start)
                }
                VStack(alignment: .leading, spacing: 8) {
                    label("Ended")
                    datePicker($end)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                label("Focused time")
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        TextField("25", text: $focusedText)
                            .textFieldStyle(.plain)
                            .font(TypeStyle.mono(18))
                            .foregroundStyle(Ink.black)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("MIN")
                            .font(TypeStyle.label(11)).tracking(1).foregroundStyle(Ink.muted)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Ink.yellow)
                    .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))

                    ForEach([25, 45, 60, 90, 120], id: \.self) { m in
                        Button("\(m)") { focusedText = "\(m)" }
                            .buttonStyle(BrutalButtonStyle(fill: focusedMinutes == m ? Ink.yellow : Ink.white, size: 11, horizontalPadding: 10, verticalPadding: 7))
                    }
                }
                HStack(spacing: 12) {
                    Text("= \(Fmt.duration(focusedMinutes * 60)) FOCUSED")
                    if pausedSeconds >= 60 {
                        Text("· \(Fmt.duration(pausedSeconds)) PAUSED INSIDE THE BLOCK")
                    }
                    Text("· TYPE MINUTES, 1:30, OR 1.5H")
                }
                .font(TypeStyle.label(10)).tracking(1).foregroundStyle(Ink.muted)
            }
        }
    }

    private var intentionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Intention")
            TextField("What was this block for?", text: $intention)
                .textFieldStyle(.plain)
                .font(TypeStyle.body(15))
                .foregroundStyle(Ink.black)
                .padding(12)
                .background(Ink.white)
                .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Focus rating")
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
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Notes")
            TextField("What got done?", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...5)
                .font(TypeStyle.body(14))
                .foregroundStyle(Ink.black)
                .padding(12)
                .background(Ink.white)
                .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
        }
    }

    // MARK: Pieces

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
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

    // MARK: Logic

    private func sync(_ changes: () -> Void) {
        syncing = true
        changes()
        syncing = false
    }

    private func setFocused(_ minutes: Int) {
        focusedMinutes = minutes
        focusedText = "\(minutes)"
    }

    /// Accepts "90", "1:30", "1h 30m", "1.5h", "45m".
    static func parseMinutes(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        if let whole = Int(s) { return whole }
        if s.contains(":") {
            let parts = s.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            return h * 60 + m
        }
        if s.hasSuffix("h") || s.contains("h") {
            // "1.5h", "1h", "1h 30m", "1h30"
            let pieces = s.replacingOccurrences(of: "m", with: "").split(separator: "h", omittingEmptySubsequences: false)
            guard let hours = Double(pieces[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            var minutes = Int((hours * 60).rounded())
            if pieces.count > 1 {
                let rest = pieces[1].trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty, let m = Int(rest) { minutes += m }
            }
            return minutes
        }
        if s.hasSuffix("m"), let m = Int(s.dropLast().trimmingCharacters(in: .whitespaces)) { return m }
        if let fractional = Double(s) { return Int(fractional.rounded()) }
        return nil
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        syncing = true
        defer { syncing = false }
        if let session {
            start = session.startedAt
            end = session.endedAt
            setFocused(max(1, session.focusedSeconds / 60))
            subject = session.subject
            intention = session.intention
            rating = session.focusRating
            note = session.reflection
        } else {
            // Default to a 25 minute block that just ended, snapped to the minute.
            let now = Date()
            let snapped = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
            end = snapped
            start = snapped.addingTimeInterval(-25 * 60)
            setFocused(25)
            subject = defaultSubject
        }
    }

    private func save() {
        let seconds = min(focusedMinutes * 60, max(60, spanSeconds))
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
