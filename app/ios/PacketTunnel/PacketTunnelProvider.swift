import Foundation
import Libbox
import Network
import NetworkExtension

/// iOS VPN 扩展：内嵌 sing-box（Libbox.xcframework）。
/// 主 App 通过 startVPNTunnel(options: ["configContent": json]) 传入配置。
class PacketTunnelProvider: NEPacketTunnelProvider {
    private var commandServer: LibboxCommandServer?
    private var platform: KoyunPlatform?

    private var groupDir: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KoyunShared.appGroup)!
    }

    override func startTunnel(options: [String: NSObject]?) async throws {
        var config = options?["configContent"] as? String
        let saved = groupDir.appendingPathComponent("vpn-config.json")
        if let config { try? config.write(to: saved, atomically: true, encoding: .utf8) }
        // "按需连接" / 从系统设置启动时没有 options，用上次的配置
        if config == nil { config = try? String(contentsOf: saved, encoding: .utf8) }
        guard let config else {
            throw NSError(domain: "Koyun", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing config"])
        }

        let work = groupDir.appendingPathComponent("Working")
        let temp = groupDir.appendingPathComponent("Temp")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let setup = LibboxSetupOptions()
        setup.basePath = groupDir.path
        setup.workingPath = work.path
        setup.tempPath = temp.path
        setup.logMaxLines = 2000
        setup.crashReportSource = "NetworkExtension"
        setup.oomKillerEnabled = true // iOS 扩展内存上限约 50MB
        var err: NSError?
        LibboxSetup(setup, &err)
        if let err { throw err }

        let p = KoyunPlatform(tunnel: self)
        platform = p
        commandServer = LibboxNewCommandServer(p, p, &err)
        if let err { throw err }
        try commandServer!.start()
        try commandServer!.startOrReloadService(config, options: LibboxOverrideOptions())
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        try? commandServer?.closeService()
        try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
        commandServer?.close()
        commandServer = nil
        platform?.reset()
        platform = nil
    }

    /// 主 App 发来新配置（订阅更新）时热重载
    override func handleAppMessage(_ messageData: Data) async -> Data? {
        if let config = String(data: messageData, encoding: .utf8), !config.isEmpty {
            try? config.write(to: groupDir.appendingPathComponent("vpn-config.json"), atomically: true, encoding: .utf8)
            do {
                try commandServer?.startOrReloadService(config, options: LibboxOverrideOptions())
                return "ok".data(using: .utf8)
            } catch {
                return error.localizedDescription.data(using: .utf8)
            }
        }
        return nil
    }
}

