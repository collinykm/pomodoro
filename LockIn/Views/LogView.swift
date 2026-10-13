import SwiftUI
import SwiftData

/// Every focus block, newest first, grouped by day. Add blocks by hand, fix or delete existing ones.
struct LogView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerEngine.self) private var engine
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var allSessions: [FocusSession]

    @State private var editing: FocusSession?
    @State private var creating = false
    @State private var pendingDelete: FocusSession?
    @State private var daysShown = 14

    private var groups: [(day: Date, sessions: [FocusSession])] {
        let cal = Calendar.current
        var map: [Date: [FocusSession]] = [:]
        for s in allSessions {
            map[cal.startOfDay(for: s.startedAt), default: []].append(s)
        }
        return map.keys.sorted(by: >).prefix(daysShown).map { ($0, map[$0]!.sorted { $0.startedAt > $1.startedAt }) }
    }

    private var hasMore: Bool {
        Set(allSessions.map { Calendar.current.startOfDay(for: $0.startedAt) }).count > daysShown
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FOCUS LOG")
                            .font(TypeStyle.display(36))
                            .tracking(-1)
                            .foregroundStyle(Ink.black)
                        Text("Forgot to start the timer, or forgot to pause it? Add the block or fix the one that's wrong. Everything here feeds the stats.")
                            .font(TypeStyle.body(14))
                            .foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    Button {
                        creating = true
                    } label: {
                        Label("Log a block", systemImage: "plus")
                    }
                    .buttonStyle(BrutalButtonStyle(fill: Ink.coral))
                }

                if allSessions.isEmpty {
                    Text("No blocks yet. Run the timer, or log one by hand.")
                        .font(TypeStyle.body(15))
                        .foregroundStyle(Ink.black)
                        .padding(22)
                        .frame(maxWidth: .infinity)
                        .brutalCard(Ink.white)
                }

                ForEach(groups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(dayTitle(group.day).uppercased())
                                .font(TypeStyle.label(12))
                                .tracking(1.2)
                                .foregroundStyle(Ink.black)
                            Spacer()
                            Tag(text: "\(Fmt.duration(Stats.totalSeconds(group.sessions))) · \(group.sessions.count) BLOCK\(group.sessions.count == 1 ? "" : "S")", fill: Ink.white)
                        }
                        ForEach(group.sessions) { session in
                            SessionRow(session: session,
                                       onEdit: { editing = session },
                                       onDelete: { pendingDelete = session })
                        }
                    }
                }

                if hasMore {
                    Button("Show more days") { daysShown += 14 }
                        .buttonStyle(BrutalButtonStyle(fill: Ink.white, size: 12))
                }
            }
            .padding(32)
        }
        .sheet(isPresented: $creating) {
            SessionEditor(session: nil, defaultSubject: engine.selectedSubject)
        }
        .sheet(item: $editing) { session in
            SessionEditor(session: session)
        }
        .confirmationDialog("Delete this block?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete block", role: .destructive) {
                if let s = pendingDelete { context.delete(s); try? context.save() }
                pendingDelete = nil
            }
        } message: {
            if let s = pendingDelete {
                Text("\(Fmt.duration(s.focusedSeconds)) of focus will be removed from your stats.")
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(day, equalTo: Date(), toGranularity: .year) ? "EEEE, MMM d" : "EEE, MMM d, yyyy"
        return f.string(from: day)
    }
}

/// One block in the log. Click anywhere on the row to edit it.
struct SessionRow: View {
    let session: FocusSession
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: session.startedAt)) – \(f.string(from: session.endedAt))"
    }

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 14) {
                Rectangle()
                    .fill(session.subject?.color ?? Color(hex: 0xBDBDBD))
                    .frame(width: 8)
                    .overlay(Rectangle().stroke(Ink.black, lineWidth: 2))

                Text(session.subject?.emoji ?? "·")
                    .font(.system(size: 20))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(session.subject?.name ?? "Unassigned")
                            .font(TypeStyle.heading(15))
                            .foregroundStyle(Ink.black)
                        if let cat = session.subject?.category, !cat.isEmpty {
                            Tag(text: cat, fill: Ink.paper)
                        }
                        if session.isManual { Tag(text: "Logged", fill: Ink.white) }
                        else if session.wasEdited { Tag(text: "Edited", fill: Ink.white) }
                        if !session.completed && !session.isManual { Tag(text: "Ended early", fill: Ink.paper) }
                    }
                    if !session.intention.isEmpty {
                        Text(session.intention)
                            .font(TypeStyle.body(13))
                            .foregroundStyle(Ink.muted)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(timeRange.uppercased())
                        if session.focusRating > 0 { Text("· \(String(repeating: "★", count: session.focusRating))") }
                    }
                    .font(TypeStyle.label(10))
                    .tracking(0.8)
                    .foregroundStyle(Ink.muted)
                }

                Spacer()

                Text(Fmt.duration(session.focusedSeconds))
                    .font(TypeStyle.display(22))
                    .tracking(-0.5)
                    .foregroundStyle(Ink.black)

                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Ink.black)
                        .frame(width: 32, height: 32)
                        .background(Ink.white)
                        .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Ink.black)
                            .frame(width: 32, height: 32)
                            .background(Ink.white)
                            .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete block")
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .brutalCard(Ink.white, shadow: 4)
    }
}
