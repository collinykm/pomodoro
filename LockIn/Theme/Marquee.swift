import Foundation

/// Lines for the scrolling banner: a mix of motivational quotes and jokes, shuffled once per day
/// so the order is stable across launches but changes tomorrow.
enum Marquee {
    static let quotes: [String] = [
        "THE SECRET OF GETTING AHEAD IS GETTING STARTED",
        "DONE IS BETTER THAN PERFECT",
        "YOU DON'T HAVE TO BE GREAT TO START, BUT YOU HAVE TO START TO BE GREAT",
        "SMALL STEPS EVERY DAY",
        "FOCUS ON BEING PRODUCTIVE, NOT BUSY",
        "IT ALWAYS SEEMS IMPOSSIBLE UNTIL IT'S DONE",
        "THE BEST TIME TO START WAS YESTERDAY. THE NEXT BEST TIME IS NOW",
        "DISCIPLINE IS CHOOSING WHAT YOU WANT MOST OVER WHAT YOU WANT NOW",
        "ONE BLOCK AT A TIME",
        "YOU ARE WHAT YOU REPEATEDLY DO",
        "ACTION IS THE FOUNDATIONAL KEY TO ALL SUCCESS",
        "WELL BEGUN IS HALF DONE",
        "STUDY WHILE OTHERS ARE SLEEPING",
        "FUTURE YOU IS WATCHING. MAKE THEM PROUD",
        "A YEAR FROM NOW YOU'LL WISH YOU HAD STARTED TODAY",
        "MOTIVATION GETS YOU STARTED. HABIT KEEPS YOU GOING",
        "DON'T WATCH THE CLOCK. DO WHAT IT DOES. KEEP GOING",
        "THE EXPERT IN ANYTHING WAS ONCE A BEGINNER",
        "PROGRESS, NOT PERFECTION",
        "YOUR ONLY LIMIT IS YOUR MIND",
        "HARD WORK BEATS TALENT WHEN TALENT DOESN'T WORK HARD",
        "25 MINUTES. THAT'S IT. YOU CAN DO 25 MINUTES",
        "THE PAIN OF DISCIPLINE IS LIGHTER THAN THE PAIN OF REGRET",
        "START WHERE YOU ARE. USE WHAT YOU HAVE. DO WHAT YOU CAN",
        "EAT THE FROG FIRST",
        "TRUST THE PROCESS",
        "LOCK IN",
    ]

    static let jokes: [String] = [
        "I TOLD MY PROFESSOR I'D DO IT TOMORROW. THAT WAS THREE TOMORROWS AGO",
        "WHY DID THE STUDENT EAT HIS HOMEWORK? THE TEACHER SAID IT WAS A PIECE OF CAKE",
        "PROCRASTINATORS UNITE! …TOMORROW",
        "MY STUDY PLAN HAS A GREAT FIRST STEP: MAKE A STUDY PLAN",
        "I'M NOT LAZY, I'M ON ENERGY-SAVING MODE",
        "PARALLEL LINES HAVE SO MUCH IN COMMON. SHAME THEY'LL NEVER MEET",
        "THERE ARE 10 KINDS OF PEOPLE: THOSE WHO KNOW BINARY AND THOSE WHO DON'T",
        "WHY WAS SIX AFRAID OF SEVEN? BECAUSE SEVEN ATE NINE",
        "I HAVE A DEGREE IN PROCRASTINATION. STILL WAITING FOR IT TO ARRIVE",
        "MY BRAIN HAS TOO MANY TABS OPEN",
        "COFFEE: BECAUSE ADULTING IS HARD AND SO IS CALCULUS",
        "WHY DO PROGRAMMERS PREFER DARK MODE? BECAUSE LIGHT ATTRACTS BUGS",
        "A SQL QUERY WALKS INTO A BAR, SEES TWO TABLES, AND ASKS: CAN I JOIN YOU?",
        "I'D TELL YOU A CHEMISTRY JOKE BUT I KNOW I WOULDN'T GET A REACTION",
        "WHY DID THE MATH BOOK LOOK SAD? TOO MANY PROBLEMS",
        "GROUP PROJECTS: WHERE ONE PERSON LEARNS THE MATERIAL AND FOUR LEARN TO TRUST",
        "I WOULD STUDY HISTORY BUT THAT'S ALL IN THE PAST",
        "THE PAST, PRESENT AND FUTURE WALKED INTO A BAR. IT WAS TENSE",
        "MY ALARM CLOCK IS THE ONLY THING THAT GETS UP ON TIME",
        "DEADLINES: THE ORIGINAL PRODUCTIVITY APP",
        "I FINALLY FOUND MY MOTIVATION. IT WAS UNDER THE BED WITH THE SOCKS",
        "WHY DID THE PHYSICS STUDENT BREAK UP WITH BIOLOGY? NO CHEMISTRY",
        "99 LITTLE BUGS IN THE CODE, TAKE ONE DOWN, PATCH IT AROUND, 127 LITTLE BUGS IN THE CODE",
        "I STUDIED SO HARD LAST NIGHT. THE TEXTBOOK WAS A GREAT PILLOW",
        "A SEMICOLON WALKS INTO A BAR; THE BARTENDER SAYS, ANOTHER PAUSE?",
        "WHY DON'T SCIENTISTS TRUST ATOMS? THEY MAKE UP EVERYTHING",
        "LIBRARY VOLUME: ONE PAGE TURN AND THE WHOLE ROOM KNOWS",
    ]

    /// Alternates quotes and jokes in a daily-stable shuffled order.
    static func lineup(for date: Date = Date(), count: Int = 10) -> [String] {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        var rng = SeededGenerator(seed: UInt64(day) &* 2_654_435_761)
        let q = quotes.shuffled(using: &rng)
        let j = jokes.shuffled(using: &rng)
        var out: [String] = []
        var qi = 0, ji = 0
        while out.count < count && (qi < q.count || ji < j.count) {
            if qi < q.count { out.append(q[qi]); qi += 1 }
            if out.count < count, ji < j.count { out.append(j[ji]); ji += 1 }
        }
        return out
    }
}

/// Tiny deterministic generator so the banner order is the same all day.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
}
