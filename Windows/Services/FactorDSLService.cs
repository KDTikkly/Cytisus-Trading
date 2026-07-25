using System.Globalization;

namespace CytisusTrading.Windows;

public sealed record FactorOperatorDefinition(
    string Name,
    int MinimumArguments,
    int MaximumArguments,
    FactorMissingValuePolicy MissingValuePolicy,
    bool CrossSectional,
    bool TemporalSafe,
    int ComplexityCost);

public abstract record FactorExpressionNode;

public sealed record FactorFieldNode(string Name) : FactorExpressionNode;

public sealed record FactorConstantNode(double Value) : FactorExpressionNode;

public sealed record FactorOperatorNode(
    string Name,
    IReadOnlyList<FactorExpressionNode> Arguments) : FactorExpressionNode;

public sealed record ParsedFactorExpression(
    string Source,
    FactorExpressionNode Root,
    int Depth,
    int OperatorCount,
    int MinimumHistory);

public sealed record FactorEvaluation(
    IReadOnlyList<double?> Values,
    double Coverage,
    int MinimumHistory);

public interface IFactorDSLService
{
    ParsedFactorExpression Parse(
        string expression,
        int maximumDepth = 8,
        int maximumOperators = 16);
    FactorEvaluation Evaluate(
        ParsedFactorExpression expression,
        NormalizedResearchDataset dataset);
    IReadOnlyDictionary<string, FactorOperatorDefinition> Operators { get; }
}

