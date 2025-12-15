//
// XcodeClient.swift
// Xproject
//

import Foundation

private typealias InstalledXcode = (path: String, version: String)

// MARK: - Xcode Client Protocol

public protocol XcodeClientProtocol: Sendable {
    func buildForTesting(scheme: String, clean: Bool, buildDestination: String) async throws
    func runTests(scheme: String, destination: String) async throws
    func archive(environment: String) async throws
    func generateIPA(environment: String) async throws
    func upload(environment: String) async throws
    func clean() async throws
}

// MARK: - Xcode Client

// swiftlint:disable:next type_body_length
public final class XcodeClient: XcodeClientProtocol, Sendable {
    private let workingDirectory: String
    private let configurationProvider: any ConfigurationProviding
    private let commandExecutor: any CommandExecuting
    private let fileManagerBuilder: @Sendable () -> FileManager
    private let verbose: Bool

    public init(
        workingDirectory: String,
        configurationProvider: any ConfigurationProviding,
        commandExecutor: any CommandExecuting,
        verbose: Bool,
        fileManagerBuilder: @Sendable @escaping () -> FileManager = { .default }
    ) {
        self.workingDirectory = workingDirectory
        self.configurationProvider = configurationProvider
        self.commandExecutor = commandExecutor
        self.fileManagerBuilder = fileManagerBuilder
        self.verbose = verbose
    }

    // MARK: - Public Methods

    public func buildForTesting(scheme: String, clean: Bool, buildDestination: String) async throws {
        let config = try configurationProvider.configuration

        // Ensure directories exist
        try createDirectoriesIfNeeded(config: config)

        let reportName = "tests"
        let xcodeArgs = buildXcodeArgs(config: config, scheme: scheme, buildDestination: buildDestination)

        if clean {
            let cleanArgs = ["clean"] + xcodeArgs
            let cleanReportName = "\(reportName)-\(scheme)-clean"
            try await executeXcodeBuild(args: cleanArgs, reportName: cleanReportName, config: config)
        }

        let buildArgs = [
            "analyze",
            "build-for-testing",
            "-enableCodeCoverage YES"
        ] + xcodeArgs

        let buildReportName = buildReportName(scheme: scheme, destination: buildDestination)
        try await executeXcodeBuild(args: buildArgs, reportName: buildReportName, config: config)
    }

    public func runTests(scheme: String, destination: String) async throws {
        let config = try configurationProvider.configuration

        let xcodeArgs = [
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGN_IDENTITY=",
            "PROVISIONING_PROFILE=",
            config.projectOrWorkspace(),
            "-scheme '\(scheme)'",
            "-parallel-testing-enabled NO",
            "test-without-building",
            "-destination '\(destination)'"
        ]

        let reportName = testReportName(scheme: scheme, destination: destination)
        try await executeXcodeBuild(args: xcodeArgs, reportName: reportName, config: config)
    }

    public func archive(environment: String) async throws {
        let config = try configurationProvider.configuration

        guard let releaseConfig = config.xcode?.release?[environment] else {
            throw XcodeClientError.environmentNotFound(environment)
        }

        try createDirectoriesIfNeeded(config: config)

        var xcodeArgs = [config.projectOrWorkspace()]

        if let configuration = releaseConfig.configuration,
           !configuration.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            xcodeArgs.append("-configuration '\(configuration)'")
        }

        xcodeArgs.append(contentsOf: [
            "-archivePath '\(archivePath(filename: releaseConfig.output, config: config))'",
            "-destination 'generic/platform=\(releaseConfig.destination)'",
            "-scheme '\(releaseConfig.scheme)'",
            "-parallelizeTargets",
            "clean archive"
        ])

