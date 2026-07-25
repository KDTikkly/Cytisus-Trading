#include "quant_core.h"

#include <algorithm>
#include <cmath>
#include <numeric>
#include <utility>
#include <vector>

int cytisus_rolling_mean(
    const double* values,
    size_t count,
    size_t window,
    double* output) {
    if (!values || !output || window == 0 || window > count) {
        return 1;
    }
    double sum = 0.0;
    for (size_t index = 0; index < count; ++index) {
        sum += values[index];
        if (index >= window) {
            sum -= values[index - window];
        }
        output[index] = index + 1 < window ? NAN : sum / window;
    }
    return 0;
}

int cytisus_returns(
    const double* prices,
    size_t count,
    double* output) {
    if (!prices || !output || count < 2) {
        return 1;
    }
    output[0] = NAN;
    for (size_t index = 1; index < count; ++index) {
        if (prices[index - 1] <= 0.0) {
            return 2;
        }
        output[index] = prices[index] / prices[index - 1] - 1.0;
    }
    return 0;
}

int cytisus_rolling_volatility(
    const double* values,
    size_t count,
    size_t window,
    double* output) {
    if (!values || !output || window < 2 || window > count) {
        return 1;
    }
    for (size_t index = 0; index < count; ++index) {
        if (index + 1 < window) {
            output[index] = NAN;
            continue;
        }
        const size_t start = index + 1 - window;
        double mean = 0.0;
        for (size_t cursor = start; cursor <= index; ++cursor) {
            mean += values[cursor];
        }
        mean /= static_cast<double>(window);
        double total = 0.0;
        for (size_t cursor = start; cursor <= index; ++cursor) {
            const double difference = values[cursor] - mean;
            total += difference * difference;
        }
        output[index] = std::sqrt(total / static_cast<double>(window - 1));
    }
    return 0;
}

int cytisus_cross_sectional_rank(
    const double* values,
    size_t count,
    double* output) {
    if (!values || !output || count == 0) {
        return 1;
    }
    std::vector<std::pair<double, size_t>> sorted;
    sorted.reserve(count);
    for (size_t index = 0; index < count; ++index) {
        sorted.emplace_back(values[index], index);
    }
    std::stable_sort(sorted.begin(), sorted.end());
    const double denominator = count > 1 ? static_cast<double>(count - 1) : 1.0;
    for (size_t rank = 0; rank < count; ++rank) {
        output[sorted[rank].second] = static_cast<double>(rank) / denominator;
    }
    return 0;
}

int cytisus_normalize(
    const double* values,
    size_t count,
    double* output) {
    if (!values || !output || count < 2) {
        return 1;
    }
    const double mean =
        std::accumulate(values, values + count, 0.0) / count;
    double total = 0.0;
    for (size_t index = 0; index < count; ++index) {
        const double difference = values[index] - mean;
        total += difference * difference;
    }
    const double standard_deviation =
        std::sqrt(total / static_cast<double>(count - 1));
    if (standard_deviation == 0.0) {
        return 2;
    }
    for (size_t index = 0; index < count; ++index) {
        output[index] = (values[index] - mean) / standard_deviation;
    }
    return 0;
}

int cytisus_covariance(
    const double* left,
    const double* right,
    size_t count,
    double* output) {
    if (!left || !right || !output || count < 2) {
        return 1;
    }
    const double left_mean =
        std::accumulate(left, left + count, 0.0) / count;
    const double right_mean =
        std::accumulate(right, right + count, 0.0) / count;
    double total = 0.0;
    for (size_t index = 0; index < count; ++index) {
        total += (left[index] - left_mean) * (right[index] - right_mean);
    }
    *output = total / static_cast<double>(count - 1);
    return 0;
}

int cytisus_correlation(
    const double* left,
    const double* right,
    size_t count,
    double* output) {
    if (!left || !right || !output || count < 2) {
        return 1;
    }
    std::vector<double> left_normalized(count);
    std::vector<double> right_normalized(count);
    if (cytisus_normalize(left, count, left_normalized.data()) != 0 ||
        cytisus_normalize(right, count, right_normalized.data()) != 0) {
        return 3;
    }
    double left_variance = 0.0;
    double right_variance = 0.0;
    for (size_t index = 0; index < count; ++index) {
        left_variance += left_normalized[index] * left_normalized[index];
        right_variance += right_normalized[index] * right_normalized[index];
    }
    const double denominator =
        std::sqrt(left_variance * right_variance);
    if (denominator == 0.0) {
        return 4;
    }
    double numerator = 0.0;
    for (size_t index = 0; index < count; ++index) {
        numerator += left_normalized[index] * right_normalized[index];
    }
    *output = numerator / denominator;
    return 0;
}

int cytisus_matrix_multiply(
    const double* left,
    const double* right,
    size_t rows,
    size_t inner,
    size_t columns,
    double* output) {
    if (!left || !right || !output || rows == 0 || inner == 0 || columns == 0) {
        return 1;
    }
    for (size_t row = 0; row < rows; ++row) {
        for (size_t column = 0; column < columns; ++column) {
            double value = 0.0;
            for (size_t index = 0; index < inner; ++index) {
                value += left[row * inner + index] *
                    right[index * columns + column];
            }
            output[row * columns + column] = value;
        }
    }
    return 0;
}

int cytisus_batched_linear_score(
    const double* features,
    const double* parameters,
    size_t batches,
    size_t feature_count,
    double* output) {
    if (!features || !parameters || !output ||
        batches == 0 || feature_count == 0) {
        return 1;
    }
    for (size_t batch = 0; batch < batches; ++batch) {
        double total = 0.0;
        for (size_t feature = 0; feature < feature_count; ++feature) {
            total += features[feature] *
                parameters[batch * feature_count + feature];
        }
        output[batch] = total;
    }
    return 0;
}

int cytisus_monte_carlo_normal(
    unsigned long long seed,
    size_t count,
    double* output) {
    if (!output || count == 0) {
        return 1;
    }
    unsigned long long state = seed == 0 ? 17 : seed;
    const double scale = 1.0 /
        static_cast<double>(0x1fffffffffffffULL);
    for (size_t index = 0; index < count; index += 2) {
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        const double first =
            (static_cast<double>((state >> 11) | 1ULL) * scale);
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        const double second =
            static_cast<double>(state >> 11) * scale;
        const double magnitude =
            std::sqrt(-2.0 * std::log(first));
        const double angle = 6.28318530717958647692 * second;
        output[index] = magnitude * std::cos(angle);
        if (index + 1 < count) {
            output[index + 1] = magnitude * std::sin(angle);
        }
    }
    return 0;
}
