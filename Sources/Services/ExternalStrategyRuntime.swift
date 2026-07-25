import Foundation

final class ExternalStrategyRuntime {
    private let manifest: StrategyManifest
    private let codec: StrategyMessageCodec
    private let heartbeatTimeout: TimeInterval
    private let shutdownTimeout: TimeInterval
    private let messageHandler: (StrategyMessageEnvelope) -> Void
    private let logHandler: (ApplicationLogEntry) -> Void
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let queue = DispatchQueue(
        label: "Cytisus.ExternalStrategyRuntime",
        qos: .utility
    )
    private var eventIds: Set<String> = []

    private(set) var state: StrategyRuntimeState = .stopped
    private(set) var lastHeartbeat: Date?
    private(set) var exitCode: Int32?

    init(
        manifest: StrategyManifest,
        codec: StrategyMessageCodec,
        heartbeatTimeout: TimeInterval = 30,
        shutdownTimeout: TimeInterval = 5,
        messageHandler: @escaping (StrategyMessageEnvelope) -> Void,
        logHandler: @escaping (ApplicationLogEntry) -> Void
    ) {
        self.manifest = manifest
        self.codec = codec
        self.heartbeatTimeout = heartbeatTimeout
        self.shutdownTimeout = shutdownTimeout
        self.messageHandler = messageHandler
        self.logHandler = logHandler
    }

    func start(initialize: StrategyMessageEnvelope) throws {
        guard manifest.source == .thirdParty,
              state == .stopped else {
            throw StrategyProtocolError.runtime(
                "External runtime accepts a stopped ThirdParty strategy only."
            )
        }
        process.executableURL = URL(fileURLWithPath: manifest.entrypoint)
        process.arguments = []
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { [weak self] process in
            self?.exitCode = process.terminationStatus
            if self?.state != .rejected {
                self?.state = .exited
            }
        }
        state = .starting
        try process.run()
        try send(initialize)
        queue.async { [weak self] in self?.pumpOutput() }
        queue.async { [weak self] in self?.pumpErrors() }
    }

    func send(_ message: StrategyMessageEnvelope) throws {
        guard process.isRunning else {
            throw StrategyProtocolError.runtime(
                "Strategy process is not running."
            )
        }
        let line = try codec.encode(message, direction: .coreToStrategy)
        try input.fileHandleForWriting.write(
            contentsOf: Data(line.utf8)
        )
    }

    func evaluateHeartbeat(now: Date) -> Bool {
        let timedOut = StrategyHeartbeatMonitor(
            timeout: heartbeatTimeout
        ).isTimedOut(lastHeartbeat: lastHeartbeat, now: now)
        if timedOut {
            state = .unhealthy
            process.terminate()
        }
        return timedOut
    }

    func shutdown(_ message: StrategyMessageEnvelope) {
        if process.isRunning {
            try? send(message)
            try? input.fileHandleForWriting.close()
            let deadline = Date().addingTimeInterval(shutdownTimeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
            }
        }
        state = .exited
    }

    private func pumpOutput() {
        var buffer = Data()
        while process.isRunning {
            let data = output.fileHandleForReading.availableData
            if data.isEmpty { break }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard let line = String(data: lineData, encoding: .utf8) else {
                    reject("Malformed UTF-8 strategy output.")
                    return
                }
                do {
                    let message = try codec.decode(
                        line,
                        direction: .strategyToCore,
                        expectedStrategyId: manifest.strategyId,
                        expectedStrategyVersion: manifest.version
                    )
                    guard eventIds.insert(message.eventId).inserted else {
                        throw StrategyProtocolError.malformedMessage(
                            "Duplicate strategy event ID."
                        )
                    }
                    if message.messageType == "heartbeat" {
                        lastHeartbeat = message.timestamp
                    } else if message.messageType == "ready" {
                        state = .ready
                    } else if message.messageType == "cycle_complete" {
                        state = .running
                    }
                    messageHandler(message)
                } catch {
                    reject("Malformed strategy output rejected.")
                    return
                }
            }
        }
    }

    private func pumpErrors() {
        let maximumCharacters = 4096
        while process.isRunning {
            let data = errors.fileHandleForReading.availableData
            if data.isEmpty { break }
            let raw = String(data: data, encoding: .utf8) ?? ""
            let bounded = String(raw.prefix(maximumCharacters))
            logHandler(
                ApplicationLogEntry(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    severity: .warning,
                    module: "StrategyRuntime",
                    message: SensitiveDataRedactor.redact(bounded),
                    correlationID: nil,
                    strategyID: manifest.strategyId,
                    cycleID: nil,
                    context: [
                        "stream": "stderr",
                        "truncated": raw.count > maximumCharacters
                            ? "true"
                            : "false"
                    ]
                )
            )
        }
    }

    private func reject(_ reason: String) {
        state = .rejected
        logHandler(
            ApplicationLogEntry(
                id: UUID().uuidString,
                timestamp: Date(),
                severity: .error,
                module: "StrategyRuntime",
                message: reason,
                correlationID: nil,
                strategyID: manifest.strategyId,
                cycleID: nil,
                context: ["raw_output_logged": "false"]
            )
        )
        if process.isRunning {
            process.terminate()
        }
    }
}
