//
// BuildService.swift
// XProject
//

import Foundation

// MARK: - Build Service Protocol

public protocol BuildServiceProtocol: Sendable {
    func buildForTesting(scheme: String, clean: Bool, buildDestination: String) async throws
    func runTests(scheme: String, destination: String) async throws
    func archive(environment: String) async throws
    func generateIPA(environment: String) async throws
    func upload(environment: String) async throws
    func clean() async throws
}

// MARK: - Build Service

public final class BuildService: BuildServiceProtocol, Sendable {
    private let configurationProvider: any ConfigurationProviding
    private let commandExecutor: any CommandExecuting
    private let fileManagerBuilder: @Sendable () -> FileManager

    public init(
        configurationProvider: any ConfigurationProviding = ConfigurationService.shared,
        commandExecutor: any CommandExecuting = CommandExecutor(),
        fileManagerBuilder: @Sendable @escaping () -> FileManager = { .default }
    ) {
        self.configurationProvider = configurationProvider
        self.commandExecutor = commandExecutor
        self.fileManagerBuilder = fileManagerBuilder
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
            throw BuildError.environmentNotFound(environment)
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
            throw BuildError.environmentNotFound(environment)
        }

        let exportPath = exportPath(filename: releaseConfig.output, config: config)
        let exportPlistPath = try createExportPlist(signingConfiguration: releaseConfig.signing, config: config)

        let xcodeArgs = [
            "-exportArchive",
            "-archivePath '\(archivePath(filename: releaseConfig.output, config: config))'",
            "-exportPath '\(exportPath)'",
            "-exportOptionsPlist '\(exportPlistPath)'"
        ]

        // Clean export directory
        _ = try commandExecutor.executeOrThrow("rm -rf '\(exportPath)'")

        let reportName = "export-\(environment)"
        try await executeXcodeBuild(args: xcodeArgs, reportName: reportName, config: config)
    }

    public func upload(environment: String) async throws {
        let config = try configurationProvider.configuration

        guard let releaseConfig = config.xcode?.release?[environment] else {
            throw BuildError.environmentNotFound(environment)
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

        _ = try commandExecutor.executeOrThrow(uploadCommand)
    }

    public func clean() async throws {
        let config = try configurationProvider.configuration
        let buildPath = config.buildPath()
        let reportsPath = config.reportsPath()

        _ = try commandExecutor.executeOrThrow("rm -rf '\(buildPath)' '\(reportsPath)'")
    }

    // MARK: - Private Methods

    private func buildXcodeArgs(config: XProjectConfiguration, scheme: String, buildDestination: String) -> [String] {
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

    private func executeXcodeBuild(args: [String], reportName: String, config: XProjectConfiguration) async throws {
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
        _ = try commandExecutor.executeOrThrow("rm -fr '\(xcodeLogFile)' '\(reportFile)' '\(resultFile)'")

        // Execute xcodebuild with xcpretty
        let buildCommand = "set -o pipefail && \(xcodeVersion) xcrun xcodebuild \(argsString) | " +
                           "tee '\(xcodeLogFile)' | xcpretty --color --no-utf -r junit -o '\(reportFile)'"

        _ = try commandExecutor.executeOrThrow(buildCommand)
    }

    private func getXcodeVersion(config: XProjectConfiguration) async throws -> String {
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
            throw BuildError.xcodeVersionNotFound(targetVersion)
        }

        return "DEVELOPER_DIR=\"\(xcodeApp)/Contents/Developer\""
    }

    private func findInstalledXcodes() async throws -> [String] {
        // Try mdfind first
        let mdfindResult = try? commandExecutor.execute("mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\" 2>/dev/null")

        if let result = mdfindResult, result.isSuccess, !result.output.isEmpty {
            return result.output.split(separator: "\n").map(String.init)
        }

        // Fallback to find in /Applications
        let findResult = try commandExecutor.execute("""
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
        let result = try commandExecutor.execute(command)

        guard result.isSuccess, !result.output.isEmpty else {
            return "0.0"
        }

        return result.output.split(separator: "\n").first.map(String.init) ?? "0.0"
    }

    private func createDirectoriesIfNeeded(config: XProjectConfiguration) throws {
        let fileManager = fileManagerBuilder()
        let buildPath = config.buildPath()
        let reportsPath = config.reportsPath()

        try fileManager.createDirectory(atPath: buildPath, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: reportsPath, withIntermediateDirectories: true)
    }

    private func archivePath(filename: String, config: XProjectConfiguration) -> String {
        return "\(config.buildPath())/\(filename).xcarchive"
    }

    private func exportPath(filename: String, config: XProjectConfiguration) -> String {
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

    private func createExportPlist(signingConfiguration: SigningConfiguration?, config: XProjectConfiguration) throws -> String {
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

        let plistPath = "\(config.buildPath())/export.plist"
        let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)

        try plistData.write(to: URL(fileURLWithPath: plistPath))

        return plistPath
    }
}

// MARK: - Build Errors

public enum BuildError: Error, LocalizedError, Sendable {
    case environmentNotFound(String)
    case xcodeVersionNotFound(String)
    case configurationError(String)

    public var errorDescription: String? {
        switch self {
        case .environmentNotFound(let environment):
            return "Environment '\(environment)' not found in xcode.release configuration"
        case .xcodeVersionNotFound(let version):
            return "Xcode version \(version) not found"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}
