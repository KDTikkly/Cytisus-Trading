import Foundation
import SwiftUI

@MainActor
final class StrategyParameterModel: ObservableObject, Identifiable {
    let definition: StrategyParameterDefinition
    @Published var value: String
    @Published var draftValue: String
    @Published var confirmationChecked = false
    @Published var previewText = "No pending change."
    @Published var status = "Current"

    init(definition: StrategyParameterDefinition, value: String) {
        self.definition = definition
        self.value = value
        draftValue = value
    }

    var id: String { definition.key }
    var key: String { definition.key }
    var label: String { definition.label }
    var description: String { definition.description }
    var riskTierLabel: String { definition.safetyOverride.riskTier.rawValue }
    var activationLabel: String {
        definition.safetyOverride.activationMode.rawValue
    }
    var rangeLabel: String {
        let safety = definition.safetyOverride
        if safety.hardMin == nil && safety.hardMax == nil {
            return "Cytisus bounded text"
        }
        return "Hard range \(safety.hardMin ?? "-") to \(safety.hardMax ?? "-")"
    }
}

@MainActor
final class StrategyItemModel: ObservableObject, Identifiable {
    let manifest: StrategyManifest
    let parameterSchema: StrategyParameterSchema
    @Published var mode: StrategyMode
    @Published var runtimeState: StrategyRuntimeState
    @Published var health: HealthState
    @Published var lastHeartbeat: Date?
    @Published var parameterVersion: Int
    @Published var blocksNewRisk: Bool
    @Published var liveToPaperTransition: LiveToPaperTransition
    @Published var parameters: [StrategyParameterModel]
    @Published var parameterChanges: [StrategyParameterChange] = []
    @Published var signals: [StrategySignal] = []
    @Published var targets: [StrategyTarget] = []
    @Published var intents: [StrategyIntentRecord] = []
    @Published var cycles: [StrategyCycleSummary] = []

    init(
        manifest: StrategyManifest,
        parameterSchema: StrategyParameterSchema,
        state: StrategyPersistentState
    ) {
        self.manifest = manifest
        self.parameterSchema = parameterSchema
        mode = state.mode
        runtimeState = state.runtimeState
        health = state.health
        lastHeartbeat = state.lastHeartbeat
        parameterVersion = state.parameterVersion
        blocksNewRisk = state.blocksNewRisk
        liveToPaperTransition = state.liveToPaperTransition
        parameters = parameterSchema.parameters.map { definition in
            StrategyParameterModel(
                definition: definition,
                value: state.parameterValues[definition.key] ??
                    definition.defaultValue
            )
        }
    }

    var id: String { manifest.strategyId }
    var strategyId: String { manifest.strategyId }
    var name: String { manifest.name }
    var sourceLabel: String { manifest.source.rawValue }
    var lastHeartbeatDisplay: String {
        lastHeartbeat?.formatted(date: .abbreviated, time: .shortened)
            ?? "No heartbeat"
    }

    func persistentState() -> StrategyPersistentState {
        StrategyPersistentState(
            strategyId: strategyId,
            mode: mode,
            runtimeState: runtimeState,
            health: health,
            lastHeartbeat: lastHeartbeat,
            parameterVersion: parameterVersion,
            parameterValues: Dictionary(
                uniqueKeysWithValues: parameters.map { ($0.key, $0.value) }
            ),
            blocksNewRisk: blocksNewRisk,
            liveToPaperTransition: liveToPaperTransition
        )
    }
}
