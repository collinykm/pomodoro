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

/// Categories are free text so you can invent your own; these are the quick picks.
enum SubjectCategory {
    static let suggestions: [String] = [
        "Math", "Computer Science", "Science", "Engineering", "Writing", "Reading",
        "Languages", "History", "Business", "Economics", "Art & Design", "Music",
        "Health", "Personal", "Other",
    ]
    static let none = "Uncategorized"
}

@Model
final class Subject {
    var name: String
    var emoji: String
    var colorHex: String
    var kindRaw: String
    /// Free-text grouping across subjects, e.g. "Math" for Calculus + Linear Algebra.
    var category: String = ""
    /// Weekly focus goal in minutes; 0 means no goal.
    var weeklyGoalMinutes: Int
    var isArchived: Bool
    var sortOrder: Int
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \FocusSession.subject)
    var sessions: [FocusSession] = []

    init(name: String,
         emoji: String = "📚",
         colorHex: String = "FF6B6B",
         kind: SubjectKind = .course,
         category: String = "",
         weeklyGoalMinutes: Int = 0,
         sortOrder: Int = 0) {
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.category = category
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

    var categoryOrNone: String {
        let trimmed = category.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? SubjectCategory.none : trimmed
    }
}

// MARK: - FocusSession (one completed, abandoned, or hand-logged focus block)

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
    /// True when the block was typed in by hand rather than run on the timer.
    var isManual: Bool = false
    /// True once the user has edited the block after the fact.
    var wasEdited: Bool = false
    var subject: Subject?

    init(startedAt: Date,
         endedAt: Date,
         focusedSeconds: Int,
         plannedSeconds: Int,
         intention: String,
         completed: Bool,
         subject: Subject?,
         isManual: Bool = false) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.focusedSeconds = focusedSeconds
        self.plannedSeconds = plannedSeconds
        self.intention = intention
        self.completed = completed
        self.focusRating = 0
        self.reflection = ""
        self.isManual = isManual
        self.wasEdited = false
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

        let starters: [(name: String, emoji: String, color: Int, kind: SubjectKind, category: String)] = [
            ("Calculus",     "📐", 0, .course, "Math"),
            ("Intro to CS",  "💻", 1, .course, "Computer Science"),
            ("Side Project", "🛠️", 2, .project, "Computer Science"),
            ("Reading",      "📖", 3, .other, "Reading"),
        ]
        for (i, s) in starters.enumerated() {
            let subject = Subject(name: s.name,
                                  emoji: s.emoji,
                                  colorHex: String(format: "%06X", Ink.subjectPalette[s.color % Ink.subjectPalette.count]),
                                  kind: s.kind,
                                  category: s.category,
                                  weeklyGoalMinutes: s.kind == .course ? 180 : 0,
                                  sortOrder: i)
            context.insert(subject)
        }
        try? context.save()
    }
}
