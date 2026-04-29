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

    /// Drive the inbound read loop.
    func start() async {
        await delegate.readLoop()
    }

    /// Send a request to JS and await its reply.
    func request(_ command: UInt, body: [String: Any]) async throws -> Data? {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        return try await rpc.request(command, data: data)
    }

    /// Set an external event/request handler — called for all incoming messages.
    func setHandler(_ handler: any RPCDelegate) {
        delegate.externalHandler = handler
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

    /// External handler for events — set by Worker
    weak var externalHandler: (any RPCDelegate)?

    init(ipc: IPC) { self.ipc = ipc }

    func rpc(_ rpc: RPC, send data: Data) {
        print("📤 sending \(data.count) bytes to JS")
        Task {
            do { try await ipc.write(data: data) }
            catch { print("❌ IPC write: \(error)") }
        }
    }

    func readLoop() async {
        print("📡 readLoop started")
        do {
            for try await chunk in ipc {
                print("📡 received \(chunk.count) bytes from JS")
                rpc.receive(chunk)
            }
        } catch {
            print("❌ IPC read: \(error)")
        }
    }

    func rpc(_ rpc: RPC, didReceiveRequest request: IncomingRequest) async throws {
        try await externalHandler?.rpc(rpc, didReceiveRequest: request)
            ?? { request.reply(nil) }()
    }

    func rpc(_ rpc: RPC, didReceiveEvent event: IncomingEvent) async {
        await externalHandler?.rpc(rpc, didReceiveEvent: event)
    }

    func rpc(_ rpc: RPC, didFailWith error: Error) {
        print("❌ RPC: \(error)")
        externalHandler?.rpc(rpc, didFailWith: error)
    }
}
