import CryptoKit
import Foundation

enum LocalStudioServiceError: Error {
    case wrongProject
    case costLimitExceeded
    case invalidProjectPath
    case unavailableDevice
}

final class LocalStudioService {
    private let store: LocalStudioStore
    private let auditStore: AuditEventStore
    private let allowedExtensions = [
        "py", "json", "md", "txt", "yaml", "yml"
    ]

    init(store: LocalStudioStore, auditStore: AuditEventStore) {
        self.store = store
        self.auditStore = auditStore
    }

    func loadOrCreateFixtureState() throws -> LocalStudioState {
        let current = try store.loadLocalStudioState()
        guard current.projects.isEmpty else { return current }
        let projectFile = AlgorithmProjectFile(
            relativePath: "strategy.py",
            sha256: sha256("def signal(prices): return prices\n"),
            sizeBytes: 42
        )
        let state = LocalStudioState(
            schemaVersion: 1,
            projects: [
                AlgorithmProject(
                    projectId: "project-ma-demo",
                    name: "Moving Average Research",
                    projectType: "Research",
                    currentVersion: 1,
                    versions: [
                        AlgorithmProjectVersion(
                            version: 1,
                            createdAt: Date(),
                            source: "Fixture",
                            files: [projectFile]
                        )
                    ]
                )
            ],
            jobs: [],
            checkpoints: [],
            models: [],
            executionModules: [
                ExecutionModuleRecord(
                    moduleId: "twap-fixture",
                    name: "TWAP Fixture",
                    version: "1.0.0",
                    status: "PaperValidationOnly",
                    requiresExecutionGateway: true
                )
            ],
            accounts: [
                LongbridgeAccountFixture(
                    accountId: "fixture-local-paper",
                    displayName: "Local Paper",
                    channel: "LocalPaper",
                    market: "US",
                    isSynthetic: true
                ),
                LongbridgeAccountFixture(
                    accountId: "fixture-longbridge-live",
                    displayName: "Longbridge Live Fixture",
                    channel: "LongbridgeLive",
                    market: "US",
                    isSynthetic: true
                )
            ],
            accountMappings: [
                StrategyAccountMapping(
                    strategyId: "official-fixture-strategy",
                    accountId: "fixture-local-paper",
                    market: "US",
                    source: "SyntheticFixture"
                )
            ],
            agentAuthorizations: []
        )
        try store.saveLocalStudioState(state)
        appendAudit(
            category: .algorithmProject,
            action: "InitializeFixtureStudio",
            result: .completed,
            context: [
                "project_count": String(state.projects.count),
                "synthetic_account_count": String(state.accounts.count)
            ]
        )
        return state
    }

