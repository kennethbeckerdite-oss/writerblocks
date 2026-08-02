import SwiftUI
import WriterblocksCore

/// One question, one line. Where the writer lives.
struct AskView: View {
    @Binding var project: Project

    @State private var draft = ""
    @State private var focusStrandId: String?
    @FocusState private var fieldFocused: Bool

    private var dealt: DealtQuestion? {
        Deck.nextQuestion(project, focusStrandId: focusStrandId)
    }

    private var stats: ProjectStats { OutlineBuilder.stats(project) }

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
                            project, strandId: dealt.strand.id, questionId: dealt.template.id
                        )
                        draft = ""
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
        .onAppear { fieldFocused = true }
        .onChange(of: dealt?.template.id) { _, _ in fieldFocused = true }
        .onChange(of: project.strands.count) { _, _ in
            // A focused strand that was deleted must not keep filtering.
            if let id = focusStrandId, !project.strands.contains(where: { $0.id == id }) {
                focusStrandId = nil
            }
        }
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
    }
}
