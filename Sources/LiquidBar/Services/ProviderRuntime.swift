import Foundation

enum ProviderHealth: String, Codable, Sendable, Equatable {
    case normal
    case degraded
    case disconnected
}

struct ProviderActionDescriptor: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var symbol: String?
    var isEnabled: Bool
}

struct ProviderPanelState: Codable, Sendable, Equatable {
    var title: String
    var subtitle: String
    var progressCurrent: Double?
    var progressTotal: Double?
    var health: ProviderHealth
    var actions: [ProviderActionDescriptor]

    static func disconnected(title: String, subtitle: String? = nil) -> ProviderPanelState {
        ProviderPanelState(
            title: title,
            subtitle: subtitle ?? L10n.tr("Provider unavailable"),
            progressCurrent: nil,
            progressTotal: nil,
            health: .disconnected,
            actions: []
        )
    }
}

enum ProviderPayloadLimits {
    static let maxTitleCharacters = 80
    static let maxSubtitleCharacters = 160
    static let maxActions = 6
    static let maxActionIdCharacters = 80
    static let maxActionTitleCharacters = 48
    static let maxSymbolCharacters = 64

    static func bounded(_ value: String, maxCharacters: Int, fallback: String = "") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? fallback : trimmed
        return String(source.prefix(maxCharacters))
    }
}

extension ProviderActionDescriptor {
    func normalizedForDisplay() -> ProviderActionDescriptor? {
        let normalizedId = ProviderPayloadLimits.bounded(id, maxCharacters: ProviderPayloadLimits.maxActionIdCharacters)
        guard !normalizedId.isEmpty else { return nil }

        let normalizedTitle = ProviderPayloadLimits.bounded(
            title,
            maxCharacters: ProviderPayloadLimits.maxActionTitleCharacters,
            fallback: normalizedId
        )
        let normalizedSymbol = symbol.map {
            ProviderPayloadLimits.bounded($0, maxCharacters: ProviderPayloadLimits.maxSymbolCharacters)
        }.flatMap { $0.isEmpty ? nil : $0 }

        return ProviderActionDescriptor(
            id: normalizedId,
            title: normalizedTitle,
            symbol: normalizedSymbol,
            isEnabled: isEnabled
        )
    }
}

extension ProviderPanelState {
    func normalizedForDisplay(fallbackTitle: String) -> ProviderPanelState {
        var seenActionIds: Set<String> = []
        let normalizedActions = actions.compactMap { action -> ProviderActionDescriptor? in
            guard seenActionIds.count < ProviderPayloadLimits.maxActions,
                  let normalized = action.normalizedForDisplay(),
                  seenActionIds.insert(normalized.id).inserted else {
                return nil
            }
            return normalized
        }

        let normalizedTotal: Double? = progressTotal.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        let normalizedCurrent: Double? = progressCurrent.flatMap { value in
            guard value.isFinite, let normalizedTotal else { return nil }
            return min(max(0, value), normalizedTotal)
        }

        return ProviderPanelState(
            title: ProviderPayloadLimits.bounded(
                title,
                maxCharacters: ProviderPayloadLimits.maxTitleCharacters,
                fallback: fallbackTitle
            ),
            subtitle: ProviderPayloadLimits.bounded(subtitle, maxCharacters: ProviderPayloadLimits.maxSubtitleCharacters),
            progressCurrent: normalizedCurrent,
            progressTotal: normalizedTotal,
            health: health,
            actions: Array(normalizedActions)
        )
    }
}

protocol PluginProvider: Sendable {
    var id: String { get }
    func fetchState() async throws -> ProviderPanelState
    func performAction(_ actionId: String, payload: [String: String]?) async throws
}

enum ProviderRuntimeError: Error {
    case providerNotFound
    case timeout
    case invalidPayload
    case xpcError(String)
}

