import Darwin
import Foundation

/// File-system work too small to leave the main actor, and the helpers the
/// concurrent work shares.
nonisolated enum Files {
    static var fm: FileManager { FileManager.default }

    static func exists(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0
    }

    static func isFile(_ url: URL) -> Bool {
        var st = stat()
        return stat(url.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG
    }

    static func isDirectory(_ url: URL) -> Bool {
        var st = stat()
        return stat(url.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    static func size(_ url: URL) -> Int64? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return Int64(st.st_size)
    }

    /// (mtime in ns, size, inode), the signature a re-read compares.
    static func signature(_ url: URL) -> [Int64]? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        let ns = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
        return [ns, Int64(st.st_size), Int64(bitPattern: UInt64(st.st_ino))]
    }

    static func list(_ dir: URL) -> [String] {
        (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    static func read(_ url: URL) -> String? {
        guard let data = fm.contents(atPath: url.path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func makeDirectory(_ url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Writes beside the target and renames over it, so a reader never sees
    /// half a file.
    static func writeAtomic(_ data: Data, to url: URL) throws {
        try makeDirectory(url.deletingLastPathComponent())
        let tmp = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).\(getpid()).tmp")
        do {
            try data.write(to: tmp)
            try rename(tmp, url)
        } catch {
            unlink(tmp.path)
            throw error
        }
    }

    static func rename(_ from: URL, _ to: URL) throws {
        if Darwin.rename(from.path, to.path) != 0 { throw POSIXError(errno) }
    }

    static func remove(_ url: URL) {
        unlink(url.path)
    }

    static func removeTree(_ url: URL) {
        try? fm.removeItem(at: url)
    }

    /// Moves a file, copying across volumes.
    static func move(_ from: URL, _ to: URL) throws {
        if Darwin.rename(from.path, to.path) == 0 { return }
        let code = errno
        guard code == EXDEV else { throw POSIXError(code) }
        try copyFile(from, to)
        unlink(from.path)
    }

    static func copyFile(_ from: URL, _ to: URL) throws {
        if copyfile(from.path, to.path, nil, copyfile_flags_t(COPYFILE_DATA)) != 0 { throw POSIXError(errno) }
    }

    /// Creates an empty file, failing if it cannot.
    static func touch(_ url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT, 0o644)
        guard fd >= 0 else { throw POSIXError(errno) }
        close(fd)
    }

    /// The system's words for an error, as `strerror` gives them when it is
    /// a system error.
    static func reason(_ error: any Error) -> String {
        if let p = error as? POSIXError { return String(cString: strerror(p.code.rawValue)) }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain { return String(cString: strerror(Int32(ns.code))) }
        if let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError, u.domain == NSPOSIXErrorDomain {
            return String(cString: strerror(Int32(u.code)))
        }
        return ns.localizedDescription
    }

    static func diskFree(near url: URL) -> Int64 {
        var probe = url
        while !exists(probe) && probe.path != "/" { probe = probe.deletingLastPathComponent() }
        var s = statfs()
        guard statfs(probe.path, &s) == 0 else { return 0 }
        return Int64(s.f_bavail) * Int64(s.f_bsize)
    }
}

extension POSIXError {
    nonisolated init(_ code: Int32) {
        self.init(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
