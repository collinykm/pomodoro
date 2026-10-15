import SwiftUI
import SwiftData

/// A horizontal timeline of one day's focus blocks, with a week strip to hop between days.
/// Blocks are laid out by wall-clock time; click one to edit it.
struct DayTimelineCard: View {
    let allSessions: [FocusSession]
    /// Start of the focus block currently running, if any, so it can be drawn live.
    var activeStart: Date? = nil
    var activeColor: Color = Ink.yellow
    let onEdit: (FocusSession) -> Void

    @State private var day: Date = Calendar.current.startOfDay(for: Date())
    @State private var now: Date = Date()

    private let cal = Calendar.current
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var daySessions: [FocusSession] {
        let interval = cal.dateInterval(of: .day, for: day)!
        return allSessions.filter { interval.contains($0.startedAt) }.sorted { $0.startedAt < $1.startedAt }
    }

    private var isToday: Bool { cal.isDateInToday(day) }

    private var weekDays: [Date] {
        let week = cal.dateInterval(of: .weekOfYear, for: day)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            weekStrip
            timeline
        }
        .padding(22)
        .brutalCard(Ink.white)
        .onReceive(ticker) { now = $0 }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            SectionTitle(text: "Timeline")
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(BrutalIconButtonStyle(fill: Ink.white, side: 30))
            Text(dayTitle.uppercased())
                .font(TypeStyle.label(12))
                .tracking(1)
                .foregroundStyle(Ink.black)
                .frame(minWidth: 150)
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(BrutalIconButtonStyle(fill: Ink.white, side: 30))
                .disabled(isToday)
            if !isToday {
                Button("Today") { day = cal.startOfDay(for: Date()) }
                    .buttonStyle(BrutalButtonStyle(fill: Ink.yellow, size: 10, horizontalPadding: 10, verticalPadding: 6))
            }
            Tag(text: "\(Fmt.duration(Stats.totalSeconds(daySessions))) · \(daySessions.count) BLOCK\(daySessions.count == 1 ? "" : "S")", fill: Ink.paper)
        }
    }

    private var dayTitle: String {
        if isToday { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: day)
    }

    private func shift(_ days: Int) {
        guard let next = cal.date(byAdding: .day, value: days, to: day) else { return }
        guard next <= cal.startOfDay(for: Date()) else { return }
        day = next
    }

    // MARK: Week strip

    private var weekStrip: some View {
        HStack(spacing: 8) {
            ForEach(weekDays, id: \.self) { d in
                let secs = Stats.totalSeconds(allSessions.filter { cal.isDate($0.startedAt, inSameDayAs: d) })
                let selected = cal.isDate(d, inSameDayAs: day)
                let future = d > cal.startOfDay(for: Date())
                Button {
                    if !future { day = d }
                } label: {
                    VStack(spacing: 3) {
                        Text(d.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(TypeStyle.label(9)).tracking(0.8)
                        Text(d.formatted(.dateTime.day()))
                            .font(TypeStyle.heading(16))
                        Text(secs == 0 ? "–" : Fmt.duration(secs))
                            .font(TypeStyle.label(9))
                    }
                    .foregroundStyle(Ink.black.opacity(future ? 0.35 : 1))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        ZStack {
                            if selected { Rectangle().fill(Ink.black).offset(x: 3, y: 3) }
                            Rectangle().fill(selected ? Ink.yellow : (cal.isDateInToday(d) ? Ink.paper : Ink.white))
                                .overlay(Rectangle().stroke(Ink.black, lineWidth: selected ? 3 : 2))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(future)
            }
        }
    }

    // MARK: Timeline

    /// Points per hour. Fixed, so the strip always spans the full day and scrolls sideways.
    private let hourWidth: CGFloat = 110

    /// The hour to scroll into view first: a little before the current time today, otherwise a
    /// little before the day's first block.
    private var anchorHour: Int {
        if isToday { return max(0, cal.component(.hour, from: now) - 4) }
        if let first = daySessions.first { return max(0, cal.component(.hour, from: first.startedAt) - 1) }
        return 8
    }

    private var timeline: some View {
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let span = dayEnd.timeIntervalSince(dayStart)
        let width = hourWidth * 24
        let lanes = laneAssignments(daySessions)
        let laneCount = max(1, (lanes.values.max() ?? 0) + 1)
        let laneHeight: CGFloat = 52
        let laneGap: CGFloat = 6
        let x: (Date) -> CGFloat = { date in
            let t = date.timeIntervalSince(dayStart) / span
            return CGFloat(min(1, max(0, t))) * width
        }

        return ScrollViewReader { scroller in
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Hour grid + labels (each hour gets an id so the strip can scroll to it)
                    ForEach(0...24, id: \.self) { hour in
                        let hx = CGFloat(hour) * hourWidth
                        Rectangle()
                            .fill(Ink.black.opacity(hour % 6 == 0 ? 0.6 : 0.2))
                            .frame(width: 1)
                            .offset(x: hx)
                            .id(hour)
                        if hour < 24 {
                            Text(hourLabel(hour))
                                .font(TypeStyle.label(9))
                                .tracking(0.5)
                                .foregroundStyle(Ink.muted)
                                .offset(x: hx + 4, y: CGFloat(laneCount) * (laneHeight + laneGap) + 2)
                        }
                    }

                    // Blocks
                    ForEach(daySessions) { s in
                        let lane = lanes[s.persistentModelID] ?? 0
                        let x0 = x(s.startedAt)
                        let x1 = max(x(s.endedAt), x0 + 6)
                        Button {
                            onEdit(s)
                        } label: {
                            TimelineBlock(session: s, width: x1 - x0)
                                .frame(width: x1 - x0, height: laneHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: x0, y: CGFloat(lane) * (laneHeight + laneGap))
                        .help(tooltip(s))
                    }

                    // Live block
                    if isToday, let activeStart {
                        let x0 = x(activeStart)
                        let x1 = max(x(now), x0 + 6)
                        Rectangle()
                            .fill(activeColor)
                            .overlay(Rectangle().stroke(Ink.black, style: StrokeStyle(lineWidth: 2.5, dash: [5, 3])))
                            .overlay(alignment: .leading) {
                                Text("NOW")
                                    .font(TypeStyle.label(9)).tracking(1).foregroundStyle(Ink.black)
                                    .padding(.leading, 6)
                            }
                            .frame(width: x1 - x0, height: laneHeight)
                            .offset(x: x0, y: 0)
                            .allowsHitTesting(false)
                    }

                    // Now marker
                    if isToday {
                        Rectangle()
                            .fill(Ink.coral)
                            .frame(width: 3, height: CGFloat(laneCount) * (laneHeight + laneGap) - laneGap)
                            .offset(x: x(now) - 1.5)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: width, height: CGFloat(laneCount) * (laneHeight + laneGap) + 18, alignment: .topLeading)
            }
            .onAppear { scroller.scrollTo(anchorHour, anchor: .leading) }
            .onChange(of: day) { _, _ in scroller.scrollTo(anchorHour, anchor: .leading) }
        }
        .frame(height: CGFloat(laneCount) * (laneHeight + laneGap) + 32)
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 || hour == 24 { return "12AM" }
        if hour == 12 { return "12PM" }
        return hour < 12 ? "\(hour)AM" : "\(hour - 12)PM"
    }

    private func tooltip(_ s: FocusSession) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        var t = "\(s.subject?.name ?? "Unassigned") · \(f.string(from: s.startedAt)) – \(f.string(from: s.endedAt)) · \(Fmt.duration(s.focusedSeconds))"
        if !s.intention.isEmpty { t += "\n\(s.intention)" }
        return t
    }

    /// Greedy lane packing so overlapping blocks stack instead of drawing on top of each other.
    private func laneAssignments(_ sessions: [FocusSession]) -> [PersistentIdentifier: Int] {
        var laneEnds: [Date] = []
        var out: [PersistentIdentifier: Int] = [:]
        for s in sessions {
            if let free = laneEnds.firstIndex(where: { $0 <= s.startedAt }) {
                laneEnds[free] = s.endedAt
                out[s.persistentModelID] = free
            } else {
                laneEnds.append(s.endedAt)
                out[s.persistentModelID] = laneEnds.count - 1
            }
        }
        return out
    }
}

private struct TimelineBlock: View {
    let session: FocusSession
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(session.subject?.color ?? Color(hex: 0xBDBDBD))
                .overlay(Rectangle().stroke(Ink.black, lineWidth: 2.5))
            if width > 60 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.startedAt.formatted(date: .omitted, time: .shortened).uppercased())
                        .font(TypeStyle.label(8)).tracking(0.5)
                        .foregroundStyle(Ink.black.opacity(0.7))
                    Text(session.subject.map { "\($0.emoji) \($0.name)" } ?? "Unassigned")
                        .font(TypeStyle.label(11))
                        .foregroundStyle(Ink.black)
                        .lineLimit(1)
                }
                .padding(6)
            }
            if width > 36 {
                Text(Fmt.duration(session.focusedSeconds))
                    .font(TypeStyle.label(9))
                    .foregroundStyle(Ink.black)
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .clipped()
    }
}
