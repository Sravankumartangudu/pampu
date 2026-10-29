import SwiftUI
import UIKit

@main
struct PampuApp: App {
    @StateObject private var drop = Drop()
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView(drop: drop)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
        .onChange(of: phase) { _, now in
            switch now {
            case .active: drop.start()
            case .background: drop.sender.isSending ? finishInBackground() : drop.stop()
            default: break
            }
        }
    }

    /// iOS gives a backgrounded app a little time; use it to finish a drop that's under way.
    private func finishInBackground() {
        var task = UIBackgroundTaskIdentifier.invalid
        let end = {
            if UIApplication.shared.applicationState == .background { drop.stop() }
            if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
        }
        task = UIApplication.shared.beginBackgroundTask(withName: "Finish drop") { end() }
        Task { @MainActor in
            while drop.sender.isSending { try? await Task.sleep(for: .milliseconds(400)) }
            end()
        }
    }
}
