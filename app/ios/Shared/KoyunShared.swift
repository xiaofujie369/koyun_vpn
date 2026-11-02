import Foundation

/// 主 App 与 VPN 扩展共用的标识（需在 Apple 开发者后台创建同名 App Group）
enum KoyunShared {
    static let appGroup = "group.com.koyun.vpn"
    static let extensionBundleId = "com.koyun.vpn.PacketTunnel"
}
