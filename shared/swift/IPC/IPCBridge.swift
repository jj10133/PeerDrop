//
//  IPCBridge.swift
//  App
//
//  Created by Janardhan on 2026-03-25.
//


import BareKit
import BareRPC
import Foundation

final class IPCBridge {

    let rpc: RPC

    private let worklet:  Worklet
    private let delegate: _Delegate

    init() {
        worklet = Worklet()
        worklet.start(name: "app", ofType: "bundle")

        let ipc      = IPC(worklet: worklet)
        let delegate = _Delegate(ipc: ipc)
        let rpc      = RPC(delegate: delegate)
        delegate.rpc = rpc

        self.delegate = delegate
        self.rpc      = rpc
    }

    /// Drive the inbound read loop. Call once from a long-lived async Task.
    func start() async {
        await delegate.readLoop()
    }

    /// Send a request to JS and await its reply.
    func request(_ command: UInt, body: [String: Any]) async throws -> Data? {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        return try await rpc.request(command, data: data)
    }

    // MARK: - Lifecycle

    func suspend()   { worklet.suspend() }
    func resume()    { worklet.resume() }
    func terminate() { worklet.terminate() }
}

// MARK: - Private delegate

private final class _Delegate: RPCDelegate {
    private let ipc: IPC
    unowned var rpc: RPC!

    init(ipc: IPC) { self.ipc = ipc }

    func rpc(_ rpc: RPC, send data: Data) {
        Task {
            do { try await ipc.write(data: data) }
            catch { print("❌ IPC write: \(error)") }
        }
    }

    func readLoop() async {
        do {
            for try await chunk in ipc { rpc.receive(chunk) }
        } catch {
            print("❌ IPC read: \(error)")
        }
    }
}
