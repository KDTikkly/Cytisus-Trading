import Foundation

enum FactorDSLError: Error, LocalizedError {
    case invalidDefinition(String)

    var errorDescription: String? {
        switch self {
        case .invalidDefinition(let message): return message
        }
    }
}

struct FactorOperatorDefinition {
    let name: String
    let minimumArguments: Int
    let maximumArguments: Int
    let missingValuePolicy: FactorMissingValuePolicy
    let crossSectional: Bool
    let temporalSafe: Bool
    let complexityCost: Int
}

indirect enum FactorExpressionNode {
    case field(String)
    case constant(Double)
    case operation(String, [FactorExpressionNode])
}

struct ParsedFactorExpression {
    let source: String
    let root: FactorExpressionNode
    let depth: Int
    let operatorCount: Int
    let minimumHistory: Int
}

struct FactorEvaluation {
    let values: [Double?]
    let coverage: Double
    let minimumHistory: Int
}

final class FactorDSLService {
    static let baseFields = Set([
        "open",
        "high",
        "low",
        "close",
        "volume",
        "returns",
        "market_return",
        "sector_return",
        "capital_flow"
    ])

    let operators: [String: FactorOperatorDefinition]

    init() {
        operators = [
            "lag": Self.definition("lag", 2, .propagate, false, 1),
            "delta": Self.definition("delta", 2, .propagate, false, 1),
            "rolling_mean": Self.definition(
                "rolling_mean", 2, .ignoreWindowMissing, false, 2
            ),
            "rolling_std": Self.definition(
                "rolling_std", 2, .ignoreWindowMissing, false, 2
            ),
            "rolling_rank": Self.definition(
                "rolling_rank", 2, .ignoreWindowMissing, false, 2
            ),
            "ema": Self.definition("ema", 2, .propagate, false, 2),
            "rolling_corr": Self.definition(
                "rolling_corr", 3, .ignoreWindowMissing, false, 3
            ),
            "rolling_beta": Self.definition(
                "rolling_beta", 3, .ignoreWindowMissing, false, 3
            ),
            "cross_section_rank": Self.definition(
                "cross_section_rank", 1, .crossSectionMedian, true, 2
            ),
            "zscore": Self.definition(
                "zscore", 1, .crossSectionMedian, true, 2
            ),
            "winsorize": Self.definition(
                "winsorize", 1, .crossSectionMedian, true, 2
            ),
            "sector_neutralize": Self.definition(
                "sector_neutralize", 1, .crossSectionMedian, true, 3
            ),
            "safe_divide": Self.definition(
                "safe_divide", 2, .propagate, false, 2
            ),
            "signed_power": Self.definition(
                "signed_power", 2, .propagate, false, 2
            ),
            "min": Self.definition("min", 2, .propagate, false, 1),
            "max": Self.definition("max", 2, .propagate, false, 1),
            "conditional": Self.definition(
                "conditional", 3, .propagate, false, 3
            )
        ]
    }

    func parse(
        _ expression: String,
        maximumDepth: Int = 8,
        maximumOperators: Int = 16
    ) throws -> ParsedFactorExpression {
        guard !expression.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
        expression.count <= 2048 else {
            throw FactorDSLError.invalidDefinition(
                "The expression is empty or exceeds 2048 characters."
            )
        }
        var parser = FactorExpressionParser(
            source: expression,
            fields: Self.baseFields,
            operators: operators
        )
        let root = try parser.parse()
        let expressionDepth = depth(root)
        let count = operatorCount(root)
        guard expressionDepth <= maximumDepth else {
            throw FactorDSLError.invalidDefinition(
                "The expression exceeds the maximum depth."
            )
        }
        guard count <= maximumOperators else {
            throw FactorDSLError.invalidDefinition(
                "The expression exceeds the maximum operator count."
            )
        }
        return ParsedFactorExpression(
            source: expression,
            root: root,
            depth: expressionDepth,
            operatorCount: count,
            minimumHistory: try validate(root)
        )
    }

