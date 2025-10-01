//
// OutputFormatter.swift
// Xproject
//

import Foundation

/// Utility for formatting command output consistently
public enum OutputFormatter {
    /// Print information block at the start of command execution
    /// Shows working directory and configuration file when non-default or in verbose mode
    public static func printInfoBlock(
        workingDirectory: String,
        configFile: String?,
        verbose: Bool
    ) {
        let currentDirectory = FileManager.default.currentDirectoryPath
        let isNonDefaultDirectory = workingDirectory != currentDirectory

        // Determine if we should print anything
        let shouldPrintWorkingDir = verbose || isNonDefaultDirectory
        let shouldPrintConfig = verbose || configFile != nil

        // Only print if there's something to show
        guard shouldPrintWorkingDir || shouldPrintConfig else {
            return
        }

        // Print working directory if needed
        if shouldPrintWorkingDir {
            let displayPath = verbose
                ? URL(fileURLWithPath: workingDirectory).standardized.path
                : workingDirectory
            print("Working Directory: \(displayPath)")
        }

        // Print configuration file if needed
        if shouldPrintConfig, let configFile = configFile {
            print("Configuration: \(configFile)")
        }

        // Add blank line after info block for spacing
        print("")
    }
}
