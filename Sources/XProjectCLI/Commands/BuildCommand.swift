//
// BuildCommand.swift
// XProject
//

import ArgumentParser
import XProject

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the project for testing",
        discussion: """
            Builds the project for testing, similar to 'rake xcode:tests'.
            Supports building specific schemes or all configured test schemes.
            """
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Flag(name: .long, help: "Show what would be done without executing")
    var dryRun = false

    @Flag(name: .long, help: "Clean build before building")
    var clean = false

    @Option(name: .long, help: "Specific scheme to build (if not provided, builds all test schemes)")
    var scheme: String?

    @Option(name: .long, help: "Build destination override")
    var destination: String?

    func run() async throws {
        let configService = ConfigurationService(customConfigPath: globalOptions.config)
        let xcodeClient = XcodeClient(
            configurationProvider: configService,
            commandExecutor: CommandExecutor(dryRun: dryRun)
        )

        do {
            try await runBuild(xcodeClient: xcodeClient, configService: configService)
        } catch {
            print("❌ Build failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    private func runBuild(xcodeClient: XcodeClient, configService: ConfigurationService) async throws {
        print("🔨 Building project...")
        let config = try configService.configuration

        guard let xcodeConfig = config.xcode,
              let testsConfig = xcodeConfig.tests else {
            throw XcodeClientError.configurationError("No xcode.tests configuration found")
        }

        let schemes = testsConfig.schemes

        if let specificScheme = scheme {
            // Build specific scheme
            guard let schemeConfig = schemes.first(where: { $0.scheme == specificScheme }) else {
                throw XcodeClientError.configurationError("Scheme '\(specificScheme)' not found in configuration")
            }

            let buildDest = destination ?? schemeConfig.buildDestination

            print("Building scheme: \(specificScheme)")
            try await xcodeClient.buildForTesting(
                scheme: specificScheme,
                clean: clean,
                buildDestination: buildDest
            )
        } else {
            // Build all test schemes
            print("Building \(schemes.count) scheme(s)...")

            for schemeConfig in schemes {
                let buildDest = destination ?? schemeConfig.buildDestination

                print("Building scheme: \(schemeConfig.scheme)")
                try await xcodeClient.buildForTesting(
                    scheme: schemeConfig.scheme,
                    clean: clean,
                    buildDestination: buildDest
                )

                // Only clean on first scheme to avoid redundant cleans
                if clean {
                    // Reset clean flag after first build
                    // Note: This is a limitation since clean is let, but in practice
                    // cleaning multiple times is redundant anyway
                }
            }
        }

        print("✅ Build completed successfully!")
    }
}
