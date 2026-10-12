// SPDX-License-Identifier: MIT
import Foundation

public final class NetworkMetricsSource: ObservableObject {
    @Published public private(set) var latest: NetworkSnapshot?

    private var timer: Timer?
    private var publicIPTimer: Timer?
    private var previousCounters: [InterfaceCounters]?
    private var previousTimestamp: Date?
    private var currentPublicIP: String?
    private var isFetchingPublicIP = false
    private var publicIPLookupEnabled = true

    public init() {}

    public func start(interval: TimeInterval = 1.0) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
        restartPublicIPTimerIfEnabled()
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        publicIPTimer?.invalidate(); publicIPTimer = nil
        previousCounters = nil
        previousTimestamp = nil
    }

    public func refreshPublicIPNow() {
        guard publicIPLookupEnabled else { return }
        fetchPublicIP()
    }

    /// spec §6: public-IP lookup is a privacy-relevant external call and must be
    /// independently toggleable. Reflected immediately: turning it off cancels any pending
    /// timer; turning it on restarts it and fetches right away.
    public func setPublicIPLookupEnabled(_ enabled: Bool) {
        publicIPLookupEnabled = enabled
        if enabled {
            restartPublicIPTimerIfEnabled()
        } else {
            publicIPTimer?.invalidate()
            publicIPTimer = nil
        }
    }

    private func restartPublicIPTimerIfEnabled() {
        guard publicIPLookupEnabled, timer != nil else { return }
        publicIPTimer?.invalidate()
        publicIPTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.fetchPublicIP() }
        RunLoop.main.add(publicIPTimer!, forMode: .common)
        fetchPublicIP()
    }

    private func tick() {
        let (localIP, counters) = IPAddressParser.readCurrentState()
        let now = Date()
        if let prevCounters = previousCounters, let prevTime = previousTimestamp {
            let result = ThroughputCalculator.throughput(previous: prevCounters, current: counters, elapsed: now.timeIntervalSince(prevTime))
            let perInterface = result.perInterface.mapValues { $0.rx + $0.tx }
            latest = NetworkSnapshot(rxBytesPerSec: result.rxBytesPerSec, txBytesPerSec: result.txBytesPerSec, perInterface: perInterface, localIPv4: localIP, publicIP: currentPublicIP)
        }
        previousCounters = counters
        previousTimestamp = now
    }

    private func fetchPublicIP() {
        // Review Focus: disabling the widget mid-flight must not deliver a result into a
        // torn-down source. Guard with a simple flag checked after the await.
        guard !isFetchingPublicIP else { return }
        isFetchingPublicIP = true
        Task { [weak self] in
            let ip = await PublicIPFetcher.fetch()
            guard let self else { return }
            self.isFetchingPublicIP = false
            guard self.timer != nil else { return } // stop() was called while this was in flight
            self.currentPublicIP = ip
            if let existing = self.latest {
                self.latest = NetworkSnapshot(rxBytesPerSec: existing.rxBytesPerSec, txBytesPerSec: existing.txBytesPerSec, perInterface: existing.perInterface, localIPv4: existing.localIPv4, publicIP: ip)
            }
        }
    }
}
