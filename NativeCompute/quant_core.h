#ifndef CYTISUS_QUANT_CORE_H
#define CYTISUS_QUANT_CORE_H

#include <stddef.h>

#if defined(_WIN32)
#define CYTISUS_EXPORT __declspec(dllexport)
#else
#define CYTISUS_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

CYTISUS_EXPORT int cytisus_rolling_mean(
    const double* values,
    size_t count,
    size_t window,
    double* output);

CYTISUS_EXPORT int cytisus_returns(
    const double* prices,
    size_t count,
    double* output);

CYTISUS_EXPORT int cytisus_rolling_volatility(
    const double* values,
    size_t count,
    size_t window,
    double* output);

CYTISUS_EXPORT int cytisus_cross_sectional_rank(
    const double* values,
    size_t count,
    double* output);

CYTISUS_EXPORT int cytisus_normalize(
    const double* values,
    size_t count,
    double* output);

CYTISUS_EXPORT int cytisus_covariance(
    const double* left,
    const double* right,
    size_t count,
    double* output);

CYTISUS_EXPORT int cytisus_correlation(
    const double* left,
    const double* right,
    size_t count,
    double* output);

CYTISUS_EXPORT int cytisus_matrix_multiply(
    const double* left,
    const double* right,
    size_t rows,
    size_t inner,
    size_t columns,
    double* output);

CYTISUS_EXPORT int cytisus_batched_linear_score(
    const double* features,
    const double* parameters,
    size_t batches,
    size_t feature_count,
    double* output);

CYTISUS_EXPORT int cytisus_monte_carlo_normal(
    unsigned long long seed,
    size_t count,
    double* output);

#ifdef __cplusplus
}
#endif

#endif
