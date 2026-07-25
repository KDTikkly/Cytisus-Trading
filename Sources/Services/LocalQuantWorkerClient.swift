import Foundation

enum LocalQuantWorkerError: Error {
    case invalidInterpreter
    case invalidWorkerScript
    case timedOut
    case noResponse
    case responseTooLarge
}

protocol LocalQuantWorkerClient {
    func send(
        pythonExecutableURL: URL,
        workerScriptURL: URL,
        rootURL: URL,
        request: [String: Any],
        timeout: TimeInterval
    ) throws -> [String: Any]
}

final class ProcessLocalQuantWorkerClient: LocalQuantWorkerClient {
    private let maximumResponseBytes = 1_048_576

    func send(
        pythonExecutableURL: URL,
        workerScriptURL: URL,
        rootURL: URL,
        request: [String: Any],
        timeout: TimeInterval
    ) throws -> [String: Any] {
        guard pythonExecutableURL.isFileURL,
              FileManager.default.isExecutableFile(
                atPath: pythonExecutableURL.path
              ) else {
            throw LocalQuantWorkerError.invalidInterpreter
        }
        guard workerScriptURL.isFileURL,
              workerScriptURL.lastPathComponent == "quant_worker.py",
              FileManager.default.fileExists(atPath: workerScriptURL.path) else {
            throw LocalQuantWorkerError.invalidWorkerScript
        }

        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = pythonExecutableURL
        process.arguments = [
            workerScriptURL.path,
            "--root",
            rootURL.path,
            "--stdio"
        ]
        process.currentDirectoryURL = rootURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        let requestData = try JSONSerialization.data(
            withJSONObject: request,
            options: [.sortedKeys]
        )
        try process.run()
        input.fileHandleForWriting.write(requestData)
        input.fileHandleForWriting.write(Data([0x0a]))
        input.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(max(1, timeout))
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            throw LocalQuantWorkerError.timedOut
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            throw LocalQuantWorkerError.noResponse
        }
        guard data.count <= maximumResponseBytes else {
            throw LocalQuantWorkerError.responseTooLarge
        }
        let firstLine: Data
        if let newlineIndex = data.firstIndex(where: { (byte: UInt8) in
            byte == 0x0a
        }) {
            firstLine = Data(data[..<newlineIndex])
        } else {
            firstLine = data
        }
        return try JSONSerialization.jsonObject(
            with: firstLine
        ) as? [String: Any] ?? [:]
    }
}
