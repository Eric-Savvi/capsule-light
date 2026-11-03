import Foundation
import IOKit.hid

/// Raw USB HID access to the NZXT Capsule Elite. Protocol: HANDOVER.md.
/// Calls block the caller until the mic answers (a few ms) or 500 ms pass.
final class CapsuleHID: @unchecked Sendable {
    static let reportID: UInt8 = 0xA8
    // The only commands this app may send (HANDOVER.md safety rule 1).
    static let writes: Set<UInt8> = [0x21, 0x31, 0x2E, 0x35, 0x30, 0x37]
    static let reads: Set<UInt8> = [0x22, 0x32, 0x2F, 0x36, 0x38, 0x39]

    enum Failure: LocalizedError {
        case notConnected, noReply(UInt8), sendFailed(UInt8, IOReturn)
        var errorDescription: String? {
            switch self {
            case .notConnected: "Capsule not connected"
            case .noReply(let c): String(format: "Capsule didn't acknowledge command 0x%02X", c)
            case .sendFailed(let c, let r): String(format: "Sending 0x%02X failed (IOReturn 0x%08X)", c, r)
            }
        }
    }

    /// Called on the main queue when the mic appears or disappears.
    var onConnectionChange: ((Bool) -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let lock = NSLock()
    private var device: IOHIDDevice?
    private var replies: [[UInt8]] = []
    private let replyArrived = DispatchSemaphore(value: 0)
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    init() {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x1E71,
            kIOHIDProductIDKey: 0x260E,
            kIOHIDDeviceUsagePageKey: 0xFFC0, // primary page is Consumer (mute button)
        ] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            Unmanaged<CapsuleHID>.fromOpaque(ctx!).takeUnretainedValue().attach(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            Unmanaged<CapsuleHID>.fromOpaque(ctx!).takeUnretainedValue().detach(dev)
        }, ctx)
        // HID callbacks run on their own thread so a blocked caller still gets its reply.
        Thread { [manager] in
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            CFRunLoopRun()
        }.start()
    }

    var isConnected: Bool { lock.withLock { device != nil } }

    private func attach(_ dev: IOHIDDevice) {
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, 64, { ctx, _, _, _, id, report, len in
            guard id == CapsuleHID.reportID else { return } // skip the mute button's report 0x03
            let me = Unmanaged<CapsuleHID>.fromOpaque(ctx!).takeUnretainedValue()
            me.lock.withLock { me.replies.append(Array(UnsafeBufferPointer(start: report, count: len))) }
            me.replyArrived.signal()
        }, Unmanaged.passUnretained(self).toOpaque())
        lock.withLock { device = dev }
        DispatchQueue.main.async { self.onConnectionChange?(true) }
    }

    private func detach(_ dev: IOHIDDevice) {
        lock.withLock { if device === dev { device = nil } }
        DispatchQueue.main.async { self.onConnectionChange?(false) }
    }

    /// Sends `[0xA8, cmd, payload…]` (64 bytes) and returns the first reply that `matches`.
    private func request(_ cmd: UInt8, _ payload: [UInt8], matches: ([UInt8]) -> Bool) throws -> [UInt8] {
        guard let dev = lock.withLock({ replies.removeAll(); return device }) else { throw Failure.notConnected }
        var buf = [Self.reportID, cmd] + payload
        buf += [UInt8](repeating: 0, count: 64 - buf.count)
        let r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(Self.reportID), buf, buf.count)
        guard r == kIOReturnSuccess else { throw Failure.sendFailed(cmd, r) }
        let deadline = DispatchTime.now() + .milliseconds(500)
        while replyArrived.wait(timeout: deadline) == .success {
            if let hit = lock.withLock({ replies.first(where: matches) }) { return hit }
        }
        throw Failure.noReply(cmd)
    }

    /// Reads one setting; returns the data bytes after `[0xA8, cmd]`.
    func read(_ cmd: UInt8) throws -> [UInt8] {
        precondition(Self.reads.contains(cmd), "refusing read 0x\(String(cmd, radix: 16))")
        return Array(try request(cmd, []) { $0.count > 2 && $0[0] == Self.reportID && $0[1] == cmd }.dropFirst(2))
    }

    /// Writes one setting and requires the `[0xA8, 0xFF, cmd]` ACK (safety rule 3).
    func write(_ cmd: UInt8, _ payload: [UInt8]) throws {
        precondition(Self.writes.contains(cmd), "refusing write 0x\(String(cmd, radix: 16))")
        _ = try request(cmd, payload) { $0.count > 2 && $0[0] == Self.reportID && $0[1] == 0xFF && $0[2] == cmd }
    }
}
