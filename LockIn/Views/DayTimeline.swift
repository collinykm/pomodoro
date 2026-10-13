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

    /// Hours shown. Always covers 8am–6pm, stretched to include every block and the current time.
    private var hourRange: (start: Int, end: Int) {
        var start = 8, end = 18
        let blocks = daySessions
        if let first = blocks.first {
            start = min(start, cal.component(.hour, from: first.startedAt))
        }
        for s in blocks {
            let endHour = cal.component(.hour, from: s.endedAt) + 1
            let sameDay = cal.isDate(s.endedAt, inSameDayAs: day)
            end = max(end, sameDay ? endHour : 24)
        }
        if isToday {
            let h = cal.component(.hour, from: now)
            end = max(end, h + 1)
            if let activeStart { start = min(start, cal.component(.hour, from: activeStart)) }
        }
        return (max(0, start), min(24, max(end, start + 1)))
    }

    private var timeline: some View {
        let range = hourRange
        let dayStart = cal.startOfDay(for: day)
        let windowStart = cal.date(byAdding: .hour, value: range.start, to: dayStart)!
        let windowEnd = cal.date(byAdding: .hour, value: range.end, to: dayStart)!
        let span = windowEnd.timeIntervalSince(windowStart)
        let lanes = laneAssignments(daySessions)
        let laneCount = max(1, (lanes.values.max() ?? 0) + 1)
        let laneHeight: CGFloat = 52
        let laneGap: CGFloat = 6

        return GeometryReader { geo in
            let width = geo.size.width
            let x: (Date) -> CGFloat = { date in
                let t = date.timeIntervalSince(windowStart) / span
                return CGFloat(min(1, max(0, t))) * width
            }

            ZStack(alignment: .topLeading) {
                // Hour grid + labels
                ForEach(range.start...range.end, id: \.self) { hour in
                    let hx = CGFloat(hour - range.start) / CGFloat(range.end - range.start) * width
                    Rectangle()
                        .fill(Ink.black.opacity(hour == range.start || hour == range.end ? 0.6 : 0.2))
                        .frame(width: 1)
                        .offset(x: hx)
                    if shouldLabel(hour, totalHours: range.end - range.start, width: width) {
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
        }
        .frame(height: CGFloat(laneCount) * (laneHeight + laneGap) + 18)
    }

    private func shouldLabel(_ hour: Int, totalHours: Int, width: CGFloat) -> Bool {
        let perHour = width / CGFloat(max(1, totalHours))
        let every = perHour > 70 ? 1 : (perHour > 36 ? 2 : 3)
        return (hour - hourRange.start) % every == 0 && hour != hourRange.end
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