final class KoyunPlatform: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    private weak var tunnel: PacketTunnelProvider?
    private var nwMonitor: NWPathMonitor?

    init(tunnel: PacketTunnelProvider) { self.tunnel = tunnel }

    func reset() {
        nwMonitor?.cancel()
        nwMonitor = nil
    }

    // MARK: TUN

    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options, let ret0_, let tunnel else { throw err("nil options") }
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())
            if let it = try? options.getDNSServerAddress() {
                var servers: [String] = []
                while it.hasNext() { servers.append(it.next()) }
                if !servers.isEmpty {
                    let dns = NEDNSSettings(servers: servers)
                    dns.matchDomains = [""]
                    settings.dnsSettings = dns
                }
            }
            var a4: [String] = [], m4: [String] = []
            let i4 = options.getInet4Address()!
            while i4.hasNext() { let p = i4.next()!; a4.append(p.address()); m4.append(p.mask()) }
            let v4 = NEIPv4Settings(addresses: a4, subnetMasks: m4)
            var r4: [NEIPv4Route] = []
            let ri4 = options.getInet4RouteAddress()!
            while ri4.hasNext() { let p = ri4.next()!; r4.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask())) }
            if r4.isEmpty { r4.append(NEIPv4Route.default()) }
            v4.includedRoutes = r4
            var x4: [NEIPv4Route] = []
            let rx4 = options.getInet4RouteExcludeAddress()!
            while rx4.hasNext() { let p = rx4.next()!; x4.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask())) }
            v4.excludedRoutes = x4
            settings.ipv4Settings = v4

            var a6: [String] = [], l6: [NSNumber] = []
            let i6 = options.getInet6Address()!
            while i6.hasNext() { let p = i6.next()!; a6.append(p.address()); l6.append(NSNumber(value: p.prefix())) }
            if !a6.isEmpty {
                let v6 = NEIPv6Settings(addresses: a6, networkPrefixLengths: l6)
                var r6: [NEIPv6Route] = []
                let ri6 = options.getInet6RouteAddress()!
                while ri6.hasNext() { let p = ri6.next()!; r6.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix()))) }
                if r6.isEmpty { r6.append(NEIPv6Route.default()) }
                v6.includedRoutes = r6
                settings.ipv6Settings = v6
            }
        }
        let sem = DispatchSemaphore(value: 0)
        var setErr: Error?
        tunnel.setTunnelNetworkSettings(settings) { e in setErr = e; sem.signal() }
        sem.wait()
        if let setErr { throw setErr }
        if let fd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = fd
            return
        }
        let fd = LibboxGetTunnelFileDescriptor()
        if fd == -1 { throw err("missing tun file descriptor") }
        ret0_.pointee = fd
    }

    // MARK: 网络监听

    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        guard let listener else { return }
        let monitor = NWPathMonitor()
        nwMonitor = monitor
        let sem = DispatchSemaphore(value: 0)
        var first = true
        monitor.pathUpdateHandler = { path in
            if let i = path.availableInterfaces.first, path.status != .unsatisfied {
                listener.updateDefaultInterface(i.name, interfaceIndex: Int32(i.index),
                                                isExpensive: path.isExpensive, isConstrained: path.isConstrained)
            } else {
                listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            }
            if first { first = false; sem.signal() }
        }
        monitor.start(queue: DispatchQueue.global())
        sem.wait()
    }

    func closeDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {
        reset()
    }

    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        guard let path = nwMonitor?.currentPath, path.status != .unsatisfied else { return IfaceIter([]) }
        return IfaceIter(path.availableInterfaces.map { it in
            let i = LibboxNetworkInterface()
            i.name = it.name
            i.index = Int32(it.index)
            switch it.type {
            case .wifi: i.type = LibboxInterfaceTypeWIFI
            case .cellular: i.type = LibboxInterfaceTypeCellular
            case .wiredEthernet: i.type = LibboxInterfaceTypeEthernet
            default: i.type = LibboxInterfaceTypeOther
            }
            return i
        })
    }

    final class IfaceIter: NSObject, LibboxNetworkInterfaceIteratorProtocol {
        private var it: IndexingIterator<[LibboxNetworkInterface]>
        private var cur: LibboxNetworkInterface?
        init(_ a: [LibboxNetworkInterface]) { it = a.makeIterator() }
        func hasNext() -> Bool { cur = it.next(); return cur != nil }
        func next() -> LibboxNetworkInterface? { cur }
    }

    // MARK: 其余接口（不需要的功能给默认值）

    func usePlatformAutoDetectInterfaceControl() -> Bool { false }
    func autoDetectInterfaceControl(_: Int32) throws {}
    func findConnectionOwner(_: Int32, sourceAddress _: String?, sourcePort _: Int32, destinationAddress _: String?, destinationPort _: Int32) throws -> LibboxConnectionOwner { throw err("not supported") }
    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }
    func clearDNSCache() {}
    func readWIFIState() -> LibboxWIFIState? { nil }
    func localDNSTransport() -> (any LibboxLocalDNSTransportProtocol)? { nil }
    func systemCertificates() -> (any LibboxStringIteratorProtocol)? { nil }
    func send(_: LibboxNotification?) throws {}
    func cancelNotification(_: String?, typeID _: Int32) throws {}
    func startNeighborMonitor(_: LibboxNeighborUpdateListenerProtocol?) throws {}
    func closeNeighborMonitor(_: LibboxNeighborUpdateListenerProtocol?) throws {}
    func registerMyInterface(_: String?) {}
    func usePlatformShell() -> Bool { false }
    func checkPlatformShell() throws { throw err("not supported") }
    func openShellSession(_: LibboxPlatformUser?, command _: String?, environ _: (any LibboxStringIteratorProtocol)?, term _: String?, rows _: Int32, cols _: Int32) throws -> any LibboxShellSessionProtocol { throw err("not supported") }
    func readSystemSSHHostKey(_ error: NSErrorPointer) -> String { error?.pointee = err("not supported"); return "" }
    func lookupSFTPServer(_ error: NSErrorPointer) -> String { error?.pointee = err("not supported"); return "" }
    func tailscaleHostname() -> String { "iPhone" }
    func usePlatformBridge() -> Bool { false }
    func createBridge(_: LibboxBridgeOptions?) throws -> any LibboxBridgeSessionProtocol { throw err("not supported") }
    func lookupUser(_: String?) throws -> LibboxPlatformUser { throw err("not supported") }
    func writeLog(_: String?) {}

    // CommandServerHandler
    func serviceStop() throws { tunnel?.cancelTunnelWithError(nil) }
    func serviceReload() throws {}
    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus { LibboxSystemProxyStatus() }
    func setSystemProxyEnabled(_: Bool) throws {}
    func triggerNativeCrash() throws {}
    func writeDebugMessage(_: String?) {}
    func connectSSHAgent(_ ret0_: UnsafeMutablePointer<Int32>?) throws { ret0_?.pointee = -1 }

    private func err(_ m: String) -> NSError {
        NSError(domain: "Koyun", code: 0, userInfo: [NSLocalizedDescriptionKey: m])
    }
}
