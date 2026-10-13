import SwiftUI
import SwiftData

/// Shown right after a focus block ends. Mirrors Session's reflection step:
/// rate your focus, jot what you got done, move on.
struct ReflectionSheet: View {
    @Bindable var session: FocusSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var rating: Int = 0
    @State private var note: String = ""

    private let faces = ["😵‍💫", "😕", "😐", "🙂", "🔥"]
    private let labels = ["Scattered", "Meh", "Okay", "Good", "Locked in"]

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.completed ? "BLOCK DONE." : "BLOCK ENDED.")
                        .font(TypeStyle.display(34))
                        .tracking(-1)
                        .foregroundStyle(Ink.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .brutalCard(Ink.yellow, border: 3, shadow: 6, rotation: -1.5)
                    Spacer()
                    Tag(text: Fmt.duration(session.focusedSeconds), fill: Ink.white)
                    if let subject = session.subject {
                        Tag(text: "\(subject.emoji) \(subject.name)", fill: subject.color)
                    }
                }

                if !session.intention.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR INTENTION")
                            .font(TypeStyle.label(10)).tracking(1.2).foregroundStyle(Ink.muted)
                        Text(session.intention)
                            .font(TypeStyle.body(16))
                            .foregroundStyle(Ink.black)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .brutalCard(Ink.white, shadow: 4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "How was your focus?")
                    HStack(spacing: 10) {
                        ForEach(0..<5, id: \.self) { i in
                            Button {
                                rating = i + 1
                            } label: {
                                VStack(spacing: 4) {
                                    Text(faces[i]).font(.system(size: 26))
                                    Text(labels[i].uppercased())
                                        .font(TypeStyle.label(9)).tracking(0.5)
                                        .foregroundStyle(Ink.black)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background {
                                    ZStack {
                                        if rating == i + 1 { Rectangle().fill(Ink.black).offset(x: 4, y: 4) }
                                        Rectangle().fill(rating == i + 1 ? Ink.coral : Ink.white)
                                            .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "What did you get done?")
                    TextField("One line. What moved forward, what did you learn, what's next?", text: $note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                        .font(TypeStyle.body(15))
                        .foregroundStyle(Ink.black)
                        .padding(14)
                        .background(Ink.white)
                        .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                }

                HStack {
                    Button("Skip") { dismiss() }
                        .buttonStyle(BrutalButtonStyle(fill: Ink.white))
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save reflection") { save() }
                        .buttonStyle(BrutalButtonStyle(fill: Ink.coral))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(32)
        }
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(.light)
        .onAppear {
            rating = session.focusRating
            note = session.reflection
        }
    }

    private func save() {
        session.focusRating = rating
        session.reflection = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        dismiss()
    }
}
