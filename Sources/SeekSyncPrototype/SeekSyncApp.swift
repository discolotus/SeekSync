import AppKit
import SwiftUI

private enum MainWindowRoute: String, Codable, Hashable {
    case main
}

@main
struct SeekSyncPrototypeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("SeekSync", for: MainWindowRoute.self) { _ in
            RootPrototypeView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 520)
        } defaultValue: {
            .main
        }
        .defaultSize(width: 1_180, height: 720)

        MenuBarExtra("SeekSync", systemImage: "arrow.triangle.2.circlepath") {
            MenuBarStatusView()
                .environmentObject(model)
        }

        Settings {
            SettingsScreen()
                .environmentObject(model)
                .frame(width: 660, height: 560)
        }
    }
}

struct RootPrototypeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAddPlaylist = false
    @SceneStorage("playlistInspectorPresented") private var inspectorPresented = false

    var body: some View {
        LibraryInspectorVariant(
            showAddPlaylist: $showAddPlaylist,
            inspectorPresented: $inspectorPresented
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    inspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help(inspectorPresented ? "Hide playlist inspector" : "Show playlist inspector")
                .accessibilityLabel(inspectorPresented ? "Hide playlist inspector" : "Show playlist inspector")
                .disabled(model.selectedSection == .batchSync)
            }
        }
        .sheet(isPresented: $showAddPlaylist) {
            AddPlaylistSheet()
                .environmentObject(model)
        }
        .sheet(item: $model.pendingSync) { pending in
            SyncPreviewSheet(pending: pending)
                .environmentObject(model)
        }
        .sheet(item: $model.pendingBatchSync) { pending in
            BatchSyncPreviewSheet(pending: pending)
                .environmentObject(model)
        }
        .onChange(of: model.selectedPlaylistID) { _, playlistID in
            if playlistID != nil {
                inspectorPresented = true
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toastMessage {
                ToastView(message: toast)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 3_200_000_000)
                        if model.toastMessage == toast {
                            withAnimation { model.toastMessage = nil }
                        }
                    }
            }
        }
    }

}

struct MenuBarStatusView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SeekSyncBrandHeader(iconSize: 30)
            Divider()
            if let run = model.activeRun {
                Text(run.playlistName).font(.headline)
                ActiveSyncProgressView(run: run, compact: true)
                Button("Cancel Current Run") { model.cancelActiveRun() }
            } else {
                Label("SeekSync is idle", systemImage: "checkmark.circle")
                    .font(.headline)
                if let next = model.plans.filter(\.enabled).map(\.nextRunAt).min() {
                    Text("Next daily check \(next.relativeLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Open SeekSync") {
                if let existingWindow = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                    existingWindow.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    openWindow(value: MainWindowRoute.main)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Button("Refresh Spotify") { model.refreshSpotify() }
            Divider()
            Text(model.dependencyState.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Quit SeekSync") { NSApp.terminate(nil) }
        }
        .padding(10)
        .frame(width: 280)
    }
}
