import ArgumentParser
import Foundation

public struct FreezeRayCLI: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "freezeray",
        abstract: "Freeze SwiftData schemas for safe production releases",
        version: "0.5.0",
        subcommands: [
            InitCommand.self,
            FreezeCommand.self,
            GenerateCommand.self,
        ],
        defaultSubcommand: nil
    )

    public init() {}
}