    func evaluate(
        _ expression: ParsedFactorExpression,
        dataset: NormalizedResearchDataset
    ) throws -> FactorEvaluation {
        guard !dataset.observations.isEmpty else {
            return FactorEvaluation(
                values: [],
                coverage: 0,
                minimumHistory: expression.minimumHistory
            )
        }
        let values = try evaluateNode(expression.root, dataset: dataset)
        let coverage = Double(values.compactMap { $0 }.count) /
            Double(values.count)
        return FactorEvaluation(
            values: values,
            coverage: coverage,
            minimumHistory: expression.minimumHistory
        )
    }

    private func evaluateNode(
        _ node: FactorExpressionNode,
        dataset: NormalizedResearchDataset
    ) throws -> [Double?] {
        switch node {
        case .field(let name):
            return try dataset.observations.map {
                Optional(try $0.field(name))
            }
        case .constant(let value):
            return Array<Double?>(
                repeating: value,
                count: dataset.observations.count
            )
        case .operation(let name, let nodes):
            let arguments = try nodes.map {
                try evaluateNode($0, dataset: dataset)
            }
            switch name {
            case "lag":
                return lag(
                    arguments[0],
                    window: try window(nodes[1]),
                    dataset: dataset
                )
            case "delta":
                return binary(
                    arguments[0],
                    lag(
                        arguments[0],
                        window: try window(nodes[1]),
                        dataset: dataset
                    )
                ) { $0 - $1 }
            case "rolling_mean":
                return rolling(
                    arguments[0],
                    window: try window(nodes[1]),
                    dataset: dataset
                ) { $0.reduce(0, +) / Double($0.count) }
            case "rolling_std":
                return rolling(
                    arguments[0],
                    window: try window(nodes[1]),
                    dataset: dataset,
                    aggregate: Self.standardDeviation
                )
            case "rolling_rank":
                return rolling(
                    arguments[0],
                    window: try window(nodes[1]),
                    dataset: dataset,
                    aggregate: Self.rankOfLast
                )
            case "ema":
                return ema(
                    arguments[0],
                    window: try window(nodes[1]),
                    dataset: dataset
                )
            case "rolling_corr":
                return rollingPair(
                    arguments[0],
                    arguments[1],
                    window: try window(nodes[2]),
                    dataset: dataset,
                    aggregate: Self.correlation
                )
            case "rolling_beta":
                return rollingPair(
                    arguments[0],
                    arguments[1],
                    window: try window(nodes[2]),
                    dataset: dataset,
                    aggregate: Self.beta
                )
            case "cross_section_rank":
                return crossSection(
                    arguments[0],
                    dataset: dataset,
                    transform: Self.ranks
                )
            case "zscore":
                return crossSection(
                    arguments[0],
                    dataset: dataset,
                    transform: Self.zscores
                )
            case "winsorize":
                return crossSection(
                    arguments[0],
                    dataset: dataset,
                    transform: Self.winsorize
                )
            case "sector_neutralize":
                return sectorNeutralize(arguments[0], dataset: dataset)
            case "safe_divide":
                return binary(arguments[0], arguments[1]) {
                    abs($1) < 1e-12 ? nil : $0 / $1
                }
            case "signed_power":
                return binary(arguments[0], arguments[1]) {
                    ($0 < 0 ? -1 : 1) * pow(abs($0), $1)
                }
            case "min":
                return binary(arguments[0], arguments[1]) {
                    Swift.min($0, $1)
                }
            case "max":
                return binary(arguments[0], arguments[1]) {
                    Swift.max($0, $1)
                }
            case "conditional":
                return zip(
                    arguments[0],
                    zip(arguments[1], arguments[2])
                ).map { condition, values in
                    guard let condition else { return nil }
                    return condition > 0 ? values.0 : values.1
                }
            default:
                throw FactorDSLError.invalidDefinition(
                    "Unknown DSL operator."
                )
            }
        }
    }

    private func lag(
        _ values: [Double?],
        window: Int,
        dataset: NormalizedResearchDataset
    ) -> [Double?] {
        var result = Array<Double?>(
            repeating: nil,
            count: values.count
        )
        for indices in symbolIndices(dataset).values {
            guard indices.count > window else { continue }
            for offset in window..<indices.count {
                result[indices[offset]] = values[indices[offset - window]]
            }
        }
        return result
    }

