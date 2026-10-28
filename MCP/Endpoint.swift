import CryptoKit
import Darwin
import Foundation

/// Where one Ideator instance listens for cards from AI tools: a Unix socket in the user's own
/// temporary folder. A normal run has one name. A scratch run (`-CardsFolder`) has a name of its own
/// for each notes folder, so a helper given a folder reaches only the scratch run on that folder, and
/// a helper given none never reaches a scratch run.
nonisolated struct Endpoint: Equatable, Sendable {
    let path: String

    init(scratchFolder: URL?, directory: URL = Endpoint.userTemporaryDirectory) {
        let name = scratchFolder.map { "ideator-mcp-\(Self.tag(of: $0)).sock" } ?? "ideator-mcp.sock"
        path = directory.appending(path: name).path
    }

    /// 16 hex digits of the folder's path: a socket address holds at most 103 bytes.
    private static func tag(of folder: URL) -> String {
        SHA256.hash(data: Data(folder.standardizedFileURL.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// `confstr`, not `TMPDIR`: the AI tool starts the helper with an environment of its own, and
    /// both halves must name the same folder. Only this user can open it.
    static var userTemporaryDirectory: URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0 else { return FileManager.default.temporaryDirectory }
        return URL(filePath: String(cString: buffer), directoryHint: .isDirectory)
    }
}

/// The helper's command line: nothing for the owner's Ideator, or `-CardsFolder <folder>`, the
/// app's own argument, for the scratch run on that folder.
nonisolated struct HelperArguments: Equatable {
    /// Absolute, so the app the helper starts gets the same folder whatever its working directory.
    let scratchFolder: URL?

    struct Usage: Error, Equatable {
        static let text = "usage: ideator-mcp [-CardsFolder <folder>]"
    }

    init(_ arguments: [String], currentDirectory: URL) throws {
        switch arguments.count {
        case 0: scratchFolder = nil
        case 2 where arguments[0] == "-CardsFolder":
            scratchFolder = URL(filePath: arguments[1], directoryHint: .isDirectory, relativeTo: currentDirectory)
                .absoluteURL.standardizedFileURL
        default: throw Usage()
        }
    }
}

/// The few POSIX calls both halves make on the endpoint, each total: a failure is nil or false.
nonisolated enum Socket {
    /// A connection to whatever listens at `path`; nil when nothing does.
    static func connect(to path: String) -> Int32? {
        guard var address = address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        noSignalOnClosedPeer(fd)
        let status = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard status == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    /// A listening socket at `path` that only this user can reach. Nil while another process answers
    /// there; a file a killed instance left behind is replaced.
    static func listen(at path: String) -> Int32? {
        if let live = connect(to: path) {
            close(live)
            return nil
        }
        guard var address = address(path) else { return nil }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        noSignalOnClosedPeer(fd)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 16) == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    /// Writes `line` and a newline, all of it, or returns false.
    @discardableResult
    static func write(line: Data, to fd: Int32) -> Bool {
        var bytes = [UInt8](line)
        bytes.append(UInt8(ascii: "\n"))
        var sent = 0
        while sent < bytes.count {
            let n = bytes[sent...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return false }
            sent += n
        }
        return true
    }

    /// A peer that went away fails the write instead of killing this process with SIGPIPE.
    private static func noSignalOnClosedPeer(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    private static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }
}

/// Newline-ended lines from a file descriptor, each at most `limit` bytes, so no peer can make this
/// process hold an unbounded line. A line that passes the limit is skipped to its newline.
nonisolated struct LineReader {
    enum Next: Equatable {
        case line(Data)
        case tooLong
    }

    private let fd: Int32
    private let limit: Int
    private var buffer: [UInt8] = []
    /// How much of `buffer` holds no newline, so a long line is scanned once.
    private var searched = 0
    private var skipping = false
    private var ended = false

    init(fd: Int32, limit: Int) {
        self.fd = fd
        self.limit = limit
    }

    /// The next line without its newline; nil at the end of the input. A last line with no newline
    /// still counts.
    mutating func next() -> Next? {
        while true {
            if let newline = buffer[searched...].firstIndex(of: UInt8(ascii: "\n")) {
                let tooLong = skipping || newline > limit
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                searched = 0
                skipping = false
                return tooLong ? .tooLong : .line(line)
            }
            searched = buffer.count
            if buffer.count > limit {
                buffer.removeAll(keepingCapacity: true)
                searched = 0
                skipping = true
            }
            if ended {
                defer {
                    buffer = []
                    searched = 0
                }
                if skipping {
                    skipping = false
                    return .tooLong
                }
                return buffer.isEmpty ? nil : .line(Data(buffer))
            }
            var chunk = [UInt8](repeating: 0, count: 65_536)
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            if n <= 0 {
                ended = true
            } else {
                buffer.append(contentsOf: chunk[..<n])
            }
        }
    }
}
