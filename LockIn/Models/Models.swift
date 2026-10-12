import Foundation
import SwiftData
import SwiftUI

// MARK: - Subject (a class, a side project, or anything else you focus on)

enum SubjectKind: String, Codable, CaseIterable, Identifiable {
    case course = "Class"
    case project = "Project"
    case other = "Other"

    var id: String { rawValue }

    var plural: String {
        switch self {
        case .course: return "Classes"
        case .project: return "Projects"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .course: return "graduationcap.fill"
        case .project: return "hammer.fill"
        case .other: return "sparkles"
        }
    }
}

@Model
final class Subject {
    var name: String
    /// Optional short code shown as a tag, e.g. "CS 201" or "SIDE".
    var code: String
    var emoji: String
    var colorHex: String
    var kindRaw: String
    /// Weekly focus goal in minutes; 0 means no goal.
    var weeklyGoalMinutes: Int
    var isArchived: Bool
    var sortOrder: Int
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \FocusSession.subject)
    var sessions: [FocusSession] = []

    init(name: String,
         code: String = "",
         emoji: String = "📚",
         colorHex: String = "FF6B6B",
         kind: SubjectKind = .course,
         weeklyGoalMinutes: Int = 0,
         sortOrder: Int = 0) {
        self.name = name
        self.code = code
        self.emoji = emoji
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.weeklyGoalMinutes = weeklyGoalMinutes
        self.isArchived = false
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var kind: SubjectKind {
        get { SubjectKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var color: Color { Color(hexString: colorHex) }

    var displayCode: String {
        code.isEmpty ? String(name.prefix(3)).uppercased() : code.uppercased()
    }
}

// MARK: - FocusSession (one completed or abandoned focus block)

@Model
final class FocusSession {
    var startedAt: Date
    var endedAt: Date
    /// Seconds actually focused (pauses excluded).
    var focusedSeconds: Int
    /// Seconds that were planned when the session started.
    var plannedSeconds: Int
    var intention: String
    var completed: Bool
    /// 0 = not rated, otherwise 1...5.
    var focusRating: Int
    var reflection: String
    var subject: Subject?

    init(startedAt: Date,
         endedAt: Date,
         focusedSeconds: Int,
         plannedSeconds: Int,
         intention: String,
         completed: Bool,
         subject: Subject?) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.focusedSeconds = focusedSeconds
        self.plannedSeconds = plannedSeconds
        self.intention = intention
        self.completed = completed
        self.focusRating = 0
        self.reflection = ""
        self.subject = subject
    }
}

// MARK: - Seed data

enum SeedData {
    /// Creates a few starter subjects the first time the app launches so the UI is never empty.
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Subject>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        let starters: [(String, String, String, Int, SubjectKind)] = [
            ("Calculus",       "MATH 101", "📐", 0, .course),
            ("Intro to CS",    "CS 101",   "💻", 1, .course),
            ("Side Project",   "BUILD",    "🛠️", 2, .project),
            ("Reading",        "READ",     "📖", 3, .other),
        ]
        for (i, s) in starters.enumerated() {
            let subject = Subject(name: s.0,
                                  code: s.1,
                                  emoji: s.2,
                                  colorHex: String(format: "%06X", Ink.subjectPalette[s.3 % Ink.subjectPalette.count]),
                                  kind: s.4,
                                  weeklyGoalMinutes: s.4 == .course ? 180 : 0,
                                  sortOrder: i)
            context.insert(subject)
        }
        try? context.save()
    }
}