    private func rolling(
        _ values: [Double?],
        window: Int,
        dataset: NormalizedResearchDataset,
        aggregate: ([Double]) -> Double
    ) -> [Double?] {
        var result = Array<Double?>(
            repeating: nil,
            count: values.count
        )
        for indices in symbolIndices(dataset).values {
            guard indices.count >= window else { continue }
            for offset in (window - 1)..<indices.count {
                let sample = indices[(offset - window + 1)...offset]
                    .compactMap { values[$0] }
                if sample.count == window {
                    result[indices[offset]] = aggregate(sample)
                }
            }
        }
        return result
    }

    private func rollingPair(
        _ left: [Double?],
        _ right: [Double?],
        window: Int,
        dataset: NormalizedResearchDataset,
        aggregate: ([Double], [Double]) -> Double?
    ) -> [Double?] {
        var result = Array<Double?>(
            repeating: nil,
            count: left.count
        )
        for indices in symbolIndices(dataset).values {
            guard indices.count >= window else { continue }
            for offset in (window - 1)..<indices.count {
                let sample = Array(
                    indices[(offset - window + 1)...offset]
                )
                let pairs = sample.compactMap { index -> (Double, Double)? in
                    guard let first = left[index],
                          let second = right[index] else {
                        return nil
                    }
                    return (first, second)
                }
                if pairs.count == window {
                    result[indices[offset]] = aggregate(
                        pairs.map(\.0),
                        pairs.map(\.1)
                    )
                }
            }
        }
        return result
    }

    private func ema(
        _ values: [Double?],
        window: Int,
        dataset: NormalizedResearchDataset
    ) -> [Double?] {
        var result = Array<Double?>(
            repeating: nil,
            count: values.count
        )
        let alpha = 2.0 / Double(window + 1)
        for indices in symbolIndices(dataset).values {
            var previous: Double?
            var seen = 0
            for index in indices {
                guard let value = values[index] else { continue }
                previous = previous.map {
                    alpha * value + (1 - alpha) * $0
                } ?? value
                seen += 1
                if seen >= window {
                    result[index] = previous
                }
            }
        }
        return result
    }

    private func crossSection(
        _ values: [Double?],
        dataset: NormalizedResearchDataset,
        transform: ([Double]) -> [Double]
    ) -> [Double?] {
        var result = Array<Double?>(
            repeating: nil,
            count: values.count
        )
        let groups = Dictionary(grouping: values.indices) {
            Calendar(identifier: .gregorian).startOfDay(
                for: dataset.observations[$0].eventTime
            )
        }
        for indices in groups.values {
            let available = indices.filter { values[$0] != nil }
            let transformed = transform(available.compactMap { values[$0] })
            for (offset, index) in available.enumerated() {
                result[index] = transformed[offset]
            }
        }
        return result
    }

    private func sectorNeutralize(
        _ values: [Double?],
        dataset: NormalizedResearchDataset
    ) -> [Double?] {
        var result = Array<Double?>(
            repeating: nil,
            count: values.count
        )
        let groups = Dictionary(grouping: values.indices) { index in
            let day = Calendar(identifier: .gregorian).startOfDay(
                for: dataset.observations[index].eventTime
            )
            return "\(day.timeIntervalSince1970)|" +
                dataset.observations[index].industry
        }
        for indices in groups.values {
            let available = indices.filter { values[$0] != nil }
            guard !available.isEmpty else { continue }
            let mean = available.compactMap { values[$0] }.reduce(0, +) /
                Double(available.count)
            for index in available {
                result[index] = values[index].map { $0 - mean }
            }
        }
        return result
    }

    private func binary(
        _ left: [Double?],
        _ right: [Double?],
        operation: (Double, Double) -> Double?
    ) -> [Double?] {
        zip(left, right).map { first, second in
            guard let first, let second else { return nil }
            return operation(first, second)
        }
    }