    func validateAgentPatch(
        projectRootURL: URL,
        project: AlgorithmProject,
        patch: AgentProjectPatch,
        maximumTokenCost: Int
    ) throws -> AlgorithmProjectVersion {
        guard patch.projectId == project.projectId else {
            throw LocalStudioServiceError.wrongProject
        }
        guard patch.estimatedTokenCost >= 0,
              patch.estimatedTokenCost <= maximumTokenCost else {
            throw LocalStudioServiceError.costLimitExceeded
        }
        let relative = patch.relativePath.replacingOccurrences(
            of: "\\",
            with: "/"
        )
        let segments = relative.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !relative.hasPrefix("/"),
              !segments.contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".."
              }),
              allowedExtensions.contains(
                  URL(fileURLWithPath: relative).pathExtension.lowercased()
              ) else {
            throw LocalStudioServiceError.invalidProjectPath
        }
        let root = projectRootURL.standardizedFileURL.path
        let target = projectRootURL
            .appendingPathComponent(relative)
            .standardizedFileURL
            .path
        guard target.hasPrefix(root + "/") else {
            throw LocalStudioServiceError.invalidProjectPath
        }
        let file = AlgorithmProjectFile(
            relativePath: relative,
            sha256: sha256(patch.newContent),
            sizeBytes: Int64(patch.newContent.utf8.count)
        )
        let version = AlgorithmProjectVersion(
            version: project.currentVersion + 1,
            createdAt: Date(),
            source: "AgentPatch",
            files: [file]
        )
        appendAudit(
            category: .algorithmProject,
            action: "ValidateAgentProjectPatch",
            result: .accepted,
            context: [
                "project_id": project.projectId,
                "patch_id": patch.patchId,
                "candidate_version": String(version.version)
            ]
        )
        return version
    }

    static func fixtureDevices() -> [ComputeDevice] {
        [
            ComputeDevice(
                deviceId: "cpu",
                type: .cpu,
                vendor: "Generic",
                model: "CPU",
                driverOrRuntimeVersion: "Swift and native C ABI",
                memoryBytes: nil,
                supportedPrecisions: ["FP64", "FP32"],
                supportedBackends: ["SwiftCPU", "NativeCPU"],
                trainingSupported: true,
                inferenceSupported: true,
                health: .ready,
                failureReason: "Deterministic CPU fallback is always available."
            ),
            ComputeDevice(
                deviceId: "apple-metal",
                type: .appleMetal,
                vendor: "Apple",
                model: "Metal",
                driverOrRuntimeVersion: "Not loaded",
                memoryBytes: nil,
                supportedPrecisions: [],
                supportedBackends: ["Metal", "MPS", "CoreML"],
                trainingSupported: false,
                inferenceSupported: false,
                health: .unavailable,
                failureReason: "No runtime provider was validated."
            ),
            ComputeDevice(
                deviceId: "npu",
                type: .npu,
                vendor: "Runtime",
                model: "NPU",
                driverOrRuntimeVersion: "Not loaded",
                memoryBytes: nil,
                supportedPrecisions: [],
                supportedBackends: ["QNN", "OpenVINO", "VitisAI", "CoreML"],
                trainingSupported: false,
                inferenceSupported: false,
                health: .unavailable,
                failureReason: "No ONNX execution provider was validated."
            )
        ]
    }

    static func selectDevice(
        from devices: [ComputeDevice],
        policy: ComputePolicy
    ) throws -> ComputeDevice {
        if let preferred = devices.first(where: {
            $0.deviceId == policy.preferredDeviceId &&
                $0.health == .ready
        }) {
            return preferred
        }
        if policy.allowCPUFallback,
           let cpu = devices.first(where: {
               $0.type == .cpu && $0.health == .ready
           }) {
            return cpu
        }
        throw LocalStudioServiceError.unavailableDevice
    }

    static func evaluateAgentOrder(
        authorization: AgentOrderAuthorization,
        intent: AgentOrderIntent,
        priorDailyNotional: Double,
        priorOrderCount: Int,
        now: Date,
        currentPositionValue: Double = 0,
        currentDailyLoss: Double = 0
    ) -> AgentOrderEvaluation {
        let notional = intent.quantity * intent.referencePrice
        if authorization.revoked {
            return AgentOrderEvaluation(
                decision: .revoked,
                reason: "Authorization was revoked.",
                notional: notional
            )
        }
        if now >= authorization.expiresAt {
            return AgentOrderEvaluation(
                decision: .expired,
                reason: "Authorization expired.",
                notional: notional
            )
        }
        if (authorization.validFrom != nil &&
            now < authorization.validFrom!) ||
            (intent.expiresAt != nil && now >= intent.expiresAt!) {
            return AgentOrderEvaluation(
                decision: .expired,
                reason: "The authorization or intent is outside its time window.",
                notional: notional
            )
        }
        guard authorization.authorizationId == intent.authorizationId,
              authorization.allowedStrategies.contains(intent.strategyId),
              authorization.allowedSymbols.contains(intent.symbol) else {
            return AgentOrderEvaluation(
                decision: .rejected,
                reason: "The strategy or symbol is outside the authorization.",
                notional: notional
            )
        }
        if (!authorization.allowedAccounts.isEmpty &&
            !authorization.allowedAccounts.contains(intent.accountId)) ||
            (!authorization.allowedMarkets.isEmpty &&
             !authorization.allowedMarkets.contains(intent.market)) ||
            (!authorization.allowedOrderTypes.isEmpty &&
             !authorization.allowedOrderTypes.contains(intent.orderType)) ||
            intent.confidence < authorization.minimumConfidence ||
            (intent.outsideRegularHours &&
             !authorization.outsideRegularHoursPermission) {
            return AgentOrderEvaluation(
                decision: .rejected,
                reason: "The account, market, order type, confidence, or trading-hours boundary failed.",
                notional: notional
            )
        }
        guard notional <= authorization.maxNotionalPerOrder,
              priorDailyNotional + notional <= authorization.maxDailyNotional,
              priorOrderCount < authorization.maxOrdersPerDay,
              currentPositionValue + notional <= authorization.maximumPosition,
              currentDailyLoss <= authorization.maximumDailyLoss else {
            return AgentOrderEvaluation(
                decision: .rejected,
                reason: "An authorization limit would be exceeded.",
                notional: notional
            )
        }
        let decision: AgentOrderDecision
        switch authorization.mode {
        case .suggestOnly: decision = .suggested
        case .confirmEveryOrder: decision = .pendingConfirmation
        case .boundedAutonomy: decision = .authorized
        }
        return AgentOrderEvaluation(
            decision: decision,
            reason: "The intent passed the configured authorization boundary.",
            notional: notional
        )
    }

    static func executionProposal(
        intentId: String,
        symbol: String,
        side: String,
        quantity: Double,
        referencePrice: Double
    ) -> ExecutionModuleProposal {
        ExecutionModuleProposal(
            proposalId: "proposal-\(intentId)",
            moduleId: "twap-fixture",
            intentId: intentId,
            symbol: symbol,
            side: side,
            quantity: quantity,
            limitPrice: referencePrice,
            requiresExecutionGateway: true,
            reason: "Synthetic child proposal; the Execution Gateway remains authoritative."
        )
    }

    private func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func appendAudit(
        category: AuditEventCategory,
        action: String,
        result: AuditResult,
        context: [String: String]
    ) {
        try? auditStore.appendAuditEvent(
            AuditEvent(
                id: UUID().uuidString,
                occurredAt: Date(),
                category: category,
                action: action,
                result: result,
                actor: "LocalStudio",
                correlationID: UUID().uuidString,
                context: context
            )
        )
    }
}
