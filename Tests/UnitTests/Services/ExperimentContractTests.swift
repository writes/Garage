import Foundation
import Testing
@testable import Garage

/// Pins the THREE copies of the experiment contract together: the Swift enums, the server
/// sanitizer's known-id/arm sets, and the server's mirror of the bundled registry. Each of them
/// silently degrades when the others move — an id the server drops never reaches the client, and
/// a bundled allocation the server does not know is refused as a re-weight of the open epoch.
/// Parsing the TypeScript source turns that three-way drift into a build failure.
struct ExperimentContractTests {
    private struct ContractParseFailure: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: - Assertions

    @Test func knownExperimentsMatchTheSwiftIdentifierEnum() throws {
        let ids = try Self.stringSet(named: "KNOWN_EXPERIMENTS", in: Self.serverSource())
        #expect(ids == Set(ExperimentID.allCases.map(\.rawValue)))
    }

    @Test func knownArmsMatchTheSwiftArmEnum() throws {
        let arms = try Self.stringSet(named: "KNOWN_ARMS", in: Self.serverSource())
        #expect(arms == Set(ExperimentArm.allCases.map(\.rawValue)))
    }

    @Test func theServerMirrorOfTheBundledRegistryMatchesTheShippedOne() throws {
        let mirrored = try Self.bundledRegistryMirror(in: Self.serverSource())
        // Order-sensitive by design: the assigner walks allocations as cumulative ranges.
        #expect(mirrored == ExperimentRegistry.bundled.definitions)
    }

    @Test func theServerMirrorCoversEveryKnownExperiment() throws {
        let source = try Self.serverSource()
        let mirrored = try Self.bundledRegistryMirror(in: source).map(\.id.rawValue)
        #expect(Set(mirrored) == (try Self.stringSet(named: "KNOWN_EXPERIMENTS", in: source)))
    }

    // MARK: - TypeScript source parsing

    private static func serverSource() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // UnitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let url = repoRoot.appendingPathComponent("CloudFunctions/src/functions/experimentConfig.ts")
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw ContractParseFailure(description: "experimentConfig.ts not readable at \(url.path)")
        }
        return source
    }

    /// `const NAME = new Set([...]);` — anchored to the declaration shape so a rename or a
    /// reshape fails the test instead of silently matching nothing.
    private static func stringSet(named name: String, in source: String) throws -> Set<String> {
        guard let body = try captures(#"const \#(name) = new Set\(\[([^\]]*)\]\);"#, in: source).first?.last else {
            throw ContractParseFailure(description: "\(name) declaration not found in experimentConfig.ts")
        }
        return Set(try captures(#""([a-z_]+)""#, in: body).compactMap(\.last))
    }

    /// `const BUNDLED_REGISTRY … = { <id>: { epoch: N, allocations: [ { arm, weight }, … ] }, … };`
    /// The mirror carries no kill flag — a bundled definition shipped as killed is a mismatch,
    /// which is the correct signal rather than something to paper over.
    private static func bundledRegistryMirror(in source: String) throws -> [ExperimentDefinition] {
        guard let block = try captures(
            #"const BUNDLED_REGISTRY[^=]*= \{(.*?)\n\};"#, in: source, options: [.dotMatchesLineSeparators]
        ).first?.last else {
            throw ContractParseFailure(description: "BUNDLED_REGISTRY declaration not found in experimentConfig.ts")
        }

        let entries = try captures(
            #"([a-z_]+):\s*\{\s*epoch:\s*(\d+),\s*allocations:\s*\[(.*?)\],\s*isKilled:\s*(true|false),\s*\},"#,
            in: block,
            options: [.dotMatchesLineSeparators]
        )
        guard !entries.isEmpty else {
            throw ContractParseFailure(description: "BUNDLED_REGISTRY has no parsable experiment entries")
        }

        return try entries.map { entry in
            guard entry.count == 5, let id = ExperimentID(rawValue: entry[1]), let epoch = Int(entry[2]) else {
                throw ContractParseFailure(description: "BUNDLED_REGISTRY entry is unparsable: \(entry)")
            }
            // The kill bit is part of the mirror: a bundle-killed epoch must be bundle-killed
            // on the server too, or the two sides disagree about whether a same-epoch non-kill
            // override is a revival.
            return ExperimentDefinition(
                id: id,
                epoch: epoch,
                allocations: try allocations(in: entry[3]),
                isKilled: entry[4] == "true"
            )
        }
    }

    private static func allocations(in body: String) throws -> [ArmAllocation] {
        try captures(#"\{\s*arm:\s*"([a-z_]+)",\s*weight:\s*(-?[\d.]+)\s*\}"#, in: body).map { match in
            guard match.count == 3, let arm = ExperimentArm(rawValue: match[1]), let weight = Double(match[2]) else {
                throw ContractParseFailure(description: "BUNDLED_REGISTRY allocation is unparsable: \(match)")
            }
            return ArmAllocation(arm: arm, weight: weight)
        }
    }

    private static func captures(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) throws -> [[String]] {
        let regex = try NSRegularExpression(pattern: pattern, options: options)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }
}