    private func symbolIndices(
        _ dataset: NormalizedResearchDataset
    ) -> [String: [Int]] {
        Dictionary(grouping: dataset.observations.indices) {
            dataset.observations[$0].symbol
        }.mapValues { indices in
            indices.sorted {
                dataset.observations[$0].eventTime <
                    dataset.observations[$1].eventTime
            }
        }
    }

    private func validate(_ node: FactorExpressionNode) throws -> Int {
        switch node {
        case .field, .constant:
            return 1
        case .operation(let name, let arguments):
            let childHistory = try arguments.map(validate).max() ?? 1
            if [
                "lag",
                "delta",
                "rolling_mean",
                "rolling_std",
                "rolling_rank",
                "ema"
            ].contains(name) {
                return childHistory + (try window(arguments[1]))
            }
            if ["rolling_corr", "rolling_beta"].contains(name) {
                return childHistory + (try window(arguments[2]))
            }
            if name == "signed_power",
               case .constant(let exponent) = arguments[1],
               abs(exponent) > 3 {
                throw FactorDSLError.invalidDefinition(
                    "Signed power is bounded to an absolute exponent of 3."
                )
            }
            return childHistory
        }
    }

    private func window(_ node: FactorExpressionNode) throws -> Int {
        guard case .constant(let value) = node,
              value >= 1,
              value <= 252,
              abs(value.rounded() - value) < 0.000001 else {
            throw FactorDSLError.invalidDefinition(
                "Temporal safety requires an integer window from 1 through 252; future references are prohibited."
            )
        }
        return Int(value)
    }

    private func depth(_ node: FactorExpressionNode) -> Int {
        switch node {
        case .field, .constant: return 1
        case .operation(_, let arguments):
            return 1 + (arguments.map(depth).max() ?? 0)
        }
    }

    private func operatorCount(_ node: FactorExpressionNode) -> Int {
        switch node {
        case .field, .constant: return 0
        case .operation(_, let arguments):
            return 1 + arguments.map(operatorCount).reduce(0, +)
        }
    }

    private static func definition(
        _ name: String,
        _ argumentCount: Int,
        _ policy: FactorMissingValuePolicy,
        _ crossSectional: Bool,
        _ cost: Int
    ) -> FactorOperatorDefinition {
        FactorOperatorDefinition(
            name: name,
            minimumArguments: argumentCount,
            maximumArguments: argumentCount,
            missingValuePolicy: policy,
            crossSectional: crossSectional,
            temporalSafe: true,
            complexityCost: cost
        )
    }

    static func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return sqrt(
            values.map { pow($0 - mean, 2) }.reduce(0, +) /
                Double(values.count)
        )
    }

    static func rankOfLast(_ values: [Double]) -> Double {
        guard values.count > 1, let target = values.last else { return 0.5 }
        let below = values.filter { $0 < target }.count
        let equal = values.filter { abs($0 - target) < 1e-12 }.count
        return (Double(below) + 0.5 * Double(equal - 1)) /
            Double(values.count - 1)
    }

    static func ranks(_ values: [Double]) -> [Double] {
        guard values.count > 1 else {
            return values.map { _ in 0.5 }
        }
        return values.map { value in
            let below = values.filter { $0 < value }.count
            let equal = values.filter { abs($0 - value) < 1e-12 }.count
            return (Double(below) + 0.5 * Double(equal - 1)) /
                Double(values.count - 1)
        }
    }

    static func zscores(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }
        let mean = values.reduce(0, +) / Double(values.count)
        let deviation = standardDeviation(values)
        return values.map {
            deviation < 1e-12 ? 0 : ($0 - mean) / deviation
        }
    }

    static func winsorize(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }
        let ordered = values.sorted()
        let low = ordered[
            Int(floor(Double(ordered.count - 1) * 0.05))
        ]
        let high = ordered[
            Int(ceil(Double(ordered.count - 1) * 0.95))
        ]
        return values.map { Swift.min(Swift.max($0, low), high) }
    }

    static func correlation(
        _ left: [Double],
        _ right: [Double]
    ) -> Double? {
        guard left.count == right.count, left.count >= 2 else { return nil }
        let leftMean = left.reduce(0, +) / Double(left.count)
        let rightMean = right.reduce(0, +) / Double(right.count)
        var numerator = 0.0
        var leftVariance = 0.0
        var rightVariance = 0.0
        for index in left.indices {
            let first = left[index] - leftMean
            let second = right[index] - rightMean
            numerator += first * second
            leftVariance += first * first
            rightVariance += second * second
        }
        let denominator = sqrt(leftVariance * rightVariance)
        return denominator < 1e-12 ? 0 : numerator / denominator
    }

    static func beta(_ left: [Double], _ right: [Double]) -> Double? {
        guard left.count == right.count, left.count >= 2 else { return nil }
        let leftMean = left.reduce(0, +) / Double(left.count)
        let rightMean = right.reduce(0, +) / Double(right.count)
        var covariance = 0.0
        var variance = 0.0
        for index in left.indices {
            covariance += (left[index] - leftMean) *
                (right[index] - rightMean)
            variance += pow(right[index] - rightMean, 2)
        }
        return variance < 1e-12 ? 0 : covariance / variance
    }
}

