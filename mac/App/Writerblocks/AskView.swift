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

    /// Which row of the naming menu Return would take.
    @State private var highlighted = 0
    /// The draft as it stood when the menu was last dismissed or used. Typing
    /// more brings it back; backspacing does not — and it also stops a name
    /// containing a slash from reopening the menu the instant it is written in.
    @State private var dismissedAt: String?

    private var stats: ProjectStats { OutlineBuilder.stats(project) }

    // MARK: - Naming someone mid-sentence

    private var menuGroups: [MentionGroup]? {
        guard let token = Mentions.activeToken(in: draft) else { return nil }
        if let dismissedAt, draft.count <= dismissedAt.count { return nil }

        let groups = Mentions.candidates(project, token: token)
        return groups.isEmpty ? nil : groups
    }

    private var menuSubjects: [MentionSubject] {
        menuGroups?.flatMap(\.subjects) ?? []
    }

    private var highlightedSubject: MentionSubject? {
        let subjects = menuSubjects
        guard subjects.indices.contains(highlighted) else { return subjects.first }
        return subjects[highlighted]
    }

    private func moveHighlight(_ delta: Int) -> KeyPress.Result {
        let count = menuSubjects.count
        guard count > 0 else { return .ignored }
        highlighted = (highlighted + delta + count) % count
        return .handled
    }

    /// Put a name into the sentence, making the subject first if it is new.
    private func write(_ subject: MentionSubject) {
        if subject.isNew {
            // Immediately, so the name exists the moment it is written down.
            // The question above the field does not move: the deck only
            // re-deals when what is on screen has actually gone stale.
            project = Stories.addStrand(project, type: subject.type, label: subject.label)
        }

        draft = Mentions.insert(subject, into: draft)
        dismissedAt = draft
        highlighted = 0
        // Clicking a row moves focus off the field; put it back so the writer
        // can carry on typing. Setting true while already true does nothing, so
        // it has to go through false.
        fieldFocused = false
        fieldFocused = true
    }

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
                    .onSubmit {
                        // Return means "take the highlighted name" while the
                        // menu is up, and "answer the question" otherwise.
                        // Branching here rather than intercepting the key: this
                        // is the one submit path, and it always fires.
                        if let subject = highlightedSubject { write(subject) }
                        else { answer(draft) }
                    }
                    .onKeyPress(.upArrow) { moveHighlight(-1) }
                    .onKeyPress(.downArrow) { moveHighlight(1) }
                    .onKeyPress(.escape) {
                        guard menuGroups != nil else { return .ignored }
                        dismissedAt = draft
                        return .handled
                    }
                    .onChange(of: draft) { _, _ in highlighted = 0 }
                    // The buttons below are later siblings in this stack, so
                    // without this they paint straight over the menu.
                    .zIndex(1)
                    .overlay(alignment: .topLeading) {
                        if let groups = menuGroups {
                            MentionMenu(
                                groups: groups,
                                highlighted: highlighted,
                                onPick: write
                            )
                            .offset(y: 48)
                        }
                    }

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
        .onChange(of: questionIdentity) { _, _ in
            fieldFocused = true
            dismissedAt = nil
            highlighted = 0
        }
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
        dismissedAt = nil
        highlighted = 0
        refreshQuestion(force: true)
    }
}

/// The list of people and places that drops out of the answer field after a "/".
///
/// An overlay rather than a popover, and rows that are not buttons: both of
/// those would take first responder away from the field the writer is typing
/// in, and there would be nothing to hand it back.
private struct MentionMenu: View {
    let groups: [MentionGroup]
    let highlighted: Int
    let onPick: (MentionSubject) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(flattened.enumerated()), id: \.offset) { index, row in
                switch row {
                case .heading(let text):
                    Text(text.uppercased())
                        .font(.caption2)
                        .tracking(1.1)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, index == 0 ? 8 : 10)
                        .padding(.bottom, 3)

                case .subject(let subject, let position):
                    subjectRow(subject, isHighlighted: position == highlighted)
                }
            }
        }
        .padding(.bottom, 6)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private func subjectRow(_ subject: MentionSubject, isHighlighted: Bool) -> some View {
        HStack(spacing: 6) {
            if subject.isNew {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(title(for: subject))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // Said out loud rather than left to be discovered: some names
            // cannot be found again in a sentence however carefully they are
            // typed, so writing them connects nothing.
            if !subject.isMatchable {
                Text("won't link")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { onPick(subject) }
    }

    private func title(for subject: MentionSubject) -> String {
        guard subject.isNew else { return subject.label }
        return subject.type == .character
            ? "New character “\(subject.label)”"
            : "New place “\(subject.label)”"
    }

    private enum Row {
        case heading(String)
        /// The subject, and its index among subjects only — which is what the
        /// arrow keys count.
        case subject(MentionSubject, Int)
    }

    private var flattened: [Row] {
        var rows: [Row] = []
        var position = 0
        for group in groups {
            if let heading = group.heading { rows.append(.heading(heading)) }
            for subject in group.subjects {
                rows.append(.subject(subject, position))
                position += 1
            }
        }
        return rows
    }
}
