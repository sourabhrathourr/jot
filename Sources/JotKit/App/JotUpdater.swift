import AppKit
import Sparkle

/// Updates through Sparkle, like Hun: each GitHub release publishes a notarized DMG and an
/// EdDSA-signed `appcast.xml` (`SUFeedURL` and `SUPublicEDKey` are set by scripts/bundle.sh).
/// Sparkle checks once a day and asks before installing.
final class JotUpdater: NSObject {
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        // Only a packaged Jot.app has a feed; `swift run` and the tests don't.
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