private struct FactorExpressionParser {
    let source: String
    let fields: Set<String>
    let operators: [String: FactorOperatorDefinition]
    private var index: String.Index

    init(
        source: String,
        fields: Set<String>,
        operators: [String: FactorOperatorDefinition]
    ) {
        self.source = source
        self.fields = fields
        self.operators = operators
        index = source.startIndex
    }

    mutating func parse() throws -> FactorExpressionNode {
        let node = try parseExpression()
        skipWhitespace()
        guard index == source.endIndex else {
            throw FactorDSLError.invalidDefinition(
                "Unexpected trailing DSL input."
            )
        }
        return node
    }

    private mutating func parseExpression() throws -> FactorExpressionNode {
        skipWhitespace()
        if let character = current,
           character.isNumber || character == "-" || character == "." {
            return .constant(try parseNumber())
        }
        let identifier = try parseIdentifier()
        skipWhitespace()
        guard current == "(" else {
            guard fields.contains(identifier) else {
                throw FactorDSLError.invalidDefinition(
                    "Unknown or arbitrary identifier: \(identifier)"
                )
            }
            return .field(identifier)
        }
        guard let definition = operators[identifier] else {
            throw FactorDSLError.invalidDefinition(
                "Unknown DSL operator: \(identifier)"
            )
        }
        advance()
        var arguments: [FactorExpressionNode] = []
        skipWhitespace()
        if current != ")" {
            while true {
                arguments.append(try parseExpression())
                skipWhitespace()
                if current == "," {
                    advance()
                    continue
                }
                break
            }
        }
        guard current == ")" else {
            throw FactorDSLError.invalidDefinition(
                "Expected a closing parenthesis."
            )
        }
        advance()
        guard arguments.count >= definition.minimumArguments,
              arguments.count <= definition.maximumArguments else {
            throw FactorDSLError.invalidDefinition(
                "\(identifier) received an invalid argument count."
            )
        }
        return .operation(identifier, arguments)
    }

    private mutating func parseIdentifier() throws -> String {
        let start = index
        while let character = current,
              character.isLetter || character.isNumber ||
                character == "_" {
            advance()
        }
        guard start != index else {
            throw FactorDSLError.invalidDefinition(
                "Expected a DSL field or operator."
            )
        }
        return String(source[start..<index])
    }

    private mutating func parseNumber() throws -> Double {
        let start = index
        if current == "-" { advance() }
        while let character = current,
              character.isNumber || character == "." {
            advance()
        }
        guard let value = Double(String(source[start..<index])),
              value.isFinite,
              abs(value) <= 1000 else {
            throw FactorDSLError.invalidDefinition(
                "Constants must be finite and bounded to 1000."
            )
        }
        return value
    }

    private mutating func skipWhitespace() {
        while let character = current, character.isWhitespace {
            advance()
        }
    }

    private var current: Character? {
        index < source.endIndex ? source[index] : nil
    }

    private mutating func advance() {
        guard index < source.endIndex else { return }
        index = source.index(after: index)
    }
}
