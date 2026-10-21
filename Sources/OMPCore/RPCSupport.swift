@preconcurrency import Foundation
import Darwin

// FileHandle.read(upToCount:) may fill its requested count before returning.
// POSIX read returns the available pipe bytes, which an interactive peer requires.
func readPipe(_ handle: FileHandle, untilExit process: Process, remainingAfterExit: inout Int?) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: 65536)
    while true {
        if remainingAfterExit == nil, !process.isRunning {
            // Drain the bytes already buffered at parent exit. A descendant must
            // not keep the session alive by holding or continually writing stdout.
            var available: Int32 = 0
            // Darwin FIONREAD = _IOR('f',127,int); this C macro is not imported by Swift.
            guard ioctl(handle.fileDescriptor, 0x4004667f, &available) == 0 else { throw POSIXError(.EIO) }
            remainingAfterExit = Int(available)
        }
        if remainingAfterExit == 0 { return Data() }
        var state = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&state, 1, 100)
        if ready == 0 { continue }
        if ready < 0 { if errno == EINTR { continue }; throw POSIXError(.EIO) }
        let count = Darwin.read(handle.fileDescriptor, &bytes, min(bytes.count, remainingAfterExit ?? bytes.count))
        if count >= 0 {
            if let remaining = remainingAfterExit { remainingAfterExit = remaining - count }
            return Data(bytes.prefix(count))
        }
        if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

extension JSONValue: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .object(let o): hasher.combine(0); for key in o.keys.sorted() { hasher.combine(key); hasher.combine(o[key]) }
        case .array(let a): hasher.combine(1); hasher.combine(a)
        case .string(let s): hasher.combine(2); hasher.combine(s)
        case .number(let n): hasher.combine(3); hasher.combine(n)
        case .bool(let b): hasher.combine(4); hasher.combine(b)
        case .null: hasher.combine(5)
        }
    }
}