public sealed class FactorDSLService : IFactorDSLService
{
    private static readonly IReadOnlySet<string> BaseFields =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "open",
            "high",
            "low",
            "close",
            "volume",
            "returns",
            "market_return",
            "sector_return",
            "capital_flow"
        };

    public FactorDSLService()
    {
        Operators = new Dictionary<string, FactorOperatorDefinition>(
            StringComparer.Ordinal)
        {
            ["lag"] = Operator("lag", 2, 2, FactorMissingValuePolicy.Propagate, false, 1),
            ["delta"] = Operator("delta", 2, 2, FactorMissingValuePolicy.Propagate, false, 1),
            ["rolling_mean"] = Operator("rolling_mean", 2, 2, FactorMissingValuePolicy.IgnoreWindowMissing, false, 2),
            ["rolling_std"] = Operator("rolling_std", 2, 2, FactorMissingValuePolicy.IgnoreWindowMissing, false, 2),
            ["rolling_rank"] = Operator("rolling_rank", 2, 2, FactorMissingValuePolicy.IgnoreWindowMissing, false, 2),
            ["ema"] = Operator("ema", 2, 2, FactorMissingValuePolicy.Propagate, false, 2),
            ["rolling_corr"] = Operator("rolling_corr", 3, 3, FactorMissingValuePolicy.IgnoreWindowMissing, false, 3),
            ["rolling_beta"] = Operator("rolling_beta", 3, 3, FactorMissingValuePolicy.IgnoreWindowMissing, false, 3),
            ["cross_section_rank"] = Operator("cross_section_rank", 1, 1, FactorMissingValuePolicy.CrossSectionMedian, true, 2),
            ["zscore"] = Operator("zscore", 1, 1, FactorMissingValuePolicy.CrossSectionMedian, true, 2),
            ["winsorize"] = Operator("winsorize", 1, 1, FactorMissingValuePolicy.CrossSectionMedian, true, 2),
            ["sector_neutralize"] = Operator("sector_neutralize", 1, 1, FactorMissingValuePolicy.CrossSectionMedian, true, 3),
            ["safe_divide"] = Operator("safe_divide", 2, 2, FactorMissingValuePolicy.Propagate, false, 2),
            ["signed_power"] = Operator("signed_power", 2, 2, FactorMissingValuePolicy.Propagate, false, 2),
            ["min"] = Operator("min", 2, 2, FactorMissingValuePolicy.Propagate, false, 1),
            ["max"] = Operator("max", 2, 2, FactorMissingValuePolicy.Propagate, false, 1),
            ["conditional"] = Operator("conditional", 3, 3, FactorMissingValuePolicy.Propagate, false, 3)
        };
    }

    public IReadOnlyDictionary<string, FactorOperatorDefinition> Operators
    {
        get;
    }

    public ParsedFactorExpression Parse(
        string expression,
        int maximumDepth = 8,
        int maximumOperators = 16)
    {
        if (string.IsNullOrWhiteSpace(expression) ||
            expression.Length > 2048)
        {
            throw new FactorDSLException(
                "The expression is empty or exceeds 2048 characters.");
        }
        var parser = new Parser(expression, BaseFields, Operators);
        var root = parser.Parse();
        var depth = Depth(root);
        var operators = OperatorCount(root);
        if (depth > maximumDepth)
        {
            throw new FactorDSLException(
                "The expression exceeds the maximum depth.");
        }
        if (operators > maximumOperators)
        {
            throw new FactorDSLException(
                "The expression exceeds the maximum operator count.");
        }
        var minimumHistory = Validate(root);
        return new ParsedFactorExpression(
            expression,
            root,
            depth,
            operators,
            minimumHistory);
    }

    public FactorEvaluation Evaluate(
        ParsedFactorExpression expression,
        NormalizedResearchDataset dataset)
    {
        if (dataset.Observations.Count == 0)
        {
            return new FactorEvaluation(
                Array.Empty<double?>(),
                0,
                expression.MinimumHistory);
        }
        var values = EvaluateNode(expression.Root, dataset);
        var available = values.Count(value => value.HasValue);
        return new FactorEvaluation(
            values,
            available / (double)values.Count,
            expression.MinimumHistory);
    }

    private IReadOnlyList<double?> EvaluateNode(
        FactorExpressionNode node,
        NormalizedResearchDataset dataset)
    {
        switch (node)
        {
            case FactorFieldNode field:
                return dataset.Observations
                    .Select(observation => (double?)observation.Field(field.Name))
                    .ToArray();
            case FactorConstantNode constant:
                return Enumerable
                    .Repeat<double?>(constant.Value, dataset.Observations.Count)
                    .ToArray();
            case FactorOperatorNode operation:
                return EvaluateOperation(operation, dataset);
            default:
                throw new FactorDSLException(
                    "Unknown expression node.");
        }
    }

    private IReadOnlyList<double?> EvaluateOperation(
        FactorOperatorNode operation,
        NormalizedResearchDataset dataset)
    {
        var arguments = operation.Arguments
            .Select(argument => EvaluateNode(argument, dataset))
            .ToArray();
        return operation.Name switch
        {
            "lag" => Lag(
                arguments[0],
                Window(operation, 1),
                dataset),
            "delta" => Binary(
                arguments[0],
                Lag(arguments[0], Window(operation, 1), dataset),
                (left, right) => left - right),
            "rolling_mean" => Rolling(
                arguments[0],
                Window(operation, 1),
                dataset,
                values => values.Average()),
            "rolling_std" => Rolling(
                arguments[0],
                Window(operation, 1),
                dataset,
                StandardDeviation),
            "rolling_rank" => Rolling(
                arguments[0],
                Window(operation, 1),
                dataset,
                values => RankOfLast(values)),
            "ema" => EMA(
                arguments[0],
                Window(operation, 1),
                dataset),
            "rolling_corr" => RollingPair(
                arguments[0],
                arguments[1],
                Window(operation, 2),
                dataset,
                Correlation),
            "rolling_beta" => RollingPair(
                arguments[0],
                arguments[1],
                Window(operation, 2),
                dataset,
                Beta),
            "cross_section_rank" => CrossSection(
                arguments[0],
                dataset,
                values => Ranks(values)),
            "zscore" => CrossSection(
                arguments[0],
                dataset,
                values => ZScores(values)),
            "winsorize" => CrossSection(
                arguments[0],
                dataset,
                values => Winsorize(values)),
            "sector_neutralize" => SectorNeutralize(
                arguments[0],
                dataset),
            "safe_divide" => Binary(
                arguments[0],
                arguments[1],
                (left, right) => Math.Abs(right) < 1e-12
                    ? null
                    : left / right),
            "signed_power" => Binary(
                arguments[0],
                arguments[1],
                (left, right) => Math.Sign(left) *
                    Math.Pow(Math.Abs(left), right)),
            "min" => Binary(
                arguments[0],
                arguments[1],
                Math.Min),
            "max" => Binary(
                arguments[0],
                arguments[1],
                Math.Max),
            "conditional" => Conditional(
                arguments[0],
                arguments[1],
                arguments[2]),
            _ => throw new FactorDSLException(
                "Unknown DSL operator.")
        };
    }

    private static IReadOnlyList<double?> Lag(
        IReadOnlyList<double?> values,
        int window,
        NormalizedResearchDataset dataset)
    {
        var result = new double?[values.Count];
        foreach (var indices in SymbolIndices(dataset).Values)
        {
            for (var offset = window; offset < indices.Count; offset += 1)
            {
                result[indices[offset]] = values[indices[offset - window]];
            }
        }
        return result;
    }

    private static IReadOnlyList<double?> Rolling(
        IReadOnlyList<double?> values,
        int window,
        NormalizedResearchDataset dataset,
        Func<IReadOnlyList<double>, double> aggregate)
    {
        var result = new double?[values.Count];
        foreach (var indices in SymbolIndices(dataset).Values)
        {
            for (var offset = window - 1; offset < indices.Count; offset += 1)
            {
                var sample = indices
                    .Skip(offset - window + 1)
                    .Take(window)
                    .Select(index => values[index])
                    .Where(value => value.HasValue)
                    .Select(value => value!.Value)
                    .ToArray();
                if (sample.Length == window)
                {
                    result[indices[offset]] = aggregate(sample);
                }
            }
        }
        return result;
    }

    private static IReadOnlyList<double?> RollingPair(
        IReadOnlyList<double?> left,
        IReadOnlyList<double?> right,
        int window,
        NormalizedResearchDataset dataset,
        Func<IReadOnlyList<double>, IReadOnlyList<double>, double?> aggregate)
    {
        var result = new double?[left.Count];
        foreach (var indices in SymbolIndices(dataset).Values)
        {
            for (var offset = window - 1; offset < indices.Count; offset += 1)
            {
                var pairs = indices
                    .Skip(offset - window + 1)
                    .Take(window)
                    .Select(index => (Left: left[index], Right: right[index]))
                    .Where(pair =>
                        pair.Left.HasValue &&
                        pair.Right.HasValue)
                    .ToArray();
                if (pairs.Length == window)
                {
                    result[indices[offset]] = aggregate(
                        pairs.Select(pair => pair.Left!.Value).ToArray(),
                        pairs.Select(pair => pair.Right!.Value).ToArray());
                }
            }
        }
        return result;
    }

    private static IReadOnlyList<double?> EMA(
        IReadOnlyList<double?> values,
        int window,
        NormalizedResearchDataset dataset)
    {
        var result = new double?[values.Count];
        var alpha = 2.0 / (window + 1);
        foreach (var indices in SymbolIndices(dataset).Values)
        {
            double? previous = null;
            var seen = 0;
            foreach (var index in indices)
            {
                if (!values[index].HasValue)
                {
                    continue;
                }
                previous = previous.HasValue
                    ? alpha * values[index]!.Value +
                        (1 - alpha) * previous.Value
                    : values[index]!.Value;
                seen += 1;
                if (seen >= window)
                {
                    result[index] = previous;
                }
            }
        }
        return result;
    }

    private static IReadOnlyList<double?> CrossSection(
        IReadOnlyList<double?> values,
        NormalizedResearchDataset dataset,
        Func<IReadOnlyList<double>, IReadOnlyList<double>> transform)
    {
        var result = new double?[values.Count];
        var dateGroups = Enumerable.Range(0, values.Count)
            .GroupBy(index =>
                dataset.Observations[index].EventTime.UtcDateTime.Date);
        foreach (var group in dateGroups)
        {
            var available = group
                .Where(index => values[index].HasValue)
                .ToArray();
            var transformed = transform(
                available.Select(index => values[index]!.Value).ToArray());
            for (var index = 0; index < available.Length; index += 1)
            {
                result[available[index]] = transformed[index];
            }
        }
        return result;
    }

    private static IReadOnlyList<double?> SectorNeutralize(
        IReadOnlyList<double?> values,
        NormalizedResearchDataset dataset)
    {
        var result = new double?[values.Count];
        var groups = Enumerable.Range(0, values.Count)
            .GroupBy(index => (
                dataset.Observations[index].EventTime.UtcDateTime.Date,
                dataset.Observations[index].Industry));
        foreach (var group in groups)
        {
            var available = group
                .Where(index => values[index].HasValue)
                .ToArray();
            if (available.Length == 0)
            {
                continue;
            }
            var mean = available
                .Select(index => values[index]!.Value)
                .Average();
            foreach (var index in available)
            {
                result[index] = values[index]!.Value - mean;
            }
        }
        return result;
    }

    private static IReadOnlyList<double?> Binary(
        IReadOnlyList<double?> left,
        IReadOnlyList<double?> right,
        Func<double, double, double?> operation)
    {
        var result = new double?[left.Count];
        for (var index = 0; index < left.Count; index += 1)
        {
            if (left[index].HasValue && right[index].HasValue)
            {
                result[index] = operation(
                    left[index]!.Value,
                    right[index]!.Value);
            }
        }
        return result;
    }

    private static IReadOnlyList<double?> Binary(
        IReadOnlyList<double?> left,
        IReadOnlyList<double?> right,
        Func<double, double, double> operation)
    {
        return Binary(
            left,
            right,
            (first, second) => (double?)operation(first, second));
    }

    private static IReadOnlyList<double?> Conditional(
        IReadOnlyList<double?> condition,
        IReadOnlyList<double?> whenTrue,
        IReadOnlyList<double?> whenFalse)
    {
        var result = new double?[condition.Count];
        for (var index = 0; index < condition.Count; index += 1)
        {
            if (condition[index].HasValue)
            {
                result[index] = condition[index]!.Value > 0
                    ? whenTrue[index]
                    : whenFalse[index];
            }
        }
        return result;
    }

    private static IReadOnlyDictionary<string, IReadOnlyList<int>>
        SymbolIndices(NormalizedResearchDataset dataset)
    {
        return Enumerable.Range(0, dataset.Observations.Count)
            .GroupBy(index => dataset.Observations[index].Symbol)
            .ToDictionary(
                group => group.Key,
                group => (IReadOnlyList<int>)group
                    .OrderBy(index =>
                        dataset.Observations[index].EventTime)
                    .ToArray(),
                StringComparer.Ordinal);
    }

    private static int Validate(FactorExpressionNode node)
    {
        switch (node)
        {
            case FactorFieldNode:
            case FactorConstantNode:
                return 1;
            case FactorOperatorNode operation:
                var childHistory = operation.Arguments
                    .Select(Validate)
                    .DefaultIfEmpty(1)
                    .Max();
                if (operation.Name is
                    "lag" or
                    "delta" or
                    "rolling_mean" or
                    "rolling_std" or
                    "rolling_rank" or
                    "ema")
                {
                    return childHistory + Window(operation, 1);
                }
                if (operation.Name is "rolling_corr" or "rolling_beta")
                {
                    return childHistory + Window(operation, 2);
                }
                if (operation.Name == "signed_power" &&
                    operation.Arguments[1] is FactorConstantNode power &&
                    Math.Abs(power.Value) > 3)
                {
                    throw new FactorDSLException(
                        "Signed power is bounded to an absolute exponent of 3.");
                }
                return childHistory;
            default:
                throw new FactorDSLException("Unknown expression node.");
        }
    }

    private static int Window(
        FactorOperatorNode operation,
        int argumentIndex)
    {
        if (operation.Arguments[argumentIndex] is not
            FactorConstantNode constant ||
            constant.Value < 1 ||
            constant.Value > 252 ||
            Math.Abs(constant.Value - Math.Round(constant.Value)) >
                0.000001)
        {
            throw new FactorDSLException(
                "Temporal safety requires an integer window from 1 through 252; future references are prohibited.");
        }
        return (int)constant.Value;
    }

    private static int Depth(FactorExpressionNode node)
    {
        return node is FactorOperatorNode operation
            ? 1 + operation.Arguments.Select(Depth).DefaultIfEmpty(0).Max()
            : 1;
    }

    private static int OperatorCount(FactorExpressionNode node)
    {
        return node is FactorOperatorNode operation
            ? 1 + operation.Arguments.Sum(OperatorCount)
            : 0;
    }

    private static FactorOperatorDefinition Operator(
        string name,
        int minimumArguments,
        int maximumArguments,
        FactorMissingValuePolicy missingValuePolicy,
        bool crossSectional,
        int complexityCost)
    {
        return new FactorOperatorDefinition(
            name,
            minimumArguments,
            maximumArguments,
            missingValuePolicy,
            crossSectional,
            true,
            complexityCost);
    }

    private static double StandardDeviation(
        IReadOnlyList<double> values)
    {
        if (values.Count == 0)
        {
            return 0;
        }
        var mean = values.Average();
        return Math.Sqrt(
            values.Sum(value => Math.Pow(value - mean, 2)) /
            values.Count);
    }

    private static double RankOfLast(IReadOnlyList<double> values)
    {
        if (values.Count <= 1)
        {
            return 0.5;
        }
        var target = values[^1];
        var below = values.Count(value => value < target);
        var equal = values.Count(value => Math.Abs(value - target) < 1e-12);
        return (below + 0.5 * (equal - 1)) / (values.Count - 1);
    }

    private static IReadOnlyList<double> Ranks(
        IReadOnlyList<double> values)
    {
        if (values.Count <= 1)
        {
            return values.Select(_ => 0.5).ToArray();
        }
        return values
            .Select(value =>
            {
                var below = values.Count(item => item < value);
                var equal = values.Count(item =>
                    Math.Abs(item - value) < 1e-12);
                return (below + 0.5 * (equal - 1)) /
                    (values.Count - 1);
            })
            .ToArray();
    }

    private static IReadOnlyList<double> ZScores(
        IReadOnlyList<double> values)
    {
        if (values.Count == 0)
        {
            return Array.Empty<double>();
        }
        var mean = values.Average();
        var deviation = StandardDeviation(values);
        return values
            .Select(value => deviation < 1e-12
                ? 0
                : (value - mean) / deviation)
            .ToArray();
    }

    private static IReadOnlyList<double> Winsorize(
        IReadOnlyList<double> values)
    {
        if (values.Count == 0)
        {
            return Array.Empty<double>();
        }
        var ordered = values.OrderBy(value => value).ToArray();
        var low = ordered[(int)Math.Floor((ordered.Length - 1) * 0.05)];
        var high = ordered[(int)Math.Ceiling((ordered.Length - 1) * 0.95)];
        return values
            .Select(value => Math.Clamp(value, low, high))
            .ToArray();
    }

    internal static double? Correlation(
        IReadOnlyList<double> left,
        IReadOnlyList<double> right)
    {
        if (left.Count != right.Count || left.Count < 2)
        {
            return null;
        }
        var leftMean = left.Average();
        var rightMean = right.Average();
        var numerator = 0.0;
        var leftVariance = 0.0;
        var rightVariance = 0.0;
        for (var index = 0; index < left.Count; index += 1)
        {
            var leftDelta = left[index] - leftMean;
            var rightDelta = right[index] - rightMean;
            numerator += leftDelta * rightDelta;
            leftVariance += leftDelta * leftDelta;
            rightVariance += rightDelta * rightDelta;
        }
        var denominator = Math.Sqrt(leftVariance * rightVariance);
        return denominator < 1e-12 ? 0 : numerator / denominator;
    }

    private static double? Beta(
        IReadOnlyList<double> left,
        IReadOnlyList<double> right)
    {
        if (left.Count != right.Count || left.Count < 2)
        {
            return null;
        }
        var leftMean = left.Average();
        var rightMean = right.Average();
        var covariance = 0.0;
        var variance = 0.0;
        for (var index = 0; index < left.Count; index += 1)
        {
            covariance +=
                (left[index] - leftMean) *
                (right[index] - rightMean);
            variance += Math.Pow(right[index] - rightMean, 2);
        }
        return variance < 1e-12 ? 0 : covariance / variance;
    }

    private sealed class Parser
    {
        private readonly string _source;
        private readonly IReadOnlySet<string> _fields;
        private readonly IReadOnlyDictionary<string, FactorOperatorDefinition>
            _operators;
        private int _index;

        public Parser(
            string source,
            IReadOnlySet<string> fields,
            IReadOnlyDictionary<string, FactorOperatorDefinition> operators)
        {
            _source = source;
            _fields = fields;
            _operators = operators;
        }

        public FactorExpressionNode Parse()
        {
            var result = ParseExpression();
            SkipWhitespace();
            if (_index != _source.Length)
            {
                throw new FactorDSLException(
                    "Unexpected trailing DSL input.");
            }
            return result;
        }

        private FactorExpressionNode ParseExpression()
        {
            SkipWhitespace();
            if (_index >= _source.Length)
            {
                throw new FactorDSLException(
                    "Unexpected end of DSL expression.");
            }
            if (char.IsDigit(_source[_index]) ||
                _source[_index] is '-' or '+')
            {
                return ParseNumber();
            }
            var identifier = ParseIdentifier();
            SkipWhitespace();
            if (_index >= _source.Length || _source[_index] != '(')
            {
                if (!_fields.Contains(identifier))
                {
                    throw new FactorDSLException(
                        $"Unknown base field {identifier}.");
                }
                return new FactorFieldNode(identifier);
            }
            if (!_operators.TryGetValue(identifier, out var definition))
            {
                throw new FactorDSLException(
                    $"Unknown DSL operator {identifier}; arbitrary code is prohibited.");
            }
            _index += 1;
            var arguments = new List<FactorExpressionNode>();
            SkipWhitespace();
            if (_index < _source.Length && _source[_index] != ')')
            {
                while (true)
                {
                    arguments.Add(ParseExpression());
                    SkipWhitespace();
                    if (_index < _source.Length &&
                        _source[_index] == ',')
                    {
                        _index += 1;
                        continue;
                    }
                    break;
                }
            }
            Require(')');
            if (arguments.Count < definition.MinimumArguments ||
                arguments.Count > definition.MaximumArguments)
            {
                throw new FactorDSLException(
                    $"Operator {identifier} has an invalid argument count.");
            }
            return new FactorOperatorNode(identifier, arguments);
        }

        private FactorExpressionNode ParseNumber()
        {
            var start = _index;
            if (_source[_index] is '-' or '+')
            {
                _index += 1;
            }
            while (_index < _source.Length &&
                   (char.IsDigit(_source[_index]) ||
                    _source[_index] == '.'))
            {
                _index += 1;
            }
            var token = _source[start.._index];
            if (!double.TryParse(
                    token,
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out var value) ||
                !double.IsFinite(value) ||
                Math.Abs(value) > 1000)
            {
                throw new FactorDSLException(
                    "Constants must be finite and bounded to 1000.");
            }
            return new FactorConstantNode(value);
        }

        private string ParseIdentifier()
        {
            var start = _index;
            while (_index < _source.Length &&
                   (char.IsLetterOrDigit(_source[_index]) ||
                    _source[_index] == '_'))
            {
                _index += 1;
            }
            if (start == _index)
            {
                throw new FactorDSLException(
                    "Expected a DSL identifier.");
            }
            return _source[start.._index];
        }

        private void Require(char value)
        {
            SkipWhitespace();
            if (_index >= _source.Length || _source[_index] != value)
            {
                throw new FactorDSLException(
                    $"Expected '{value}' in DSL expression.");
            }
            _index += 1;
        }

        private void SkipWhitespace()
        {
            while (_index < _source.Length &&
                   char.IsWhiteSpace(_source[_index]))
            {
                _index += 1;
            }
        }
    }
}

public sealed class FactorDSLException : Exception
{
    public FactorDSLException(string message)
        : base(message)
    {
    }
}
