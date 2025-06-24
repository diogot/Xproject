//
// SetupService.swift
// Xproject
//

import Foundation

// MARK: - Setup Service

public final class SetupService: Sendable {
    private let configService: ConfigurationService
    private let executor: any CommandExecuting
    private let verbose: Bool

    public init(configService: ConfigurationService = .shared, dryRun: Bool = false, verbose: Bool = false) {
        self.configService = configService
        self.executor = CommandExecutor(dryRun: dryRun)
        self.verbose = verbose
    }

    public init(configService: ConfigurationService = .shared, executor: any CommandExecuting, verbose: Bool = false) {
        self.configService = configService
        self.executor = executor
        self.verbose = verbose
    }

    /// Run the complete setup process
    public func runSetup() async throws {
        let config = try configService.configuration

        if let setup = config.setup, let brew = setup.brew, brew.enabled ?? true {
            try await setupBrew(brew)
        } else {
            print("ℹ️  No setup steps required")
        }
    }

    /// Setup Homebrew and install formulas
    public func setupBrew(_ brewConfig: BrewConfiguration) async throws {
        guard executor.commandExists("brew") else {
            throw SetupError.brewNotInstalled
        }

        try await updateHomebrew()
        try await installFormulas(brewConfig.formulas)
    }

    /// Update Homebrew with retry logic
    private func updateHomebrew() async throws {
        let command = "brew update"

        if verbose {
            print("🔄 Running: \(command)")
        } else {
            print("🔄 Updating Homebrew package list...")
        }

        do {
            _ = try await executeBrewCommand(command)
            print("✅ Homebrew package list updated")
        } catch {
            do {
                print("⚠️  brew update failed, retrying...")
                _ = try await executeBrewCommand(command)
                print("✅ Homebrew package list updated (after retry)")
            } catch {
                print("⚠️  brew update failed twice, continuing with potentially outdated package list: \(error.localizedDescription)")
            }
        }
    }

    /// Install the specified formulas
    private func installFormulas(_ formulas: [String]?) async throws {
        guard let formulas = formulas, !formulas.isEmpty else {
            return
        }

        print("📦 Processing \(formulas.count) formula\(formulas.count == 1 ? "" : "s")...")

        for (index, formula) in formulas.enumerated() {
            try await installFormula(formula, index: index, total: formulas.count)
        }

        print("✅ All formulas processed successfully")
    }

    /// Install a single formula
    private func installFormula(_ formula: String, index: Int, total: Int) async throws {
        let command = "( brew list \(formula) ) && " +
                      "( brew outdated \(formula) || brew upgrade \(formula) ) || " +
                      "( brew install \(formula) )"

        if verbose {
            print("🔄 Running formula commands for \(formula) (\(index + 1) of \(total))...")
        } else {
            print("🔄 Processing \(formula) (\(index + 1) of \(total))...")
        }

        do {
            _ = try await executeBrewCommand(command)
            print("✅ \(formula) is ready")
        } catch {
            throw SetupError.brewFormulaFailed(formula: formula, error: error)
        }
    }

    /// Execute a brew command using the appropriate execution method based on verbose mode
    private func executeBrewCommand(_ command: String) async throws -> CommandResult {
        if verbose {
            return try await executor.executeWithStreamingOutput(command)
        } else {
            return try executor.executeOrThrow(command)
        }
    }
}

// MARK: - Setup Errors

public enum SetupError: Error, LocalizedError, Sendable, Equatable {
    case brewNotInstalled
    case brewFormulaFailed(formula: String, error: Error)

    public var errorDescription: String? {
        switch self {
        case .brewNotInstalled:
            return "Homebrew not found. Please install Homebrew first: https://brew.sh"
        case let .brewFormulaFailed(formula, error):
            return "Failed to install \(formula): \(error.localizedDescription)"
        }
    }

    public static func == (lhs: SetupError, rhs: SetupError) -> Bool {
        switch (lhs, rhs) {
        case (.brewNotInstalled, .brewNotInstalled):
            return true
        case let (.brewFormulaFailed(formula1, _), .brewFormulaFailed(formula2, _)):
            // Compare only the formula name, not the error
            return formula1 == formula2
        default:
            return false
        }
    }
}
