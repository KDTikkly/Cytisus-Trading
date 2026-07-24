import Foundation

protocol UniverseServicing {
    func buildDailySnapshot(
        snapshotTime: Date,
        configuration: UniverseConfiguration,
        securities: SecurityListSnapshot,
        positions: BrokerPositionSnapshot
    ) -> UniverseSnapshot
}

struct UniverseService: UniverseServicing {
    func buildDailySnapshot(
        snapshotTime: Date,
        configuration: UniverseConfiguration,
        securities: SecurityListSnapshot,
        positions: BrokerPositionSnapshot
    ) -> UniverseSnapshot {
        let heldSymbols = Set(
            positions.positions
                .filter { $0.quantity != 0 }
                .map { $0.symbol.uppercased() }
        )
        let date = Self.dateFormatter.string(from: snapshotTime)
        let entries = securities.securities
            .sorted { $0.symbol < $1.symbol }
            .map { security in
                evaluate(
                    date: date,
                    configuration: configuration,
                    sourceVersion: securities.sourceVersion,
                    security: security,
                    alreadyHeld: heldSymbols.contains(security.symbol.uppercased())
                )
            }

        return UniverseSnapshot(
            schemaVersion: 1,
            date: date,
            market: configuration.market,
            ruleVersion: configuration.ruleVersion,
            sourceVersion: securities.sourceVersion,
            createdAt: snapshotTime,
            entries: entries
        )
    }

    private func evaluate(
        date: String,
        configuration: UniverseConfiguration,
        sourceVersion: String,
        security: SecurityReference,
        alreadyHeld: Bool
    ) -> UniverseEntry {
        let exclusion = exclusionReason(
            configuration: configuration,
            security: security
        )
        let included = exclusion == nil
        let disposition: UniverseDisposition = included
            ? .included
            : alreadyHeld ? .reduceOnly : .excluded
        let reason: String
        if included {
            reason = "Included: all daily universe rules passed."
        } else if disposition == .reduceOnly {
            reason = "Reduce Only: \(exclusion ?? "unavailable")"
        } else {
            reason = "Excluded: \(exclusion ?? "unavailable")"
        }

        return UniverseEntry(
            date: date,
            symbol: security.symbol,
            included: included,
            disposition: disposition,
            reason: reason,
            liquidityMetrics: UniverseLiquidityMetrics(
                lastPrice: security.lastPrice,
                averageDailyVolume: security.averageDailyVolume,
                averageDailyValue: security.averageDailyValue
            ),
            dataCoverage: UniverseDataCoverage(
                listingAgeDays: security.listingAgeDays,
                historyCoverageDays: security.historyCoverageDays
            ),
            industry: security.industry,
            ruleVersion: configuration.ruleVersion,
            sourceVersion: sourceVersion
        )
    }

    private func exclusionReason(
        configuration: UniverseConfiguration,
        security: SecurityReference
    ) -> String? {
        if !security.tradable {
            return "security is not tradable"
        }
        if security.lastPrice < configuration.minimumPrice {
            return "price is below the configured minimum"
        }
        if security.averageDailyVolume < configuration.minimumAverageDailyVolume {
            return "liquidity is below the configured minimum"
        }
        if security.listingAgeDays < configuration.minimumListingAgeDays {
            return "listing age is below the configured minimum"
        }
        if security.historyCoverageDays < configuration.minimumHistoryCoverageDays {
            return "history coverage is below the configured minimum"
        }
        if security.suspended {
            return "security is suspended"
        }
        if security.delisted {
            return "security is delisted"
        }
        if security.abnormal {
            return "security is marked abnormal"
        }
        if !security.strategyEligible {
            return "strategy-specific placeholder filter rejected the security"
        }
        return nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