actor ProviderRuntime {
    private var providers: [String: any PluginProvider] = [:]
    private var failureCounts: [String: Int] = [:]

    func register(provider: any PluginProvider) {
        providers[provider.id] = provider
    }

    func resetProviders() {
        providers.removeAll()
        failureCounts.removeAll()
    }

    func registerProviders(from plugins: [PluginManager.LoadedPlugin]) {
        for plugin in plugins {
            guard let manifests = plugin.manifest.providers else { continue }
            for provider in manifests {
                let namespacedId = "plugin:\(plugin.manifest.id):provider:\(provider.id)"
                let transport = provider.transport?.lowercased() ?? "local"
                if transport == "xpc" {
                    guard let machService = provider.machServiceName, !machService.isEmpty else {
                        Log.plugins.warning("Skipping provider \(namespacedId, privacy: .public): missing mach_service_name for xpc transport")
                        continue
                    }
                    providers[namespacedId] = XPCBridgeProvider(id: namespacedId, machServiceName: machService)
                    continue
                }

                switch provider.kind.lowercased() {
                case "media", "music":
                    providers[namespacedId] = MediaControlProvider(id: namespacedId)
                default:
                    continue
                }
            }
        }
    }

    func fetchPanelState(
        providerId: String,
        timeoutMs: Int,
        circuitBreakerThreshold: Int,
        fallbackTitle: String
    ) async -> ProviderPanelState {
        guard let provider = providers[providerId] else {
            return .disconnected(title: fallbackTitle, subtitle: L10n.tr("Provider not found"))
        }

        if (failureCounts[providerId] ?? 0) >= circuitBreakerThreshold {
            return .disconnected(title: fallbackTitle, subtitle: L10n.tr("Provider circuit open"))
        }

        do {
            let state = try await withThrowingTaskGroup(of: ProviderPanelState.self) { group in
                group.addTask {
                    try await provider.fetchState()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(max(1, timeoutMs)) * 1_000_000)
                    throw ProviderRuntimeError.timeout
                }

                guard let first = try await group.next() else {
                    throw ProviderRuntimeError.timeout
                }
                group.cancelAll()
                return first
            }
            failureCounts[providerId] = 0
            return state.normalizedForDisplay(fallbackTitle: fallbackTitle)
        } catch {
            failureCounts[providerId, default: 0] += 1
            Log.plugins.warning("Provider fetch failed id=\(providerId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .disconnected(title: fallbackTitle, subtitle: L10n.tr("Provider timeout/error"))
        }
    }

    func performAction(
        providerId: String,
        actionId: String,
        payload: [String: String]?,
        timeoutMs: Int,
        circuitBreakerThreshold: Int
    ) async {
        guard let provider = providers[providerId] else { return }
        if (failureCounts[providerId] ?? 0) >= circuitBreakerThreshold { return }

        do {
            _ = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    try await provider.performAction(actionId, payload: payload)
                    return true
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(max(1, timeoutMs)) * 1_000_000)
                    throw ProviderRuntimeError.timeout
                }
                guard let first = try await group.next() else {
                    throw ProviderRuntimeError.timeout
                }
                group.cancelAll()
                return first
            }
            failureCounts[providerId] = 0
        } catch {
            failureCounts[providerId, default: 0] += 1
            Log.plugins.warning("Provider action failed id=\(providerId, privacy: .public) action=\(actionId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

@objc private protocol XPCProviderServiceProtocol {
    func fetchState(_ reply: @escaping (Data?, String?) -> Void)
    func performAction(_ actionId: String, payload: [String: String]?, reply: @escaping (String?) -> Void)
}

struct XPCBridgeProvider: PluginProvider {
    let id: String
    let machServiceName: String

    func fetchState() async throws -> ProviderPanelState {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(machServiceName: machServiceName, options: [])
            connection.remoteObjectInterface = NSXPCInterface(with: XPCProviderServiceProtocol.self)
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                connection.invalidate()
                continuation.resume(throwing: error)
            } as? XPCProviderServiceProtocol

            guard let proxy else {
                connection.invalidate()
                continuation.resume(throwing: ProviderRuntimeError.providerNotFound)
                return
            }

            proxy.fetchState { data, errorMessage in
                connection.invalidate()
                if let errorMessage, !errorMessage.isEmpty {
                    continuation.resume(throwing: ProviderRuntimeError.xpcError(errorMessage))
                    return
                }
                guard let data else {
                    continuation.resume(throwing: ProviderRuntimeError.invalidPayload)
                    return
                }
                do {
                    let state = try JSONDecoder().decode(ProviderPanelState.self, from: data)
                    continuation.resume(returning: state)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func performAction(_ actionId: String, payload: [String: String]?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let connection = NSXPCConnection(machServiceName: machServiceName, options: [])
            connection.remoteObjectInterface = NSXPCInterface(with: XPCProviderServiceProtocol.self)
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                connection.invalidate()
                continuation.resume(throwing: error)
            } as? XPCProviderServiceProtocol

            guard let proxy else {
                connection.invalidate()
                continuation.resume(throwing: ProviderRuntimeError.providerNotFound)
                return
            }

            proxy.performAction(actionId, payload: payload) { errorMessage in
                connection.invalidate()
                if let errorMessage, !errorMessage.isEmpty {
                    continuation.resume(throwing: ProviderRuntimeError.xpcError(errorMessage))
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }
}

struct MediaControlProvider: PluginProvider {
    let id: String

    func fetchState() async throws -> ProviderPanelState {
        ProviderPanelState(
            title: L10n.tr("Media"),
            subtitle: L10n.tr("Local provider"),
            progressCurrent: nil,
            progressTotal: nil,
            health: .normal,
            actions: [
                ProviderActionDescriptor(id: "previous", title: L10n.tr("Prev"), symbol: "backward.fill", isEnabled: true),
                ProviderActionDescriptor(id: "play_pause", title: L10n.tr("Play/Pause"), symbol: "playpause.fill", isEnabled: true),
                ProviderActionDescriptor(id: "next", title: L10n.tr("Next"), symbol: "forward.fill", isEnabled: true),
            ]
        )
    }

    func performAction(_ actionId: String, payload _: [String: String]?) async throws {
        let script: String
        switch actionId {
        case "play_pause":
            script = "tell application \"Music\" to playpause"
        case "next":
            script = "tell application \"Music\" to next track"
        case "previous":
            script = "tell application \"Music\" to previous track"
        default:
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try proc.run()
        proc.waitUntilExit()
    }
}
