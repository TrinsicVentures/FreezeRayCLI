import Foundation
import SwiftSyntax
import SwiftParser

// MARK: - Discovered Annotations

struct FreezeAnnotation: Sendable {
    let version: String
    let typeName: String
    let filePath: String
    let lineNumber: Int
}

struct MigrationPlan: Sendable {
    let typeName: String
    let filePath: String
    let lineNumber: Int
}

// MARK: - AST Visitor

class MacroDiscoveryVisitor: SyntaxVisitor {
    var freezeAnnotations: [FreezeAnnotation] = []
    var migrationPlans: [MigrationPlan] = []
    var currentFile: String = ""

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        // Look for @FreezeSchema(version: "X.Y.Z") or @FreezeRay.FreezeSchema(version: "X.Y.Z")
        for attribute in node.attributes {
            if let attr = attribute.as(AttributeSyntax.self) {
                let attrName = attr.attributeName.trimmedDescription

                // Handle both @FreezeSchema and @FreezeRay.FreezeSchema
                if attrName == "FreezeSchema" || attrName.hasSuffix(".FreezeSchema") {
                    if let version = extractVersion(from: attr) {
                        let lineNumber = node.position.utf8Offset
                        freezeAnnotations.append(FreezeAnnotation(
                            version: version,
                            typeName: node.name.text,
                            filePath: currentFile,
                            lineNumber: lineNumber
                        ))
                    }
                }
            }
        }

        // Look for SchemaMigrationPlan conformance
        if let inheritanceClause = node.inheritanceClause {
            for inheritedType in inheritanceClause.inheritedTypes {
                let typeName = inheritedType.type.trimmedDescription
                if typeName == "SchemaMigrationPlan" {
                    let lineNumber = node.position.utf8Offset
                    migrationPlans.append(MigrationPlan(
                        typeName: node.name.text,
                        filePath: currentFile,
                        lineNumber: lineNumber
                    ))
                }
            }
        }

        return .visitChildren
    }


    private func extractVersion(from attribute: AttributeSyntax) -> String? {
        guard let arguments = attribute.arguments else {
            return nil
        }

        // Handle LabeledExprListSyntax (argument list)
        if let labeledArgs = arguments.as(LabeledExprListSyntax.self) {
            for arg in labeledArgs {
                if arg.label?.text == "version" {
                    if let stringExpr = arg.expression.as(StringLiteralExprSyntax.self),
                       let segment = stringExpr.segments.first?.as(StringSegmentSyntax.self) {
                        return segment.content.text
                    }
                }
            }
        }

        return nil
    }
}

// MARK: - Discovery Result

struct DiscoveryResult: Sendable {
    let freezeAnnotations: [FreezeAnnotation]
    let migrationPlans: [MigrationPlan]
}

// MARK: - Discovery Function

/// Discovers all @FreezeSchema annotations and SchemaMigrationPlan conformances in the given source paths
func discoverMacros(in sourcePaths: [String]) throws -> DiscoveryResult {
    var allFreeze: [FreezeAnnotation] = []
    var allMigrationPlans: [MigrationPlan] = []

    for sourcePath in sourcePaths {
        let files = try findSwiftFiles(at: sourcePath)

        for file in files {
            let source = try String(contentsOfFile: file, encoding: .utf8)
            let tree = Parser.parse(source: source)

            let visitor = MacroDiscoveryVisitor(viewMode: .sourceAccurate)
            visitor.currentFile = file
            visitor.walk(tree)

            allFreeze.append(contentsOf: visitor.freezeAnnotations)
            allMigrationPlans.append(contentsOf: visitor.migrationPlans)
        }
    }

    return DiscoveryResult(
        freezeAnnotations: allFreeze,
        migrationPlans: allMigrationPlans
    )
}

/// Recursively finds all .swift files in a directory
func findSwiftFiles(at path: String) throws -> [String] {
    let fileManager = FileManager.default
    var swiftFiles: [String] = []

    // Check if path is a file or directory
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
        throw MacroDiscoveryError.pathNotFound(path)
    }

    if isDirectory.boolValue {
        // Recursively scan directory
        let enumerator = fileManager.enumerator(atPath: path)
        while let file = enumerator?.nextObject() as? String {
            if file.hasSuffix(".swift") {
                let fullPath = (path as NSString).appendingPathComponent(file)
                swiftFiles.append(fullPath)
            }
        }
    } else if path.hasSuffix(".swift") {
        // Single file
        swiftFiles.append(path)
    }

    return swiftFiles
}

// MARK: - Errors

enum MacroDiscoveryError: Error, CustomStringConvertible {
    case pathNotFound(String)
    case noSchemasFound

    var description: String {
        switch self {
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        case .noSchemasFound:
            return "No @FreezeSchema annotations found in source files"
        }
    }
}
