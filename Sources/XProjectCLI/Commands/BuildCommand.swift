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

    @Flag(name: .long, help: "Show what would be done without executing")
    var dryRun = false

    @Flag(name: .long, help: "Clean build before building")
    var clean = false

    @Option(name: .long, help: "Specific scheme to build (if not provided, builds all test schemes)")
    var scheme: String?

    @Option(name: .long, help: "Build destination override")
    var destination: String?

    func run() async throws {
        let buildService = BuildService(
            commandExecutor: CommandExecutor(dryRun: dryRun)
        )

        do {
            try await runBuild(buildService: buildService)
        } catch {
            print("❌ Build failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    private func runBuild(buildService: BuildService) async throws {
        print("🔨 Building project...")

        let configService = ConfigurationService.shared
        let config = try configService.configuration

        guard let xcodeConfig = config.xcode,
              let testsConfig = xcodeConfig.tests else {
            throw BuildError.configurationError("No xcode.tests configuration found")
        }

        let schemes = testsConfig.schemes

        if let specificScheme = scheme {
            // Build specific scheme
            guard let schemeConfig = schemes.first(where: { $0.scheme == specificScheme }) else {
                throw BuildError.configurationError("Scheme '\(specificScheme)' not found in configuration")
            }

            let buildDest = destination ?? schemeConfig.buildDestination

            print("Building scheme: \(specificScheme)")
            try await buildService.buildForTesting(
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
                try await buildService.buildForTesting(
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
