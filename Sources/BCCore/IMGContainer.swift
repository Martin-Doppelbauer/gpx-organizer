import Foundation

/// Garmin IMG container (gmapsupp.img and similar): header 0x600 bytes, 512-byte FAT entries, subfiles in blocks.
public final class IMGContainer {
    public let file: MappedFile
    public private(set) var subfiles: [String: MappedFile] = [:]   // "NAME.EXT" (upper case)
    public private(set) var description = ""

    public init?(path: String) {
        guard let f = MappedFile(path: path), f.size > 0x800 else { return nil }
        file = f
        f.xorKey = UInt8(f.u8(0))                    // value read raw (key still 0 here)
        guard f.string(0x10, 6) == "DSKIMG", f.string(0x41, 6) == "GARMIN" else { return nil }
        description = f.string(0x49, 20).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        let blockSize = 1 << (f.u8(0x61) + f.u8(0x62))
        guard blockSize >= 512, blockSize <= 1 << 20 else { return nil }

        var off = 0x600
        // leading entries with flag 0 describe the header area
        while off + 0x200 <= f.size, f.u8(off) == 0 { off += 0x200 }
        struct Part { var size = 0; var blocks: [Int] = [] }
        var order: [String] = []
        var parts: [String: Part] = [:]
        while off + 0x200 <= f.size, f.u8(off) == 1 {
            let name = f.string(off + 1, 8).trimmingCharacters(in: .whitespaces)
            let type = f.string(off + 9, 3).trimmingCharacters(in: .whitespaces)
            let size = f.u32(off + 0x0C)
            let key = (name + "." + type).uppercased()
            if !name.isEmpty {
                if parts[key] == nil { parts[key] = Part(); order.append(key) }
                if size != 0 && parts[key]!.size == 0 { parts[key]!.size = size }
                for i in 0..<240 {
                    let b = f.u16(off + 0x20 + i * 2)
                    if b == 0xFFFF { break }
                    parts[key]!.blocks.append(b)
                }
            }
            off += 0x200
        }
        guard !parts.isEmpty else { return nil }
        for key in order {
            guard let p = parts[key], p.size > 0, let first = p.blocks.first else { continue }
            let contiguous = zip(p.blocks, p.blocks.dropFirst()).allSatisfy { $1 == $0 + 1 }
            if contiguous {
                subfiles[key] = MappedFile(parent: f, offset: first * blockSize, size: p.size)
            } else {
                var d = Data()
                for b in p.blocks where d.count < p.size {
                    let start = b * blockSize
                    guard start < f.size else { break }
                    for i in 0..<min(blockSize, p.size - d.count) where start + i < f.size { d.append(UInt8(f.u8(start + i))) }
                }
                subfiles[key] = MappedFile(copying: d)
            }
        }
    }

    /// Distinct 8-character map names that have a TRE subfile.
    public var tileNames: [String] {
        subfiles.keys.filter { $0.hasSuffix(".TRE") }.map { String($0.dropLast(4)) }.sorted()
    }
}
