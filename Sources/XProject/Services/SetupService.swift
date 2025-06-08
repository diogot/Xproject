import Foundation

// MARK: - Setup Service

public final class SetupService: Sendable {
    private let configService: ConfigurationService
    private let executor: CommandExecutor
    
    public init(configService: ConfigurationService = .shared, executor: CommandExecutor = CommandExecutor()) {
        self.configService = configService
        self.executor = executor
    }
    
    /// Run the complete setup process
    public func runSetup() throws {
        let config = try configService.configuration
        
        // Only run brew setup since other dependency managers are deprecated
        if let setup = config.setup, let brew = setup.brew, brew.enabled {
            try setupBrew(brew)
        }
    }
    
    /// Setup Homebrew and install formulas
    public func setupBrew(_ brewConfig: BrewConfiguration) throws {
        // Check if brew is installed
        guard executor.commandExists("brew") else {
            throw SetupError.brewNotInstalled
        }
        
        // Update brew
        do {
            try executor.executeOrThrow("brew update")
        } catch {
            // Continue if update fails
        }
        
        // Install formulas if specified
        if let formulas = brewConfig.formulas, !formulas.isEmpty {
            for formula in formulas {
                do {
                    let command = "( brew list \(formula) ) && ( brew outdated \(formula) || brew upgrade \(formula) ) || ( brew install \(formula) )"
                    try executor.executeOrThrow(command)
                } catch {
                    throw SetupError.brewFormulaFailed(formula: formula, error: error)
                }
            }
        }
    }
}

// MARK: - Setup Errors

public enum SetupError: Error, LocalizedError, Sendable {
    case brewNotInstalled
    case brewFormulaFailed(formula: String, error: Error)
    
    public var errorDescription: String? {
        switch self {
        case .brewNotInstalled:
            return "Homebrew not found. Please install Homebrew first: https://brew.sh"
        case .brewFormulaFailed(let formula, let error):
            return "Failed to install \(formula): \(error.localizedDescription)"
        }
    }
}