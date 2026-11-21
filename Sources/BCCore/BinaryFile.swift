import Foundation

/// Read-only memory-mapped file with little-endian accessors (out-of-range reads return 0).
public final class MappedFile {
    let base: UnsafeRawPointer?
    public let size: Int
    /// IMG containers may be XOR-obscured with a single byte.
    public var xorKey: UInt8 = 0
    private var parent: MappedFile?
    private var owned: UnsafeMutableRawPointer?
    private var mapped = false

    /// A view of `size` bytes at `offset` inside another file (shares its memory).
    public init(parent: MappedFile, offset: Int, size: Int) {
        self.parent = parent
        self.base = parent.base.map { $0 + offset }
        self.size = max(0, min(size, parent.size - offset))
        self.xorKey = parent.xorKey
    }

    /// An in-memory copy (used for non-contiguous subfiles).
    public init(copying data: Data, xorKey: UInt8 = 0) {
        size = data.count
        let p = UnsafeMutableRawPointer.allocate(byteCount: max(1, data.count), alignment: 8)
        data.withUnsafeBytes { if let b = $0.baseAddress { p.copyMemory(from: b, byteCount: data.count) } }
        owned = p; base = UnsafeRawPointer(p); self.xorKey = xorKey
    }

    public init?(path: String) {
        let fd = open(path, O_RDONLY)
        if fd < 0 { return nil }
        defer { close(fd) }
        var st = stat()
        if fstat(fd, &st) != 0 { return nil }
        size = Int(st.st_size)
        if size == 0 { base = nil; return }
        let p = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0)
        if p == MAP_FAILED { return nil }
        base = UnsafeRawPointer(p)
        mapped = true
    }

    deinit {
        if mapped, let b = base { munmap(UnsafeMutableRawPointer(mutating: b), size) }
        owned?.deallocate()
    }

    @inline(__always) public func u8(_ o: Int) -> Int {
        guard let b = base, o >= 0, o < size else { return 0 }
        return Int(b.load(fromByteOffset: o, as: UInt8.self) ^ xorKey)
    }
    @inline(__always) public func u16(_ o: Int) -> Int { u8(o) | (u8(o + 1) << 8) }
    @inline(__always) public func i16(_ o: Int) -> Int { Int(Int16(truncatingIfNeeded: u16(o))) }
    @inline(__always) public func u24(_ o: Int) -> Int { u8(o) | (u8(o + 1) << 8) | (u8(o + 2) << 16) }
    @inline(__always) public func i24(_ o: Int) -> Int {
        let v = u24(o)
        return v >= 0x800000 ? v - 0x1000000 : v
    }
    @inline(__always) public func u32(_ o: Int) -> Int { u16(o) | (u16(o + 2) << 16) }
    public func string(_ o: Int, _ n: Int) -> String {
        var bytes = [UInt8](); for i in 0..<n { bytes.append(UInt8(u8(o + i))) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// LSB-first bit reader used by Garmin line bitstreams.
struct BitReader {
    let file: MappedFile
    let start: Int
    let bitCount: Int
    var pos = 0
    init(file: MappedFile, start: Int, byteLength: Int) {
        self.file = file; self.start = start; self.bitCount = byteLength * 8
    }
    var remaining: Int { bitCount - pos }
    @inline(__always) mutating func bit() -> Int {
        let v = (file.u8(start + (pos >> 3)) >> (pos & 7)) & 1
        pos += 1
        return v
    }
    mutating func read(_ n: Int) -> Int {
        var v = 0
        for i in 0..<n { v |= bit() << i }
        return v
    }
}
