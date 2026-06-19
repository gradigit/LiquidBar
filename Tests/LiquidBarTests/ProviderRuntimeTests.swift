import Testing
import Foundation
@testable import LiquidBar

private struct FastFixtureProvider: PluginProvider {
    let id: String

    func fetchState() async throws -> ProviderPanelState {
        ProviderPanelState(
            title: "Fixture",
            subtitle: "Healthy",
            progressCurrent: nil,
            progressTotal: nil,
            health: .normal,
            actions: [ProviderActionDescriptor(id: "ping", title: "Ping", symbol: nil, isEnabled: true)]
        )
    }

    func performAction(_: String, payload _: [String: String]?) async throws {}
}

private struct SlowFixtureProvider: PluginProvider {
    let id: String
    let delayNs: UInt64

    func fetchState() async throws -> ProviderPanelState {
        try await Task.sleep(nanoseconds: delayNs)
        return ProviderPanelState(
            title: "Slow",
            subtitle: "Eventually",
            progressCurrent: nil,
            progressTotal: nil,
            health: .normal,
            actions: []
        )
    }

    func performAction(_: String, payload _: [String: String]?) async throws {
        try await Task.sleep(nanoseconds: delayNs)
    }
}

@Suite("ProviderRuntime", .serialized)
struct ProviderRuntimeTests {
    @Test func testFetchPanelStateSuccess() async {
        let runtime = ProviderRuntime()
        await runtime.register(provider: FastFixtureProvider(id: "fixture.fast"))

        let state = await runtime.fetchPanelState(
            providerId: "fixture.fast",
            timeoutMs: 500,
            circuitBreakerThreshold: 3,
            fallbackTitle: "Fallback"
        )

        #expect(state.title == "Fixture")
        #expect(state.health == .normal)
        #expect(state.actions.count == 1)
    }

    @Test func testFetchPanelStateTimeoutAndCircuitBreaker() async {
        let runtime = ProviderRuntime()
        await runtime.register(provider: SlowFixtureProvider(id: "fixture.slow", delayNs: 200_000_000))

        let first = await runtime.fetchPanelState(
            providerId: "fixture.slow",
            timeoutMs: 10,
            circuitBreakerThreshold: 2,
            fallbackTitle: "Fallback"
        )
        #expect(first.health == .disconnected)

        let second = await runtime.fetchPanelState(
            providerId: "fixture.slow",
            timeoutMs: 10,
            circuitBreakerThreshold: 2,
            fallbackTitle: "Fallback"
        )
        #expect(second.health == .disconnected)

        let third = await runtime.fetchPanelState(
            providerId: "fixture.slow",
            timeoutMs: 10,
            circuitBreakerThreshold: 2,
            fallbackTitle: "Fallback"
        )
        #expect(third.health == .disconnected)
        #expect(third.subtitle.contains("circuit open"))
    }

    @Test func testFetchMissingProviderReturnsDisconnected() async {
        let runtime = ProviderRuntime()
        let state = await runtime.fetchPanelState(
            providerId: "fixture.missing",
            timeoutMs: 50,
            circuitBreakerThreshold: 2,
            fallbackTitle: "Fallback"
        )
        #expect(state.health == .disconnected)
        #expect(state.subtitle.contains("not found"))
    }

    @Test func testRegisterProvidersSkipsInvalidXPCProviderManifest() async {
        let runtime = ProviderRuntime()
        let manifest = PluginManifest(
            id: "com.example.invalidxpc",
            name: "Invalid XPC",
            version: "1.0.0",
            apiVersion: 1,
            customItems: nil,
            providers: [
                .init(id: "media0", kind: "media", transport: "xpc", machServiceName: nil)
            ],
            tiles: nil
        )
        let plugin = PluginManager.LoadedPlugin(manifest: manifest, path: URL(fileURLWithPath: "/tmp/invalidxpc/manifest.json"))
        await runtime.registerProviders(from: [plugin])

        let state = await runtime.fetchPanelState(
            providerId: "plugin:com.example.invalidxpc:provider:media0",
            timeoutMs: 50,
            circuitBreakerThreshold: 2,
            fallbackTitle: "Fallback"
        )
        #expect(state.health == .disconnected)
        #expect(state.subtitle.contains("not found"))
    }

    @Test func testRegisterProvidersSupportsXPCBridgePath() async {
        let runtime = ProviderRuntime()
        let manifest = PluginManifest(
            id: "com.example.xpc",
            name: "XPC",
            version: "1.0.0",
            apiVersion: 1,
            customItems: nil,
            providers: [
                .init(id: "media0", kind: "media", transport: "xpc", machServiceName: "com.example.missing.service")
            ],
            tiles: nil
        )
        let plugin = PluginManager.LoadedPlugin(manifest: manifest, path: URL(fileURLWithPath: "/tmp/xpc/manifest.json"))
        await runtime.registerProviders(from: [plugin])

        let state = await runtime.fetchPanelState(
            providerId: "plugin:com.example.xpc:provider:media0",
            timeoutMs: 200,
            circuitBreakerThreshold: 2,
            fallbackTitle: "Fallback"
        )
        #expect(state.health == .disconnected)
        #expect(state.subtitle.contains("timeout/error"))
    }
}
