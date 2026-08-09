import SwiftUI
import WriterblocksCore

/// The front door: one question, and your stories underneath it.
struct HomeView: View {

    /// Bumped by ⌘N to put the cursor back in the field.
    let focusToken: Int
    /// Routing is the caller's job — this view never opens a window.
    let onOpen: (URL) -> Void

    @State private var logline = ""
    @State private var stories: [StoryCard] = []
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                question
                    .padding(.top, stories.isEmpty ? 120 : 56)
                    .padding(.bottom, stories.isEmpty ? 0 : 48)

                if !stories.isEmpty {
                    grid
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            reload()
            fieldFocused = true
        }
        .onChange(of: focusToken) { _, _ in fieldFocused = true }
        // Returning from a story should show its updated card.
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in reload() }
    }

    // MARK: - The question

    private var question: some View {
        VStack(spacing: 14) {
            Text("What's the logline?")
                .font(.system(size: 40, weight: .medium, design: .serif))
                .multilineTextAlignment(.center)

            Text("One sentence, and it's allowed to be bad. You can fix it later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("One sentence…", text: $logline)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                )
                .frame(maxWidth: 560)
                .focused($fieldFocused)
                .onSubmit(start)

            Button("Start the story", action: start)
                .buttonStyle(.borderedProminent)
                .disabled(logline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - The stories

    private var grid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your stories")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open…", action: openPanel)
                    .buttonStyle(.link)
            }
            .padding(.horizontal, 32)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(stories) { story in
                    StoryCardView(story: story, onOpen: { onOpen(story.url) }, onChanged: reload)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Actions

    private func start() {
        let trimmed = logline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let url = try StoryLibrary.create(logline: trimmed)
            logline = ""
            error = nil
            onOpen(url)
        } catch {
            self.error = "Could not create the story: \(error.localizedDescription)"
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.writerblocksStory, .json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            onOpen(url)
        }
    }

    private func reload() {
        stories = StoryLibrary.stories()
    }
}

/// One story on the home screen. The card face stays clean; everything except
/// opening lives behind the ⋯ menu.
private struct StoryCardView: View {
    let story: StoryCard
    let onOpen: () -> Void
    let onChanged: () -> Void

    @State private var hovering = false
    @State private var confirmingDelete = false
    @State private var renaming = false
    @State private var draftTitle = ""

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(story.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    menu.opacity(hovering ? 1 : 0)
                }

                Text(story.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Text(counts)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(story.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(height: 168, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(hovering ? 0.45 : 0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .confirmationDialog(
            "Delete “\(story.title)”?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                try? StoryLibrary.delete(story.url)
                onChanged()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(story.stats.blocks) block\(story.stats.blocks == 1 ? "" : "s") will go to the Trash.")
        }
        // An alert rather than an inline field: the whole card is a button, so
        // a field sitting inside it would be fighting for the same clicks.
        .alert("Rename story", isPresented: $renaming) {
            TextField("Name", text: $draftTitle)
            Button("Rename") {
                try? StoryLibrary.rename(story.url, to: draftTitle)
                onChanged()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file keeps the name it was created with.")
        }
    }

    private var counts: String {
        var parts = ["\(story.stats.blocks) block\(story.stats.blocks == 1 ? "" : "s")"]
        if story.stats.characters > 0 {
            parts.append("\(story.stats.characters) character\(story.stats.characters == 1 ? "" : "s")")
        }
        if story.stats.settings > 0 {
            parts.append("\(story.stats.settings) place\(story.stats.settings == 1 ? "" : "s")")
        }
        if story.stats.open > 0 { parts.append("\(story.stats.open) open") }
        return parts.joined(separator: " · ")
    }

    private var menu: some View {
        Menu {
            Button("Rename…") {
                draftTitle = story.title
                renaming = true
            }
            Button("Duplicate") {
                _ = try? StoryLibrary.duplicate(story.url)
                onChanged()
            }
            Button("Reveal in Finder") { StoryLibrary.reveal(story.url) }
            Divider()
            Button("Delete…", role: .destructive) { confirmingDelete = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
