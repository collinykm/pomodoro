import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var allSessions: [FocusSession]
    @Query private var allSubjects: [Subject]
    @State private var range: StatsRange = .week
    @State private var editing: FocusSession?
    @State private var creating = false

    private let settings = AppSettings.shared

    private var rangeSessions: [FocusSession] {
        Stats.sessions(allSessions, in: Stats.interval(for: range))
    }

    private var bySubject: [SubjectTotal] { Stats.bySubject(rangeSessions) }

    private var buckets: [BucketTotal] {
        Stats.buckets(allSessions, range: range, subjectsPresent: bySubject)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
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
                Text(Stats.rangeTitle(range).uppercased())
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

    // MARK: Tiles

    private var tiles: some View {
        let today = Stats.totalSeconds(Stats.today(allSessions))
        let week = Stats.totalSeconds(Stats.thisWeek(allSessions))
        let month = Stats.totalSeconds(Stats.thisMonth(allSessions))
        let streak = Stats.streak(allSessions)
        let best = Stats.bestStreak(allSessions)

        return HStack(spacing: 20) {
            StatTile(label: "Today", value: Fmt.duration(today), sub: "goal \(Fmt.duration(settings.dailyGoalMinutes * 60))", fill: Ink.yellow, rotation: -1)
            StatTile(label: "This week", value: Fmt.duration(week), sub: "\(Stats.thisWeek(allSessions).count) blocks", fill: Ink.white)
            StatTile(label: "This month", value: Fmt.duration(month), sub: "\(Stats.thisMonth(allSessions).count) blocks", fill: Ink.white)
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
                .frame(height: 260)
            }
        }
        .padding(22)
        .brutalCard(Ink.white)
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
