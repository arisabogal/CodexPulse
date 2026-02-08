import Foundation

struct AppInstallStatus: Equatable {
    let destinationURL: URL
    let canInstallCurrentBuild: Bool
}

enum AppInstallationService {
    private struct BundleSignature: Equatable {
        let shortVersion: String
        let buildVersion: String
        let executableSize: Int64
        let executableModifiedAt: Date
    }

    private static let fileManager = FileManager.default

    static func status() -> AppInstallStatus {
        let sourceURL = Bundle.main.bundleURL.standardizedFileURL
        let destinationURL = preferredDestination(for: sourceURL.lastPathComponent)

        guard let sourceSignature = signature(for: sourceURL) else {
            return AppInstallStatus(destinationURL: destinationURL, canInstallCurrentBuild: false)
        }

        let installedSignature = signature(for: destinationURL)
        let canInstallCurrentBuild = installedSignature == nil || installedSignature != sourceSignature

        return AppInstallStatus(destinationURL: destinationURL, canInstallCurrentBuild: canInstallCurrentBuild)
    }

    static func installCurrentBuild() throws -> URL {
        let sourceURL = Bundle.main.bundleURL.standardizedFileURL
        let destinationURL = preferredDestination(for: sourceURL.lastPathComponent)
        let destinationParent = destinationURL.deletingLastPathComponent()

        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        let tempURL = destinationParent.appendingPathComponent("\(destinationURL.lastPathComponent).tmp-\(UUID().uuidString)")
        if fileManager.fileExists(atPath: tempURL.path) {
            try? fileManager.removeItem(at: tempURL)
        }

        try fileManager.copyItem(at: sourceURL, to: tempURL)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: tempURL, to: destinationURL)
        return destinationURL
    }

    private static func preferredDestination(for appBundleName: String) -> URL {
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let systemDestination = systemApplications.appendingPathComponent(appBundleName, isDirectory: true)

        if fileManager.fileExists(atPath: systemDestination.path) || fileManager.isWritableFile(atPath: systemApplications.path) {
            return systemDestination
        }

        let userApplications = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        return userApplications.appendingPathComponent(appBundleName, isDirectory: true)
    }

    private static func signature(for appURL: URL) -> BundleSignature? {
        guard fileManager.fileExists(atPath: appURL.path) else { return nil }
        guard let bundle = Bundle(url: appURL) else { return nil }

        let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let buildVersion = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""

        guard let executableURL = bundle.executableURL else { return nil }
        guard let attributes = try? fileManager.attributesOfItem(atPath: executableURL.path) else { return nil }

        let executableSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let executableModifiedAt = (attributes[.modificationDate] as? Date) ?? .distantPast

        return BundleSignature(
            shortVersion: shortVersion,
            buildVersion: buildVersion,
            executableSize: executableSize,
            executableModifiedAt: executableModifiedAt
        )
    }
}
