import AppKit

/// Checks GitHub Releases for a newer EasyShoot and installs it in place.
///
/// The app downloads the update itself, so macOS does not mark it as quarantined
/// and it opens without the Gatekeeper prompt a browser download gets.
@MainActor
final class Updater {
    static let shared = Updater()

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/Haythamasalama/easyshoot/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/Haythamasalama/easyshoot/releases/latest")!
    nonisolated private static let assetName = "EasyShoot.zip"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var isBusy = false

    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let assets: [Asset]

        var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
        var download: URL? { assets.first { $0.name == Updater.assetName }?.browser_download_url }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var automaticChecks: Bool {
        get { defaults.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoCheckUpdates") }
    }

    /// Checks shortly after launch and then once a day, when automatic checks are on.
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            Task { @MainActor in Updater.shared.checkIfDue() }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            checkIfDue()
        }
    }

    func checkIfDue() {
        // Never cover the first-run window (it checks again when it closes) or a capture in progress.
        guard automaticChecks, !WelcomeWindowController.shared.isShowing, !CaptureCoordinator.shared.isBusy else { return }
        let last = defaults.double(forKey: "lastUpdateCheck")
        guard Date().timeIntervalSince1970 - last >= Self.checkInterval else { return }
        check(userInitiated: false)
    }

    /// `userInitiated` checks also say when you're up to date or the check failed.
    func check(userInitiated: Bool) {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                var request = URLRequest(url: Self.latestReleaseURL)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    // For example GitHub's rate limit; a clear message beats a JSON decoding error.
                    throw UpdateError(errorDescription: HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                defaults.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")

                guard Self.isVersion(release.version, newerThan: Self.currentVersion), release.download != nil else {
                    if userInitiated { showUpToDate() }
                    return
                }
                if !userInitiated, defaults.string(forKey: "skippedVersion") == release.version { return }
                if !userInitiated, CaptureCoordinator.shared.isBusy || WelcomeWindowController.shared.isShowing {
                    // A capture started while we were online: offer it on the next hourly check instead.
                    defaults.removeObject(forKey: "lastUpdateCheck")
                    return
                }
                offer(release)
            } catch {
                if userInitiated { showFailure(error) }
            }
        }
    }

    /// Compares dotted version numbers: 1.10.0 is newer than 1.9.2.
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Alerts

    private func offer(_ release: Release) {
        AppActivation.windowOpened()
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("EasyShoot %@ is available", release.version)
        alert.informativeText = L("You have version %@. The update downloads, replaces the app and reopens it.", Self.currentVersion)
        alert.addButton(withTitle: L("Update Now"))
        alert.addButton(withTitle: L("Later"))
        alert.addButton(withTitle: L("Skip This Version"))
        let response = alert.runModal()
        AppActivation.windowClosed()
        switch response {
        case .alertFirstButtonReturn: install(release)
        case .alertThirdButtonReturn: defaults.set(release.version, forKey: "skippedVersion")
        default: break
        }
    }

    private func showUpToDate() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("You're up to date")
        alert.informativeText = L("EasyShoot %@ is the newest version.", Self.currentVersion)
        alert.runModal()
    }

    private func showFailure(_ error: Error) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Couldn't check for updates")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Open Releases Page"))
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(Self.releasesPage) }
    }

    // MARK: Install

    private func install(_ release: Release) {
        guard let download = release.download else { return }
        // Set inside the task: the check that offered this update clears the flag when it returns.
        Task { @MainActor in
            isBusy = true
            defer { isBusy = false }
            do {
                let staged = try await Self.downloadAndUnpack(download)
                try relaunch(replacingWith: staged)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L("The update couldn't be installed")
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: L("OK"))
                alert.addButton(withTitle: L("Open Releases Page"))
                if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(release.html_url) }
            }
        }
    }

    struct UpdateError: LocalizedError {
        let errorDescription: String?
    }

    /// Downloads the zip and unpacks it next to it, returning the new EasyShoot.app.
    private static func downloadAndUnpack(_ url: URL) async throws -> URL {
        let (zip, _) = try await URLSession.shared.download(from: url)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyShootUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        try await run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path])
        let app = folder.appendingPathComponent("EasyShoot.app")
        guard Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError(errorDescription: L("The download didn't contain EasyShoot."))
        }
        return app
    }

    /// Hands the swap to a small shell script that waits for this process to quit,
    /// moves the new app into place and opens it.
    private func relaunch(replacingWith newApp: URL) throws {
        let current = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            throw UpdateError(errorDescription: L("EasyShoot can't write to %@. Move it to your Applications folder and try again.", current.deletingLastPathComponent().path))
        }
        // The old app is only deleted once the new one is in place; if the move fails, the old one comes back.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$2.old"
        if mv "$2" "$2.old"; then
          if mv "$3" "$2"; then rm -rf "$2.old"; else mv "$2.old" "$2"; fi
        fi
        xattr -dr com.apple.quarantine "$2" 2>/dev/null
        open "$2"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), current.path, newApp.path]
        try process.run()
        NSApp.terminate(nil)
    }

    /// Runs a tool without blocking the main thread while it works.
    private static func run(_ tool: String, _ arguments: [String]) async throws {
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            throw UpdateError(errorDescription: L("Couldn't unpack the update."))
        }
    }
}
