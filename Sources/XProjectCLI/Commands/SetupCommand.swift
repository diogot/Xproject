import ArgumentParser
import XProject
import Foundation

struct SetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Setup project dependencies and environment"
    )
    
    func run() throws {
        print("🔧 Setting up project...")
        
        let setupService = SetupService()
        
        do {
            try setupService.runSetup()
            print("✅ Setup completed!")
        } catch let error as SetupError {
            switch error {
            case .brewNotInstalled:
                print("❌ \(error.localizedDescription)")
            case .brewFormulaFailed(let formula, _):
                print("❌ Failed to install \(formula): \(error.localizedDescription)")
            }
            throw ExitCode.failure
        }
    }
}