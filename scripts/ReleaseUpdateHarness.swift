import AppKit
import Sparkle

@MainActor final class Driver: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    var updater: SPUUpdater!
    let target: URL
    let expected: String
    let marker: URL
    var downloadStarted = false
    init(target: URL, expected: String, marker: URL) { self.target=target; self.expected=expected; self.marker=marker }
    func show(_ error: Error) { fputs("Update-chain verification failed: \(error)\n",stderr); exit(1) }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { reply(SUUpdatePermissionResponse(automaticUpdateChecks:false,sendSystemProfile:false)) }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard appcastItem.versionString == expected else { fatalError("Unexpected update build") }
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { show(error) }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { show(error) }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { show(error) }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { downloadStarted=true }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement(); verifyInstalled() }
    func dismissUpdateInstallation() {}
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { show(error) }
    func verifyInstalled() {
        guard let data=try? Data(contentsOf:target.appendingPathComponent("Contents/Info.plist")),
              let info=(try? PropertyListSerialization.propertyList(from:data,format:nil)) as? [String:Any],
              info["CFBundleVersion"] as? String == expected, downloadStarted else { return }
        try! Data("verified".utf8).write(to:marker)
        print("PASS: Sparkle downloaded, authenticated, extracted, and replaced the disposable app")
        exit(0)
    }
}
@main struct UpdateHarness {
    @MainActor static func main() throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        let target=URL(fileURLWithPath:CommandLine.arguments[1])
        guard target.path.contains("release-chain-") else { fatalError("Disposable test target required") }
        let driver=Driver(target:target,expected:CommandLine.arguments[2],marker:URL(fileURLWithPath:CommandLine.arguments[3]))
        guard let host=Bundle(url:target) else { fatalError("Missing host bundle") }
        driver.updater=SPUUpdater(hostBundle:host,applicationBundle:host,userDriver:driver,delegate:driver)
        driver.updater.automaticallyChecksForUpdates=false
        driver.updater.automaticallyDownloadsUpdates=false
        try driver.updater.start()
        DispatchQueue.main.asyncAfter(deadline:.now()+1) { driver.updater.checkForUpdates() }
        Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { _ in Task { @MainActor in driver.verifyInstalled() } }
        DispatchQueue.main.asyncAfter(deadline:.now()+55) { fputs("Timed out waiting for the disposable update\n",stderr);exit(2) }
        withExtendedLifetime(driver) { app.run() }
    }
}