        let reportName = "archive-\(environment)"
        try await executeXcodeBuild(args: xcodeArgs, reportName: reportName, config: config)
    }

    public func generateIPA(environment: String) async throws {
        let config = try configurationProvider.configuration

        guard let releaseConfig = config.xcode?.release?[environment] else {
            throw XcodeClientError.environmentNotFound(environment)
        }

        let exportPath = exportPath(filename: releaseConfig.output, config: config)

        // Validate export path is safe to delete BEFORE doing any other operations
        // Note: Use non-streaming execute for rm commands since they produce no output
        try validateSafeToDelete(exportPath)

        let exportPlistPath = try createExportPlist(signingConfiguration: releaseConfig.signing, config: config)

        var xcodeArgs = [
            "-exportArchive",
            "-archivePath '\(archivePath(filename: releaseConfig.output, config: config))'",
            "-exportPath '\(exportPath)'",
            "-exportOptionsPlist '\(exportPlistPath)'"
        ]

        // Add -allowProvisioningUpdates only for automatic signing
        if releaseConfig.signing?.signingStyle == "automatic" {
            xcodeArgs.append("-allowProvisioningUpdates")
        }

        // Clean export directory
        _ = try commandExecutor.executeOrThrow("rm -rf '\(exportPath)'")

        let reportName = "export-\(environment)"
        try await executeXcodeBuild(args: xcodeArgs, reportName: reportName, config: config)
    }

    public func upload(environment: String) async throws {
        let config = try configurationProvider.configuration

        guard let releaseConfig = config.xcode?.release?[environment] else {
            throw XcodeClientError.environmentNotFound(environment)
        }

        let ipaPath = "\(exportPath(filename: releaseConfig.output, config: config))/\(releaseConfig.scheme).ipa"
        let xcodeVersion = try await getXcodeVersion(config: config)

        // --use-old-altool should be removed once Apple fix their side
        // https://github.com/fastlane/fastlane/issues/29698
        var uploadCommand = "\(xcodeVersion) xcrun altool --upload-app --use-old-altool --type \(releaseConfig.type) -f '\(ipaPath)'"

        if let appStoreAccount = releaseConfig.appStoreAccount {
            uploadCommand += " -u \(appStoreAccount)"
        }

        if ProcessInfo.processInfo.environment["APP_STORE_PASS"] != nil {
            uploadCommand += " -p @env:APP_STORE_PASS"
        }

        if verbose {
            _ = try await commandExecutor.executeWithStreamingOutputOrThrow(uploadCommand)
        } else {
            _ = try commandExecutor.executeOrThrow(uploadCommand)
        }
    }

    public func clean() async throws {
        let config = try configurationProvider.configuration
        let buildPath = config.buildPath()
        let reportsPath = config.reportsPath()

        // Note: Use non-streaming execute for rm commands since they produce no output
        _ = try commandExecutor.executeOrThrow("rm -rf '\(buildPath)' '\(reportsPath)'")
    }

    // MARK: - Private Methods

    private func buildXcodeArgs(config: XprojectConfiguration, scheme: String, buildDestination: String) -> [String] {
        return [
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGN_IDENTITY=",
            "PROVISIONING_PROFILE=",
            config.projectOrWorkspace(),
            "-parallelizeTargets",
            "-scheme '\(scheme)'",
            "-destination '\(buildDestination)'"
        ]
    }

    private func executeXcodeBuild(args: [String], reportName: String, config: XprojectConfiguration) async throws {
        let buildPath = config.buildPath()
        let reportsPath = config.reportsPath()

        let xcodeLogFile = "\(buildPath)/xcode-\(reportName).log"
        let resultFile = "\(reportsPath)/\(reportName).xcresult"

        let allArgs = args + [
            "-resultBundlePath '\(resultFile)'",
            "-resultBundleVersion 3",
            "-skipPackagePluginValidation",
            "-skipMacroValidation"
        ]

        let xcodeVersion = try await getXcodeVersion(config: config)
        let argsString = allArgs.joined(separator: " ")

        // Clean previous outputs
        // Note: Use non-streaming execute for rm commands since they produce no output
        _ = try commandExecutor.executeOrThrow("rm -fr '\(xcodeLogFile)' '\(resultFile)'")

        // Execute xcodebuild
        let buildCommand = "set -o pipefail && \(xcodeVersion) xcrun xcodebuild \(argsString) | " +
                           "tee '\(xcodeLogFile)' | xcbeautify"

        _ = try await commandExecutor.executeWithStreamingOutputOrThrow(buildCommand)
    }

    private func getXcodeVersion(config: XprojectConfiguration) async throws -> String {
        guard let targetVersion = config.xcode?.version else {
            return "" // Use default Xcode
        }

        let installedXcodes = try await findInstalledXcodes()

        // Build version prefix for pessimistic matching (RubyGems ~> style)
        // e.g., "26.1.1" → matches "26.1.*", "26.1" → matches "26.*"
        let versionPrefix = buildVersionPrefix(from: targetVersion)

        // Find all Xcodes matching the version prefix
        let matchingXcodes = installedXcodes.compactMap { xcodePath -> (path: String, version: String)? in
            guard let version = try? fetchXcodeVersion(path: xcodePath),
                  version.hasPrefix(versionPrefix) else {
                return nil
            }
            return (path: xcodePath, version: version)
        }

        guard !matchingXcodes.isEmpty else {
            throw XcodeClientError.xcodeVersionNotFound(targetVersion)
        }

        // Prefer exact match, otherwise take the highest matching version
        let bestMatch: InstalledXcode
        if let exactMatch = matchingXcodes.first(where: { $0.version == targetVersion }) {
            bestMatch = exactMatch
        } else if let highestVersion = matchingXcodes.max(by: { compareVersions($0.version, $1.version) }) {
            bestMatch = highestVersion
        } else {
            throw XcodeClientError.xcodeVersionNotFound(targetVersion)
        }

        return "DEVELOPER_DIR=\"\(bestMatch.path)/Contents/Developer\""
    }

    /// Build version prefix for pessimistic matching.
    /// "26.1.1" → "26.1." (matches 26.1.x)
    /// "26.1" → "26." (matches 26.x)
    /// "26" → "26." (matches 26.x)
    private func buildVersionPrefix(from version: String) -> String {
        let components = version.split(separator: ".").map(String.init)

        if components.count <= 1 {
            // "26" → "26."
            return "\(components.first ?? "")."
        }

        // Drop last component and join with dots, add trailing dot
        // "26.1.1" → "26.1.", "26.1" → "26."
        return components.dropLast().joined(separator: ".") + "."
    }

    /// Compare two version strings numerically.
    /// Returns true if v1 < v2.
    private func compareVersions(_ v1: String, _ v2: String) -> Bool {
        let c1 = v1.split(separator: ".").compactMap { Int($0) }
        let c2 = v2.split(separator: ".").compactMap { Int($0) }

        for index in 0..<max(c1.count, c2.count) {
            let n1 = index < c1.count ? c1[index] : 0
            let n2 = index < c2.count ? c2[index] : 0
            if n1 != n2 {
                return n1 < n2
            }
        }
        return false
    }

    private func findInstalledXcodes() async throws -> [String] {
        // Try mdfind first - use executeReadOnly since this is discovery
        let mdfindResult = try? commandExecutor.executeReadOnly("mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null")

        if let result = mdfindResult, result.isSuccess, !result.output.isEmpty {
            return result.output.split(separator: "\n").map(String.init)
        }

        // Fallback to find in /Applications - use executeReadOnly since this is discovery
        let findResult = try commandExecutor.executeReadOnly("""
            find /Applications -name '*.app' -type d -maxdepth 1 -exec sh -c \
            'if [ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
            "{}/Contents/Info.plist" 2>/dev/null)" == "com.apple.dt.Xcode" ]; then echo "{}"; fi' ';'
            """)

        if findResult.isSuccess {
            return findResult.output.split(separator: "\n").map(String.init)
        }

        return []
    }

    private func fetchXcodeVersion(path: String) throws -> String {
        let command = "/usr/libexec/PlistBuddy -c \"Print CFBundleShortVersionString\" \"\(path)/Contents/Info.plist\""
        let result = try commandExecutor.executeReadOnly(command)

        guard result.isSuccess, !result.output.isEmpty else {
            throw XcodeClientError.xcodeVersionFetchFailed(path)
        }

        guard let version = result.output.split(separator: "\n").first.map(String.init) else {
            throw XcodeClientError.xcodeVersionFetchFailed(path)
        }

        return version
    }

    private func absolutePath(from path: String) -> String {
        if path.hasPrefix("/") {
            return path  // Already absolute
        }
        return URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent(path)
            .path
    }

    private func createDirectoriesIfNeeded(config: XprojectConfiguration) throws {
        let fileManager = fileManagerBuilder()
        let buildPath = absolutePath(from: config.buildPath())
        let reportsPath = absolutePath(from: config.reportsPath())

        try fileManager.createDirectory(atPath: buildPath, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: reportsPath, withIntermediateDirectories: true)
    }

    private func archivePath(filename: String, config: XprojectConfiguration) -> String {
        return "\(config.buildPath())/\(filename).xcarchive"
    }

    private func exportPath(filename: String, config: XprojectConfiguration) -> String {
        return "\(config.buildPath())/\(filename)-ipa"
    }

    private func buildReportName(scheme: String, destination: String) -> String {
        return "tests-\(scheme)-\(stringForDestination(destination))-build"
    }

    private func testReportName(scheme: String, destination: String) -> String {
        return "tests-\(stringForScheme(scheme))-\(stringForDestination(destination))"
    }

    private func stringForDestination(_ destination: String) -> String {
        let elements = destination.split(separator: ",").reduce(into: [String: String]()) { result, pair in
            let components = pair.split(separator: "=", maxSplits: 1)
            if components.count == 2 {
                result[String(components[0])] = String(components[1])
            }
        }

        let platform = elements["platform"] ?? elements["generic/platform"] ?? ""
        let os = elements["OS"] ?? ""
        let device = elements["name"] ?? ""

        var name = os.isEmpty ? platform : os
        if !device.isEmpty {
            if !name.isEmpty { name += "_" }
            name += device
        }

        return name.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func stringForScheme(_ scheme: String) -> String {
        return scheme.replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
    }

    private func createExportPlist(signingConfiguration: SigningConfiguration?, config: XprojectConfiguration) throws -> String {
        var plistDict: [String: Any] = ["method": "app-store-connect"]

        if let signing = signingConfiguration {
            if let signingCertificate = signing.signingCertificate {
                plistDict["signingCertificate"] = signingCertificate
            }
            if let teamID = signing.teamID {
                plistDict["teamID"] = teamID
            }
            if let signingStyle = signing.signingStyle {
                plistDict["signingStyle"] = signingStyle
            }
            if let provisioningProfiles = signing.provisioningProfiles {
                plistDict["provisioningProfiles"] = provisioningProfiles
            }
        }

        let relativePlistPath = "\(config.buildPath())/export.plist"
        let absolutePlistPath = absolutePath(from: relativePlistPath)
        let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)

        try plistData.write(to: URL(fileURLWithPath: absolutePlistPath))

        return relativePlistPath  // Return relative path for xcodebuild command
    }

    /// Validates that a path is safe to delete with rm -rf
    /// - Parameter path: The path to validate
    /// - Throws: XcodeClientError.unsafePathDeletion if the path is potentially dangerous
    private func validateSafeToDelete(_ path: String) throws {
        // Reject empty paths
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcodeClientError.unsafePathDeletion(path)
        }

        let normalizedPath = path.trimmingCharacters(in: .whitespaces)

        // Reject root and critical system directories
        let dangerousPaths = [
            "/",
            "/System",
            "/Library",
            "/Users",
            "/Applications",
            "/bin",
            "/sbin",
            "/usr",
            "/var",
            "/etc",
            "/tmp",
            "/private"
        ]

        for dangerousPath in dangerousPaths {
            if normalizedPath == dangerousPath || normalizedPath.hasPrefix(dangerousPath + "/") {
                throw XcodeClientError.unsafePathDeletion(path)
            }
        }

        // Must contain "build", "reports", or common artifact indicators
        let safeIndicators = ["build", "reports", ".xcarchive", "-ipa", ".ipa", ".log", ".xml", ".xcresult"]
        let containsSafeIndicator = safeIndicators.contains { indicator in
            normalizedPath.lowercased().contains(indicator.lowercased())
        }

        guard containsSafeIndicator else {
            throw XcodeClientError.unsafePathDeletion(path)
        }
    }
}

// MARK: - Xcode Client Errors

public enum XcodeClientError: Error, LocalizedError, Sendable {
    case environmentNotFound(String)
    case xcodeVersionNotFound(String)
    case xcodeVersionFetchFailed(String)
    case configurationError(String)
    case unsafePathDeletion(String)

    public var errorDescription: String? {
        switch self {
        case .environmentNotFound(let environment):
            return "Environment '\(environment)' not found in xcode.release configuration"
        case .xcodeVersionNotFound(let version):
            return "Xcode version \(version) not found"
        case .xcodeVersionFetchFailed(let path):
            return "Failed to fetch Xcode version from '\(path)'"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .unsafePathDeletion(let path):
            return "Refusing to delete potentially unsafe path: '\(path)'. Path must be non-empty and within the build directory."
        }
    }
}
