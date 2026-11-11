// SPDX-License-Identifier: GPL-3.0-or-later
// Monterey (macOS 12.3+) port: one-shot screen capture without SCScreenshotManager (macOS 14).

import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit

/// Takes one frame from a short-lived `SCStream`. Same call shape as
/// `SCScreenshotManager.captureImage(contentFilter:configuration:)`.
@available(macOS 12.3, *)
enum SCScreenshotCompat {
    struct CaptureFailed: Error {}

    static func captureImage(contentFilter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) {
            return try await SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration)
        }
        #endif
        let grabber = SingleFrameGrabber()
        return try await grabber.grab(filter: contentFilter, configuration: configuration)
    }

    /// Backing scale of the display a filter shows (`SCContentFilter.pointPixelScale` is macOS 14).
    static func pixelScale(of filter: SCContentFilter) -> CGFloat {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) { return CGFloat(filter.pointPixelScale) }
        #endif
        return NSScreen.main?.backingScaleFactor ?? 2
    }
}

@available(macOS 12.3, *)
private final class SingleFrameGrabber: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "single-frame-grabber")
    private let context = CIContext()
    private var stream: SCStream?
    private var continuation: CheckedContinuation<CGImage, Error>?
    private let lock = NSLock()

    func grab(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CGImage, Error>) in
            lock.lock(); continuation = cont; lock.unlock()
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            self.stream = stream
            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            } catch { finish(.failure(error)); return }
            stream.startCapture { [weak self] error in
                if let error { self?.finish(.failure(error)) }
            }
            // A stream that never produces a complete frame must not hang the caller.
            queue.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.finish(.failure(SCScreenshotCompat.CaptureFailed()))
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        if let cgImage = context.createCGImage(image, from: image.extent) {
            finish(.success(cgImage))
        } else {
            finish(.failure(SCScreenshotCompat.CaptureFailed()))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<CGImage, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        guard let cont else { return }
        let running = stream
        stream = nil
        running?.stopCapture { _ in }
        cont.resume(with: result)
    }
}

@available(macOS 12.3, *)
extension SCStream {
    /// `synchronizationClock` needs macOS 13. On macOS 12.3 the stream's sample buffers
    /// are stamped with the host time clock (untested on a real macOS 12 machine).
    var synchronizationClockCompat: CMClock? {
        if #available(macOS 13.0, *) { return synchronizationClock }
        return CMClockGetHostTimeClock()
    }
}
