import SwiftUI

struct SyncQueueScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(
                eyebrow: "Coming up",
                title: "Sync Queue",
                detail: "\(model.activeRun == nil ? 0 : 1) running · \(model.queuedSyncCount) waiting. Playlists run one at a time in the order below."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(model.isQueuePaused ? "Queue paused" : "Queue ready").font(.headline)
                        Spacer()
                        Button(model.isQueuePaused ? "Resume queue" : "Pause queue") { model.toggleQueuePaused() }
                    }
                    Text("Pausing lets the current sync finish and prevents waiting jobs and daily schedules from starting.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let run = model.activeRun {
                        HStack {
                            Label("Running now", systemImage: "arrow.down.circle")
                                .font(.headline)
                            Spacer()
                            Button("Cancel current sync") { model.cancelActiveRun() }
                        }
                        RunRow(run: run)
                        Text(model.isQueuePaused ? "The queue is paused. Cancelling will not start another playlist." : "Cancelling the current sync starts the next waiting playlist.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.queuedSyncs.isEmpty {
                        EmptyStateView(
                            systemImage: "list.number",
                            title: "No playlists waiting",
                            detail: "Choose playlists in Batch Sync and confirm them to add them to the queue."
                        )
                        Button("Choose playlists") { model.selectedSection = .batchSync }
                    } else {
                        SyncQueueView(allowsReordering: true)
                    }
                    Text("Waiting jobs and their order are saved. After restarting SeekSync, resume the queue when ready.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scheduled playlists").font(.headline)
                            Text("Daily schedules start when due and the queue is idle. Manage them in Sync Pool.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Sync Pool") { model.selectedSection = .syncPool }
                    }
                    Text(model.settings.isLiveSchedulingArmed ? "Live scheduling is armed." : "Live scheduling is disarmed. Scheduled live syncs will not start.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(model.plans.filter(\.enabled).sorted { $0.nextRunAt < $1.nextRunAt }) { plan in
                        if let playlist = model.playlist(for: plan) {
                            HStack {
                                Text(playlist.name)
                                Spacer()
                                Text(plan.nextRunAt.shortDateTimeLabel)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}
