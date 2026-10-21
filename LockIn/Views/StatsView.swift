import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var allSessions: [FocusSession]
    @Query private var allSubjects: [Subject]
    @State private var range: StatsRange = .week
    @State private var anchor: Date = Date()
    @State private var editing: FocusSession?
    @State private var creating = false

    private let settings = AppSettings.shared

    private var rangeSessions: [FocusSession] {
        Stats.sessions(allSessions, in: Stats.interval(for: range, containing: anchor))
    }

    private var isCurrentPeriod: Bool { Stats.isCurrent(range, anchor: anchor) }

    private var bySubject: [SubjectTotal] { Stats.bySubject(rangeSessions) }

    private var buckets: [BucketTotal] {
        Stats.buckets(allSessions, range: range, anchor: anchor, subjectsPresent: bySubject)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                navigator
                tiles
                chartCard
                HStack(alignment: .top, spacing: 28) {
                    VStack(spacing: 28) {
                        categoryCard
                        breakdownCard
                    }
                    .frame(maxWidth: .infinity)
                    recentCard
                        .frame(width: 380)
                }
            }
            .padding(32)
        }
        .sheet(item: $editing) { session in
            SessionEditor(session: session)
        }
        .sheet(isPresented: $creating) {
            SessionEditor(session: nil)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR FOCUS")
                    .font(TypeStyle.display(36))
                    .tracking(-1)
                    .foregroundStyle(Ink.black)
                Text(Stats.rangeTitle(range, anchor: anchor).uppercased())
                    .font(TypeStyle.label(12))
                    .tracking(1.2)
                    .foregroundStyle(Ink.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(StatsRange.allCases) { r in
                    Button(r.rawValue) { range = r }
                        .buttonStyle(BrutalButtonStyle(fill: range == r ? Ink.yellow : Ink.white, size: 12, horizontalPadding: 16, verticalPadding: 9))
                }
            }
            Button {
                creating = true
            } label: {
                Label("Log a block", systemImage: "plus")
            }
            .buttonStyle(BrutalButtonStyle(fill: Ink.coral, size: 12, horizontalPadding: 16, verticalPadding: 9))
            .padding(.leading, 10)
        }
    }

    // MARK: Navigator

    private var navigator: some View {
        HStack(spacing: 10) {
            Button { anchor = Stats.shift(anchor, range: range, by: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(BrutalIconButtonStyle(fill: Ink.white, side: 34))
                .help("Previous \(range.rawValue.lowercased())")

            Text(Stats.rangeTitle(range, anchor: anchor).uppercased())
                .font(TypeStyle.label(13))
                .tracking(1)
                .foregroundStyle(Ink.black)
                .frame(minWidth: 220)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(isCurrentPeriod ? Ink.yellow : Ink.white)
                .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))

            Button { anchor = Stats.shift(anchor, range: range, by: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(BrutalIconButtonStyle(fill: Ink.white, side: 34))
                .disabled(isCurrentPeriod)
                .help("Next \(range.rawValue.lowercased())")

            if !isCurrentPeriod {
                Button(range == .day ? "Today" : (range == .week ? "This week" : "This month")) { anchor = Date() }
                    .buttonStyle(BrutalButtonStyle(fill: Ink.yellow, size: 11, horizontalPadding: 12, verticalPadding: 8))
            }

            Spacer()

            HStack(spacing: 8) {
                Text("JUMP TO")
                    .font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                DatePicker("", selection: $anchor, in: ...Date(), displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .padding(6)
                    .background(Ink.white)
                    .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                Text(range == .day ? "" : "(PICKS THE \(range.rawValue.uppercased()) THAT CONTAINS IT)")
                    .font(TypeStyle.label(9)).tracking(0.8).foregroundStyle(Ink.muted)
            }
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        let cal = Stats.calendar
        let daySessions = Stats.sessions(allSessions, in: Stats.interval(for: .day, containing: anchor))
        let weekSessions = Stats.sessions(allSessions, in: Stats.interval(for: .week, containing: anchor))
        let monthSessions = Stats.sessions(allSessions, in: Stats.interval(for: .month, containing: anchor))
        let streak = Stats.streak(allSessions)
        let best = Stats.bestStreak(allSessions)

        let dayLabel = cal.isDateInToday(anchor) ? "Today"
            : (cal.isDateInYesterday(anchor) ? "Yesterday" : anchor.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        let weekLabel = Stats.isCurrent(.week, anchor: anchor) ? "This week" : "Week of \(Stats.interval(for: .week, containing: anchor).start.formatted(.dateTime.month(.abbreviated).day()))"
        let monthLabel = Stats.isCurrent(.month, anchor: anchor) ? "This month" : anchor.formatted(.dateTime.month(.wide).year())

        return HStack(spacing: 20) {
            StatTile(label: dayLabel,
                     value: Fmt.duration(Stats.totalSeconds(daySessions)),
                     sub: "goal \(Fmt.duration(settings.dailyGoalMinutes * 60))",
                     fill: range == .day ? Ink.yellow : Ink.white, rotation: -1)
            StatTile(label: weekLabel,
                     value: Fmt.duration(Stats.totalSeconds(weekSessions)),
                     sub: "\(weekSessions.count) blocks",
                     fill: range == .week ? Ink.yellow : Ink.white)
            StatTile(label: monthLabel,
                     value: Fmt.duration(Stats.totalSeconds(monthSessions)),
                     sub: "\(monthSessions.count) blocks",
                     fill: range == .month ? Ink.yellow : Ink.white)
            StatTile(label: "Streak", value: "\(streak)d", sub: "best \(best)d", fill: Ink.coral, rotation: 1)
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        let totalSecs = Stats.totalSeconds(rangeSessions)
        let colors = Dictionary(uniqueKeysWithValues: bySubject.map { ($0.name, Color(hexString: $0.colorHex)) })
        let names = bySubject.map(\.name)

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionTitle(text: range == .day ? "Focus by hour" : "Focus by day")
                Text("\(Fmt.duration(totalSecs)) TOTAL")
                    .font(TypeStyle.label(11)).tracking(1).foregroundStyle(Ink.muted)
                if range != .day && totalSecs > 0 {
                    Text("· CLICK A BAR TO OPEN THAT DAY")
                        .font(TypeStyle.label(9)).tracking(1).foregroundStyle(Ink.muted)
                }
            }

            if totalSecs == 0 {
                Text("No focus logged in this \(range.rawValue.lowercased()) yet. Go lock in.")
                    .font(TypeStyle.body(14))
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(buckets) { row in
                    BarMark(
                        x: .value("When", row.bucketStart, unit: range == .day ? .hour : .day),
                        y: .value("Minutes", Double(row.seconds) / 60)
                    )
                    .foregroundStyle(by: .value("Subject", row.subjectName))
                }
                .chartForegroundStyleScale(domain: names, range: names.map { colors[$0] ?? Color(hex: 0xBDBDBD) })
                .chartXAxis {
                    AxisMarks(values: .stride(by: range == .day ? .hour : .day, count: range == .day ? 3 : (range == .month ? 5 : 1))) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Ink.black.opacity(0.25))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Stats.bucketLabel(date, range: range))
                                    .font(TypeStyle.label(10))
                                    .foregroundStyle(Ink.black)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Ink.black.opacity(0.25))
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(minutes >= 60 ? String(format: "%.0fh", minutes / 60) : "\(Int(minutes))m")
                                    .font(TypeStyle.label(10))
                                    .foregroundStyle(Ink.black)
                            }
                        }
                    }
                }
                .chartLegend(names.count > 1 ? .visible : .hidden)
                .chartLegend(position: .top, alignment: .leading, spacing: 12)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture().onEnded { value in
                                    guard range != .day, let plotFrame = proxy.plotFrame else { return }
                                    let origin = geo[plotFrame].origin
                                    let xInPlot = value.location.x - origin.x
                                    if let date: Date = proxy.value(atX: xInPlot) {
                                        jump(to: date)
                                    }
                                }
                            )
                    }
                }
                .frame(height: 260)
            }
        }
        .padding(22)
        .brutalCard(Ink.white)
    }

    /// Switch to the day view for the day that was clicked in the week/month chart.
    private func jump(to date: Date) {
        let interval = Stats.interval(for: range, containing: anchor)
        let day = Stats.calendar.startOfDay(for: date)
        guard day >= interval.start, day < interval.end, day <= Date() else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            anchor = day
            range = .day
        }
    }

    // MARK: By category

    private var categoryCard: some View {
        let rows = Stats.byCategory(rangeSessions, allSubjects: allSubjects)
        let maxSecs = max(1, rows.first?.seconds ?? 1)
        let total = max(1, Stats.totalSeconds(rangeSessions))

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionTitle(text: "By category")
                Text("ACROSS ALL SUBJECTS")
                    .font(TypeStyle.label(10)).tracking(1).foregroundStyle(Ink.muted)
            }
            if rows.isEmpty {
                Text("Nothing to group yet. Give your subjects a category (Math, CS, …) and they roll up here.")
                    .font(TypeStyle.body(14))
                    .foregroundStyle(Ink.muted)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 8) {
                            Rectangle().fill(Color(hexString: row.colorHex))
                                .frame(width: 14, height: 14)
                                .overlay(Rectangle().stroke(Ink.black, lineWidth: 2))
                            Text(row.name).font(TypeStyle.body(14)).foregroundStyle(Ink.black)
                        }
                        Spacer()
                        Text("\(Fmt.duration(row.seconds)) · \(Int(Double(row.seconds) / Double(total) * 100))%")
                            .font(TypeStyle.label(11)).tracking(0.5).foregroundStyle(Ink.muted)
                    }
                    BrutalProgressBar(progress: Double(row.seconds) / Double(maxSecs), fill: Color(hexString: row.colorHex), height: 14)
                }
            }
        }
        .padding(22)
        .brutalCard(Ink.yellow)
    }

    // MARK: Breakdown

    private var breakdownCard: some View {
        let rows = bySubject
        let maxSecs = max(1, rows.first?.seconds ?? 1)
        let total = max(1, Stats.totalSeconds(rangeSessions))

        return VStack(alignment: .leading, spacing: 18) {
            SectionTitle(text: "By subject")
            if rows.isEmpty {
                Text("Nothing to break down yet.")
                    .font(TypeStyle.body(14))
                    .foregroundStyle(Ink.muted)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 8) {
                            Rectangle().fill(Color(hexString: row.colorHex))
                                .frame(width: 14, height: 14)
                                .overlay(Rectangle().stroke(Ink.black, lineWidth: 2))
                            Text(row.name).font(TypeStyle.body(14)).foregroundStyle(Ink.black)
                        }
                        Spacer()
                        Text("\(Fmt.duration(row.seconds)) · \(row.sessions) BLOCK\(row.sessions == 1 ? "" : "S") · \(Int(Double(row.seconds) / Double(total) * 100))%")
                            .font(TypeStyle.label(11)).tracking(0.5).foregroundStyle(Ink.muted)
                    }
                    BrutalProgressBar(progress: Double(row.seconds) / Double(maxSecs), fill: Color(hexString: row.colorHex), height: 14)
                }
            }
        }
        .padding(22)
        .brutalCard(Ink.white)
    }

    // MARK: Recent

    private var recentCard: some View {
        let recent = Array(rangeSessions.prefix(8))
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(text: "Recent blocks")
                Text("CLICK TO EDIT")
                    .font(TypeStyle.label(9)).tracking(1).foregroundStyle(Ink.muted)
            }
            if recent.isEmpty {
                Text("No blocks in this range.")
                    .font(TypeStyle.body(14))
                    .foregroundStyle(Ink.muted)
            }
            ForEach(recent) { s in
                Button {
                    editing = s
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle()
                            .fill(s.subject?.color ?? Color(hex: 0xBDBDBD))
                            .frame(width: 6)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(s.subject?.name ?? "Unassigned")
                                    .font(TypeStyle.body(13))
                                    .foregroundStyle(Ink.black)
                                Spacer()
                                Text(Fmt.duration(s.focusedSeconds))
                                    .font(TypeStyle.label(12))
                                    .foregroundStyle(Ink.black)
                            }
                            if !s.intention.isEmpty {
                                Text(s.intention)
                                    .font(TypeStyle.body(12))
                                    .foregroundStyle(Ink.muted)
                                    .lineLimit(2)
                            }
                            HStack(spacing: 6) {
                                Text(s.startedAt.formatted(date: .abbreviated, time: .shortened).uppercased())
                                if s.focusRating > 0 { Text("· \(String(repeating: "★", count: s.focusRating))") }
                                if s.isManual { Text("· LOGGED") } else if !s.completed { Text("· ENDED EARLY") }
                            }
                            .font(TypeStyle.label(9))
                            .tracking(0.8)
                            .foregroundStyle(Ink.muted)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .brutalCard(Ink.lavender)
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let label: String
    let value: String
    let sub: String
    var fill: Color = Ink.white
    var rotation: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(TypeStyle.label(10))
                .tracking(1.2)
                .foregroundStyle(Ink.black.opacity(0.7))
            Text(value)
                .font(TypeStyle.display(34))
                .tracking(-1)
                .foregroundStyle(Ink.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(sub.uppercased())
                .font(TypeStyle.label(10))
                .tracking(1)
                .foregroundStyle(Ink.black.opacity(0.7))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalCard(fill, rotation: rotation)
    }
}
