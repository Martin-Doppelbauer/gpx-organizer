import Foundation

extension Tile {
    /// Human-readable name of a feature (first text segment), or nil.
    public func labelText(_ f: Feature) -> String? {
        ensureLoaded()
        guard f.labelKind != 0, let l = lbl else { return nil }
        let key = Int(f.labelKind) << 32 | f.label
        lock.lock()
        if let c = labelCache[key] { lock.unlock(); return c.isEmpty ? nil : c }
        lock.unlock()
        let text = readLabel(l, kind: f.labelKind, offset: f.label)
        lock.lock()
        if labelCache.count > 20000 { labelCache.removeAll() }
        labelCache[key] = text ?? ""
        lock.unlock()
        return text
    }

    private func readLabel(_ l: MappedFile, kind: UInt8, offset: Int) -> String? {
        var off = offset
        switch kind {
        case 3:
            off = l.u32(lbl6Off + offset) & 0x3FFFFF
        case 2:
            guard let n = net, net1Off != 0 else { return nil }
            let v = n.u32(net1Off + (offset << net1Shift))
            if v & 0x400000 != 0 { return nil }
            off = v & 0x3FFFFF
        default: break
        }
        off <<= lblShift
        guard off > 0, off < lbl1Len, lblCoding == 9 || lblCoding == 10 else { return nil }
        // 8-bit / UTF-8 strings: 0-terminated, 0x1B…0x1F separate segments (route shields), <0x07 ignored
        var bytes: [UInt8] = []
        var i = lbl1Off + off
        let end = min(lbl1Off + lbl1Len, i + 200)
        while i < end {
            let b = UInt8(l.u8(i)); i += 1
            if b == 0 { break }
            if b >= 0x1B && b <= 0x1F { if !bytes.isEmpty { break }; continue }
            if b < 0x07 { continue }
            bytes.append(b)
        }
        if bytes.isEmpty { return nil }
        let s: String
        if lblCoding == 10 || lblCodepage == 65001 { s = String(decoding: bytes, as: UTF8.self) }
        else {
            let cs = (1250...1258).contains(lblCodepage) ? lblCodepage : 1252
            let enc = CFStringConvertWindowsCodepageToEncoding(UInt32(cs))
            s = (CFStringCreateWithBytes(nil, bytes, bytes.count, enc, false) as String?) ?? String(decoding: bytes, as: UTF8.self)
        }
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}
