import SwiftUI
import WriterblocksCore

/// One question, one line. Where the writer lives.
struct AskView: View {
    @Binding var project: Project
    /// Set by the web's "ask about these two". One-shot: answering it hands the
    /// deck back, rather than pinning the writer to one pair with no way out.
    @Binding var pairFocus: PairFocus?

    @State private var draft = ""
    @State private var focusStrandId: String?
    @FocusState private var fieldFocused: Bool

    /// Held rather than recomputed, because `draft` lives in this view: as a
    /// computed property this was re-dealing the whole deck on every keystroke,
    /// and the deck is about to get a great deal more work to do.
    @State private var dealt: DealtQuestion?

    private var stats: ProjectStats { OutlineBuilder.stats(project) }

    /// Which question is on screen. The template id alone is not enough — the
    /// same question asked about the next character is a new question, and the
    /// field should take focus again.
    private var questionIdentity: String? {
        dealt.map { "\($0.strand.id)::\($0.template.id)::\($0.about?.id ?? "")" }
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let dealt {
                Text(dealt.strand.label.uppercased())
                    .font(.caption)
                    .tracking(1.4)
                    .foregroundStyle(.secondary)

                Text(dealt.text)
                    .font(.system(size: 36, weight: .medium, design: .serif))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)

                if let hint = dealt.template.hint {
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }

                TextField("One sentence…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                    .frame(maxWidth: 620)
                    .focused($fieldFocused)
                    .onSubmit { answer(draft) }

                HStack(spacing: 10) {
                    Button("Add block") { answer(draft) }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Skip for now") {
                        project = Stories.skipQuestion(
                            project,
                            strandId: dealt.strand.id,
                            questionId: dealt.template.id,
                            aboutStrandId: dealt.about?.id
                        )
                        draft = ""
                        pairFocus = nil
                        refreshQuestion(force: true)
                    }
                    .buttonStyle(.link)

                    Button("Not sure yet") { answer("") }
                        .buttonStyle(.link)
                }

                Text("Skipping puts the question at the back of the deck. Nothing is ever lost.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                focusPicker
            } else {
                Text("Nothing left to ask.")
                    .font(.system(size: 30, weight: .medium, design: .serif))
                Text("Add a character or a place on the board and the questions start again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Visible accumulation is the antidote to "I have nothing to say".
            Text(counter)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .onAppear {
            refreshQuestion(force: true)
            fieldFocused = true
        }
        .onChange(of: questionIdentity) { _, _ in fieldFocused = true }
        // Answering and skipping refresh the question themselves, so the new one
        // is on screen in the same pass. This is the backstop for everything
        // else — a block edited on the board, a character renamed, a story
        // reopened — and it deliberately leaves the question alone while it is
        // still the question that was asked.
        .onChange(of: project) { _, _ in refreshQuestion() }
        .onChange(of: focusStrandId) { _, _ in refreshQuestion(force: true) }
        .onChange(of: pairFocus) { _, _ in refreshQuestion(force: true) }
        .onChange(of: project.strands.count) { _, _ in
            // A focused strand that was deleted must not keep filtering.
            if let id = focusStrandId, !project.strands.contains(where: { $0.id == id }) {
                focusStrandId = nil
            }
        }
    }

    /// Deal the next question. Unforced, this is a no-op while the question on
    /// screen is still askable — so adding a character from the answer field
    /// cannot replace the question the writer is part-way through answering.
    private func refreshQuestion(force: Bool = false) {
        if !force, let dealt, Deck.isStillDealable(project, dealt) { return }

        if let pairFocus {
            dealt = Deck.nextQuestion(
                project,
                focusStrandId: pairFocus.subject,
                focusAboutStrandId: pairFocus.about
            )
            return
        }
        dealt = Deck.nextQuestion(project, focusStrandId: focusStrandId)
    }

    private var focusable: [Strand] {
        project.strands
            .filter { $0.type == .character || $0.type == .setting }
            .sorted { $0.order < $1.order }
    }

    @ViewBuilder
    private var focusPicker: some View {
        if !focusable.isEmpty {
            Picker("Keep asking me about", selection: $focusStrandId) {
                Text("anything").tag(String?.none)
                ForEach(focusable) { strand in
                    Text(strand.label).tag(String?.some(strand.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)
        }
    }

    private var counter: String {
        let s = stats
        var parts = ["\(s.blocks) block\(s.blocks == 1 ? "" : "s")"]
        if s.characters > 0 { parts.append("\(s.characters) character\(s.characters == 1 ? "" : "s")") }
        if s.settings > 0 { parts.append("\(s.settings) place\(s.settings == 1 ? "" : "s")") }
        if s.scenes > 0 { parts.append("\(s.scenes) scene\(s.scenes == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private func answer(_ text: String) {
        guard let dealt else { return }
        project = Stories.applyAnswer(project, dealt, text)
        draft = ""
        // Being sent here from the web means "ask me about these two", not
        // "keep me on these two" — that is what the focus picker is for.
        pairFocus = nil
        refreshQuestion(force: true)
    }
}
