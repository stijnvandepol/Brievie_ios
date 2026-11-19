import Foundation

/// The host's `public_host_binding` (`apps/devices/proof.py`), mirrored: which host names a public certificate
/// authority can certify, so that a connection validated by the system roots may bind to the name.
extension PairingProof {
    /// Names no public certificate authority certifies (RFC 6761, RFC 6762, RFC 8375, ICANN's .internal).
    static let uncertifiableSuffixes = [
        ".local", ".lan", ".home.arpa", ".internal", ".localhost", ".test", ".invalid", ".example"
    ]

    /// The trust binding for `host`, or `nil` when no public certificate authority can certify it.
    ///
    /// Normalised as the server normalises its own addresses: lower case, ASCII (the caller passes the IDNA
    /// form), no brackets, no trailing dot; an IP address in its compressed form. `nil` for the special-use
    /// names above, single-label names such as `localhost`, and IP addresses that are not global. Where the
    /// two sides could disagree the app is stricter (an IPv4-mapped or multicast address, a dotted number that
    /// is not a plain IPv4 address): that address then cannot pair by link, but never sends a proof the server
    /// would count as wrong.
    static func publicHostBinding(_ host: String) -> String? {
        var name = host.trimmingCharacters(in: .whitespaces)
        name = String(name.drop { $0 == "[" || $0 == "]" })
        while let last = name.last, last == "[" || last == "]" { name.removeLast() }
        while name.hasSuffix(".") { name.removeLast() }
        name = name.lowercased()
        guard !name.isEmpty, name.utf8.allSatisfy({ $0 < 0x80 && $0 != UInt8(ascii: "%") }) else { return nil }

        if name.contains(":") {
            guard let address = IPv6(name) else { return nil }
            return address.isGlobal ? address.compressed : nil
        }
        if name.utf8.allSatisfy({ $0 == UInt8(ascii: ".") || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) {
            guard let address = IPv4(name) else { return nil }
            return address.isGlobal ? address.text : nil
        }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1, labels.allSatisfy({ (1...63).contains($0.utf8.count) }) else { return nil }
        let certifiable = !uncertifiableSuffixes.contains { suffix in
            name.hasSuffix(suffix) || name == suffix.dropFirst()
        }
        return certifiable ? name : nil
    }
}

/// A strictly written IPv4 address (four decimal parts without leading zeros), as Python's `ipaddress` reads it.
struct IPv4 {
    let value: UInt32

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard
                (1...3).contains(part.count), part == "0" || !part.hasPrefix("0"),
                let byte = UInt8(part)
            else {
                return nil
            }
            value = value << 8 | UInt32(byte)
        }
        self.value = value
    }

    var text: String {
        [24, 16, 8, 0].map { String(value >> UInt32($0) & 0xFF) }.joined(separator: ".")
    }

    /// Python 3.13's `is_global`, with multicast left out.
    var isGlobal: Bool {
        let notGlobal: [(UInt32, Int)] = [
            (0x0000_0000, 8), (0x0A00_0000, 8), (0x7F00_0000, 8), (0xA9FE_0000, 16), (0xAC10_0000, 12),
            (0xC000_0000, 24), (0xC000_00AA, 31), (0xC000_0200, 24), (0xC0A8_0000, 16), (0xC612_0000, 15),
            (0xC633_6400, 24), (0xCB00_7100, 24), (0xF000_0000, 4), (0xFFFF_FFFF, 32),
            // Shared address space (100.64.0.0/10) and multicast (224.0.0.0/4).
            (0x6440_0000, 10), (0xE000_0000, 4)
        ]
        let exceptions: [(UInt32, Int)] = [(0xC000_0009, 32), (0xC000_000A, 32)]
        if exceptions.contains(where: contains) { return true }
        return !notGlobal.contains(where: contains)
    }

    private func contains(_ network: (UInt32, Int)) -> Bool {
        let mask: UInt32 = network.1 == 0 ? 0 : ~UInt32(0) << UInt32(32 - network.1)
        return value & mask == network.0 & mask
    }
}

/// An IPv6 address (no zone), read with `inet_pton`.
struct IPv6 {
    let hextets: [UInt16]

    init?(_ text: String) {
        var address = in6_addr()
        guard inet_pton(AF_INET6, text, &address) == 1 else { return nil }
        let bytes = withUnsafeBytes(of: address) { Array($0) }
        hextets = stride(from: 0, to: 16, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
    }

    /// The RFC 5952 form Python prints: lower-case hex, the first longest run of two or more zero groups as "::".
    var compressed: String {
        var best = (start: -1, length: 0)
        var run = (start: -1, length: 0)
        for (index, hextet) in hextets.enumerated() {
            if hextet == 0 {
                run = run.start < 0 ? (index, 1) : (run.start, run.length + 1)
                if run.length > best.length { best = run }
            } else {
                run = (-1, 0)
            }
        }
        let groups = hextets.map { String($0, radix: 16) }
        guard best.length > 1 else { return groups.joined(separator: ":") }
        let head = groups[..<best.start].joined(separator: ":")
        let tail = groups[(best.start + best.length)...].joined(separator: ":")
        return head + "::" + tail
    }

    /// Python 3.13's `is_global`; IPv4-mapped (`::ffff:0:0/96`) and multicast (`ff00::/8`) addresses are left out.
    var isGlobal: Bool {
        let notGlobal: [([UInt16], Int)] = [
            ([0, 0, 0, 0, 0, 0, 0, 1], 128), ([0, 0, 0, 0, 0, 0, 0, 0], 128), ([0, 0, 0, 0, 0, 0xFFFF, 0, 0], 96),
            ([0x64, 0xFF9B, 1], 48), ([0x100, 0, 0, 0], 64), ([0x2001, 0], 23), ([0x2001, 0xDB8], 32),
            ([0x2002], 16), ([0x3FFF], 20), ([0xFC00], 7), ([0xFE80], 10), ([0xFF00], 8)
        ]
        let exceptions: [([UInt16], Int)] = [
            ([0x2001, 1, 0, 0, 0, 0, 0, 1], 128), ([0x2001, 1, 0, 0, 0, 0, 0, 2], 128), ([0x2001, 3], 32),
            ([0x2001, 4, 0x112], 48), ([0x2001, 0x20], 28), ([0x2001, 0x30], 28)
        ]
        // A mapped IPv4 address is judged by its IPv4 part on the server; the app does not bind to one.
        if contains(([0, 0, 0, 0, 0, 0xFFFF, 0, 0], 96)) { return false }
        if exceptions.contains(where: contains) { return true }
        return !notGlobal.contains(where: contains)
    }

    private func contains(_ network: ([UInt16], Int)) -> Bool {
        var remaining = network.1
        for index in 0..<8 where remaining > 0 {
            let prefix = network.0.count > index ? network.0[index] : 0
            let bits = min(16, remaining)
            let mask: UInt16 = ~UInt16(0) << UInt16(16 - bits)
            if hextets[index] & mask != prefix & mask { return false }
            remaining -= bits
        }
        return true
    }
}
