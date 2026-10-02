import SwiftUI

/// A read-only, cross-playlist view of everything the previews have learned.
///
/// It exists to answer one question the per-playlist sheets cannot: which of
/// these songs do I already own somewhere else, and can a playlist point at
/// that copy instead of downloading it again?
struct LibraryInventoryScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var availability: LibraryInventoryAvailability?

    private var inventory: LibraryInventory {
        LibraryInventory(analyses: Array(model.libraryAnalyses.values))
    }

    var body: some View {
        let inventory = inventory
        let rows = inventory.filtered(availability: availability, query: query)

        VStack(alignment: .leading, spacing: 0) {
            header(for: inventory)
            Divider()

            if inventory.entries.isEmpty {
                EmptyStateView(
                    systemImage: "square.stack.3d.up",
                    title: "No previews yet",
                    detail: "Preview a playlist against your existing music library and every track it finds shows up here."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                EmptyStateView(
                    systemImage: "line.3.horizontal.decrease.circle",
                    title: "No matching tracks",
                    detail: "No analyzed track matches this filter and search."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { offset, entry in
                            LibraryInventoryRow(entry: entry)
                            if offset < rows.count - 1 { Divider() }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func header(for inventory: LibraryInventory) -> some View {
        let counts = inventory.counts()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Track Inventory").font(.title2.bold())
                    Text(subtitle(for: inventory))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if inventory.alreadyOwnedCount > 0 {
                Text("\(inventory.alreadyOwnedCount) of \(inventory.entries.count) analyzed tracks already exist on this Mac. \"In your library\" tracks are linked from where they sit; \"below target\" tracks exist too, but miss the reuse conditions, so future syncs seek upgrades while exports keep playable copies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { filterChips(counts: counts, total: inventory.entries.count) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { filterChips(counts: counts, total: inventory.entries.count) }
                }
            }

            TextField("Search song, artist, album, path, or playlist", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)
        }
        .padding(22)
    }

    @ViewBuilder
    private func filterChips(
        counts: [LibraryInventoryAvailability: Int],
        total: Int
    ) -> some View {
        filterChip(title: "All", count: total, value: nil)
        ForEach(LibraryInventoryAvailability.allCases, id: \.self) { value in
            let count = counts[value] ?? 0
            if count > 0 {
                filterChip(title: value.label, count: count, value: value)
            }
        }
    }

    private func filterChip(
        title: String,
        count: Int,
        value: LibraryInventoryAvailability?
    ) -> some View {
        let isSelected = availability == value
        return Button {
            availability = isSelected ? nil : value
        } label: {
            HStack(spacing: 5) {
                Text(title).font(.caption.weight(.medium))
                Text("\(count)")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(isSelected ? Color.accentColor.opacity(0.5) : .clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) tracks")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func subtitle(for inventory: LibraryInventory) -> String {
        var parts = ["\(inventory.entries.count) tracks"]
        parts.append(inventory.playlistCount == 1 ? "1 playlist" : "\(inventory.playlistCount) playlists")
        if let analyzedAt = inventory.analyzedAt {
            parts.append("newest preview \(analyzedAt.shortDateTimeLabel)")
        }
        return parts.joined(separator: " · ")
    }
}

private struct LibraryInventoryRow: View {
    let entry: LibraryInventoryEntry

    private var tone: Color {
        switch entry.availability {
        case .referenced, .downloaded: return .green
        case .belowTarget: return .orange
        case .missing: return .blue
        case .unavailable: return .red
        }
    }

    private var symbol: String {
        switch entry.availability {
        case .referenced: return "link"
        case .downloaded: return "checkmark"
        case .belowTarget: return "arrow.down.right"
        case .missing: return "arrow.down"
        case .unavailable: return "questionmark"
        }
    }

    private var lengthLabel: String? {
        guard let lengthSeconds = entry.lengthSeconds, lengthSeconds > 0 else { return nil }
        return String(format: "%d:%02d", lengthSeconds / 60, lengthSeconds % 60)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                Text(entry.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let album = entry.album, !album.isEmpty {
                    Text("Album: \(album)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if entry.availability.explainsEligibilityInline {
                    Text(entry.availability.playlistEligibility)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let path = entry.localPath, !path.isEmpty {
                    Label(path, systemImage: "folder")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(path)
                        .accessibilityLabel("File path: \(path)")
                }

                HStack(spacing: 6) {
                    Label(playlistLabel, systemImage: "music.note.list")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(entry.playlistNames.joined(separator: ", "))
                    if entry.variesByPlaylist {
                        Label("Varies by playlist", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("These playlists were analyzed under different reuse conditions, so they do not agree on this track.")
                    }
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 6) {
                Label(entry.availability.label, systemImage: symbol)
                    .font(.caption2.bold())
                    .foregroundStyle(tone)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(tone.opacity(0.11), in: Capsule())

                if let quality = entry.quality {
                    Text(quality.displayLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let lengthLabel {
                    Text(lengthLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Duration \(lengthLabel)")
                }
            }
            .frame(minWidth: 138, maxWidth: 210, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var playlistLabel: String {
        guard entry.isSharedAcrossPlaylists else {
            return entry.playlistNames.first ?? "No playlist"
        }
        return "\(entry.playlistNames.count) playlists · \(entry.playlistNames.joined(separator: ", "))"
    }

    private var accessibilitySummary: String {
        var parts = [
            entry.title,
            "by \(entry.artist)",
            entry.availability.label,
            entry.availability.playlistEligibility,
            playlistLabel
        ]
        if let path = entry.localPath, !path.isEmpty { parts.append("path \(path)") }
        if entry.variesByPlaylist { parts.append("varies by playlist") }
        return parts.joined(separator: ", ")
    }
}

/// Detail-pane companion for the inventory: what the states mean and why a
/// track you already own can still be scheduled for a download.
struct LibraryInventoryExplainer: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("WHAT THIS ANSWERS")
                    .font(.caption.bold())
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text("Do I already own this?")
                    .font(.title3.bold())
                Text("Every track a library preview has examined appears here once, with the playlists that want it. Grouping happens on artist and title, so a song shared by three playlists is one row.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                ForEach(LibraryInventoryAvailability.allCases, id: \.self) { value in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(value.label).font(.callout.weight(.semibold))
                        Text(value.playlistEligibility)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                Text("This view is read-only. It reports what the last preview of each playlist found; it never moves, copies, or downloads a file.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
    }
}
