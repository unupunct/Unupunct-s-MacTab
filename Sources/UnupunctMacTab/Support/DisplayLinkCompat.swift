// SPDX-License-Identifier: GPL-3.0-or-later
// Monterey (macOS 12) port: stand-in for CADisplayLink on macOS (macOS 14+).

import AppKit
import QuartzCore

/// Same surface the app uses from `CADisplayLink`. On macOS 14+ it drives itself from
/// the real display link. On macOS 12/13 it fires from a timer at the display's
/// refresh rate (not vsync-locked, so animations are slightly less smooth).
final class DisplayLinkCompat: NSObject {
    private(set) var timestamp: CFTimeInterval = 0
    private(set) var targetTimestamp: CFTimeInterval = 0
    /// Seconds between this frame and the next, as `CADisplayLink.duration`.
    var duration: CFTimeInterval { max(0, targetTimestamp - timestamp) }
    /// Accepted for source compatibility; the timer path always runs at the display rate.
    var preferredFramesPerSecond: Float = 0

    private var target: AnyObject?
    private let selector: Selector
    private let frameInterval: TimeInterval
    private var timer: Timer?
    private var real: AnyObject?
    private let makeReal: ((DisplayLinkCompat) -> AnyObject?)?
    private var invalidated = false

    fileprivate init(target: AnyObject, selector: Selector, framesPerSecond: Int,
                     makeReal: ((DisplayLinkCompat) -> AnyObject?)?) {
        self.target = target
        self.selector = selector
        self.frameInterval = 1.0 / Double(max(30, framesPerSecond))
        self.makeReal = makeReal
    }

    func add(to runLoop: RunLoop, forMode mode: RunLoop.Mode) {
        guard !invalidated, timer == nil, real == nil else { return }
        if let makeReal, let link = makeReal(self) { real = link; return }
        let timer = Timer(timeInterval: frameInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.deliver(timestamp: now, target: now + self.frameInterval)
        }
        runLoop.add(timer, forMode: mode)
        self.timer = timer
    }

    func invalidate() {
        invalidated = true
        timer?.invalidate(); timer = nil
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) { (real as? CADisplayLink)?.invalidate() }
        #endif
        real = nil
        target = nil
    }

    var isPaused: Bool {
        get { timer == nil && real == nil }
        set { /* not used by the app; start/stop through add and invalidate */ }
    }

    fileprivate func deliver(timestamp: CFTimeInterval, target targetTime: CFTimeInterval) {
        self.timestamp = timestamp
        self.targetTimestamp = targetTime
        _ = target?.perform(selector, with: self)
    }

    #if compiler(>=5.9)
    @available(macOS 14.0, *)
    @objc fileprivate func realFire(_ link: CADisplayLink) {
        deliver(timestamp: link.timestamp, target: link.targetTimestamp)
    }
    #endif
}

extension NSView {
    func displayLinkCompat(target: AnyObject, selector: Selector) -> DisplayLinkCompat {
        let fps = window?.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 60
        return DisplayLinkCompat(target: target, selector: selector, framesPerSecond: fps, makeReal: realFactory)
    }

    private var realFactory: ((DisplayLinkCompat) -> AnyObject?)? {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) {
            return { [weak self] compat in
                guard let self else { return nil }
                let link = self.displayLink(target: compat, selector: #selector(DisplayLinkCompat.realFire(_:)))
                link.add(to: .main, forMode: .common)
                return link
            }
        }
        #endif
        return nil
    }
}

extension NSScreen {
    func displayLinkCompat(target: AnyObject, selector: Selector) -> DisplayLinkCompat {
        let factory: ((DisplayLinkCompat) -> AnyObject?)?
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) {
            factory = { [weak self] compat in
                guard let self else { return nil }
                let link = self.displayLink(target: compat, selector: #selector(DisplayLinkCompat.realFire(_:)))
                link.add(to: .main, forMode: .common)
                return link
            }
        } else { factory = nil }
        #else
        factory = nil
        #endif
        return DisplayLinkCompat(target: target, selector: selector,
                                 framesPerSecond: maximumFramesPerSecond, makeReal: factory)
    }
}
