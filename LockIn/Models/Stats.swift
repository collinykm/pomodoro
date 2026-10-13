import Foundation

enum StatsRange: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    var id: String { rawValue }
}

struct SubjectTotal: Identifiable {
    let id: String          // subject name (or "Unassigned")
    let name: String
    let colorHex: String
    let seconds: Int
    let sessions: Int
}

struct BucketTotal: Identifiable {
    var id: String { "\(bucketStart.timeIntervalSince1970)-\(subjectName)" }
    let bucketStart: Date
    let subjectName: String
    let colorHex: String
    let seconds: Int
}

/// Pure functions over `FocusSession` arrays. Views fetch with @Query and hand the rows here.
enum Stats {
    static let calendar = Calendar.current

    // MARK: Ranges

    static func interval(for range: StatsRange, containing date: Date = Date()) -> DateInterval {
        switch range {
        case .day:
            return calendar.dateInterval(of: .day, for: date)!
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)!
        case .month:
            return calendar.dateInterval(of: .month, for: date)!
        }
    }

    static func sessions(_ all: [FocusSession], in interval: DateInterval) -> [FocusSession] {
        all.filter { interval.contains($0.startedAt) }
    }

    static func totalSeconds(_ sessions: [FocusSession]) -> Int {
        sessions.reduce(0) { $0 + $1.focusedSeconds }
    }

    static func today(_ all: [FocusSession]) -> [FocusSession] {
        sessions(all, in: interval(for: .day))
    }

    static func thisWeek(_ all: [FocusSession]) -> [FocusSession] {
        sessions(all, in: interval(for: .week))
    }

    static func thisMonth(_ all: [FocusSession]) -> [FocusSession] {
        sessions(all, in: interval(for: .month))
    }

    // MARK: Per-subject

    static func bySubject(_ sessions: [FocusSession]) -> [SubjectTotal] {
        var map: [String: (name: String, color: String, secs: Int, count: Int)] = [:]
        for s in sessions {
            let name = s.subject?.name ?? "Unassigned"
            let color = s.subject?.colorHex ?? "BDBDBD"
            var entry = map[name] ?? (name, color, 0, 0)
            entry.secs += s.focusedSeconds
            entry.count += 1
            map[name] = entry
        }
        return map.values
            .map { SubjectTotal(id: $0.name, name: $0.name, colorHex: $0.color, seconds: $0.secs, sessions: $0.count) }
            .sorted { $0.seconds > $1.seconds }
    }

    // MARK: Per-category (Math across all math classes, etc.)

    static func byCategory(_ sessions: [FocusSession], allSubjects: [Subject]) -> [SubjectTotal] {
        let colors = categoryColors(allSubjects)
        var map: [String: (secs: Int, count: Int)] = [:]
        for s in sessions {
            let name = s.subject?.categoryOrNone ?? SubjectCategory.none
            var entry = map[name] ?? (0, 0)
            entry.secs += s.focusedSeconds
            entry.count += 1
            map[name] = entry
        }
        return map
            .map { SubjectTotal(id: $0.key, name: $0.key, colorHex: colors[$0.key] ?? "BDBDBD", seconds: $0.value.secs, sessions: $0.value.count) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// Stable color per category: alphabetical order over every category in use, mapped onto the
    /// fixed palette. Uncategorized is always gray.
    static func categoryColors(_ subjects: [Subject]) -> [String: String] {
        let names = Set(subjects.map(\.categoryOrNone)).subtracting([SubjectCategory.none]).sorted()
        var out: [String: String] = [SubjectCategory.none: "BDBDBD"]
        for (i, name) in names.enumerated() {
            out[name] = i < Ink.subjectPalette.count ? String(format: "%06X", Ink.subjectPalette[i]) : "BDBDBD"
        }
        return out
    }

    // MARK: Time buckets for charts

    /// Day → hourly buckets, week → daily buckets, month → daily buckets. Every bucket is present
    /// (zero rows are emitted for empty buckets so the axis stays complete).
    static func buckets(_ all: [FocusSession], range: StatsRange, anchor: Date = Date(), subjectsPresent: [SubjectTotal]) -> [BucketTotal] {
        let interval = interval(for: range, containing: anchor)
        let rows = sessions(all, in: interval)
        let component: Calendar.Component = range == .day ? .hour : .day

        var starts: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            starts.append(cursor)
            cursor = calendar.date(byAdding: component, value: 1, to: cursor)!
        }

        var totals: [Date: [String: Int]] = [:]
        for s in rows {
            let start = calendar.dateInterval(of: component, for: s.startedAt)!.start
            let name = s.subject?.name ?? "Unassigned"
            totals[start, default: [:]][name, default: 0] += s.focusedSeconds
        }

        let names = subjectsPresent.isEmpty ? ["Unassigned"] : subjectsPresent.map(\.name)
        let colors = Dictionary(uniqueKeysWithValues: subjectsPresent.map { ($0.name, $0.colorHex) })

        var out: [BucketTotal] = []
        for start in starts {
            for name in names {
                out.append(BucketTotal(bucketStart: start,
                                       subjectName: name,
                                       colorHex: colors[name] ?? "BDBDBD",
                                       seconds: totals[start]?[name] ?? 0))
            }
        }
        return out
    }

    // MARK: Streak

    /// Consecutive days (ending today or yesterday) with at least one logged focus block.
    static func streak(_ all: [FocusSession]) -> Int {
        let days = Set(all.map { calendar.startOfDay(for: $0.startedAt) })
        guard !days.isEmpty else { return 0 }
        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }

    /// Longest run of consecutive days with focus, all time.
    static func bestStreak(_ all: [FocusSession]) -> Int {
        let days = Set(all.map { calendar.startOfDay(for: $0.startedAt) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous), calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    // MARK: Labels

    static func bucketLabel(_ date: Date, range: StatsRange) -> String {
        let f = DateFormatter()
        switch range {
        case .day: f.dateFormat = "ha"
        case .week: f.dateFormat = "EEE"
        case .month: f.dateFormat = "d"
        }
        return f.string(from: date)
    }

    /// Moves an anchor date by whole days, weeks or months.
    static func shift(_ anchor: Date, range: StatsRange, by steps: Int) -> Date {
        let component: Calendar.Component
        switch range {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        return calendar.date(byAdding: component, value: steps, to: anchor) ?? anchor
    }

    static func isCurrent(_ range: StatsRange, anchor: Date) -> Bool {
        interval(for: range, containing: anchor).contains(Date())
    }

    static func rangeTitle(_ range: StatsRange, anchor: Date = Date()) -> String {
        let f = DateFormatter()
        let interval = interval(for: range, containing: anchor)
        switch range {
        case .day:
            f.dateFormat = "EEEE, MMM d"
            return f.string(from: interval.start)
        case .week:
            f.dateFormat = "MMM d"
            let end = calendar.date(byAdding: .day, value: -1, to: interval.end)!
            return "\(f.string(from: interval.start)) – \(f.string(from: end))"
        case .month:
            f.dateFormat = "MMMM yyyy"
            return f.string(from: interval.start)
        }
    }
}
