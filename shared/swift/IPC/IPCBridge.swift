import BareKit
import BareRPC
import Foundation

final class IPCBridge {

    let rpc: RPC
    private let worklet:  Worklet
    private let delegate: _Delegate

    init() {
        worklet = Worklet()
        // Debug — find where bundle actually is
            print("📦 main bundle path:", Bundle.main.bundlePath)
            print("📦 resource path:", Bundle.main.resourcePath ?? "nil")
            
            let bundleURL = Bundle.main.url(forResource: "app", withExtension: "bundle")
            print("📦 app.bundle URL:", bundleURL?.path ?? "NOT FOUND")
        worklet.start(name: "app", ofType: "bundle")

        let ipc      = IPC(worklet: worklet)
        let delegate = _Delegate(ipc: ipc)
        let rpc      = RPC(delegate: delegate)
        delegate.rpc = rpc

        self.delegate = delegate
        self.rpc      = rpc
    }

    func start() async {
        await delegate.readLoop()
    }

    /// Fire-and-forget event — no reply expected, safe to call concurrently
    func event(_ command: UInt, body: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        rpc.event(command, data: data)
    }

    /// Request — expects a reply, use only for commands that need acknowledgement
    func request(_ command: UInt, body: [String: Any]) async throws -> Data? {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        return try await rpc.request(command, data: data)
    }

    func setHandler(_ handler: any RPCDelegate) {
        delegate.externalHandler = handler
    }

    func suspend()   { worklet.suspend() }
    func resume()    { worklet.resume() }
    func terminate() { worklet.terminate() }
}

// MARK: - Private delegate

private final class _Delegate: RPCDelegate {
    private let ipc: IPC
    unowned var rpc: RPC!
    weak var externalHandler: (any RPCDelegate)?

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
