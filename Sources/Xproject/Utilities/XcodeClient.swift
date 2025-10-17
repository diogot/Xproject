//
// XcodeClient.swift
// Xproject
//

import Foundation

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
        // Note: Use non-streaming execute for rm commands since they produce no output
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

        var uploadCommand = "\(xcodeVersion) xcrun altool --upload-app --type \(releaseConfig.type) -f '\(ipaPath)'"

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
        let reportFile = "\(reportsPath)/\(reportName).xml"
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
        _ = try commandExecutor.executeOrThrow("rm -fr '\(xcodeLogFile)' '\(reportFile)' '\(resultFile)'")

        // Execute xcodebuild with xcpretty
        let buildCommand = "set -o pipefail && \(xcodeVersion) xcrun xcodebuild \(argsString) | " +
                           "tee '\(xcodeLogFile)' | xcpretty --color --no-utf -r junit -o '\(reportFile)'"

        if verbose {
            _ = try await commandExecutor.executeWithStreamingOutputOrThrow(buildCommand)
        } else {
            _ = try commandExecutor.executeOrThrow(buildCommand)
        }
    }

    private func getXcodeVersion(config: XprojectConfiguration) async throws -> String {
        guard let targetVersion = config.xcode?.version else {
            return "" // Use default Xcode
        }

        let installedXcodes = try await findInstalledXcodes()

        // Find Xcode matching target version (using ~> semantic matching)
        let matchingXcode = installedXcodes.first { xcodePath in
            guard let version = try? fetchXcodeVersion(path: xcodePath) else {
                return false
            }
            return version.hasPrefix(String(targetVersion.prefix(3))) // Match major.minor
        }

        guard let xcodeApp = matchingXcode else {
            throw XcodeClientError.xcodeVersionNotFound(targetVersion)
        }

        return "DEVELOPER_DIR=\"\(xcodeApp)/Contents/Developer\""
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
}

// MARK: - Xcode Client Errors

public enum XcodeClientError: Error, LocalizedError, Sendable {
    case environmentNotFound(String)
    case xcodeVersionNotFound(String)
    case xcodeVersionFetchFailed(String)
    case configurationError(String)

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
        }
    }
}
