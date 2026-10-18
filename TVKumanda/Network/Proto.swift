import Foundation

/// Just enough protobuf for the Android TV remote protocol: varints, length-delimited fields, flat parsing.
nonisolated enum Proto {
    enum Value: Sendable {
        case varint(UInt64)
        case bytes(Data)
    }

    static func varint(_ value: UInt64) -> Data {
        var value = value
        var out = Data()
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
        return out
    }

    /// int32 fields are sign-extended to 64 bits on the wire.
    static func field(_ number: Int, _ value: Int) -> Data {
        varint(UInt64(number << 3)) + varint(UInt64(bitPattern: Int64(value)))
    }

    static func field(_ number: Int, _ bytes: Data) -> Data {
        varint(UInt64(number << 3 | 2)) + varint(UInt64(bytes.count)) + bytes
    }

    static func field(_ number: Int, _ string: String) -> Data {
        field(number, Data(string.utf8))
    }

    /// Length-prefixed frame as used on both ports.
    static func frame(_ message: Data) -> Data {
        varint(UInt64(message.count)) + message
    }

    /// Splits complete frames off the front of `buffer`.
    static func takeFrames(from buffer: inout Data) -> [Data] {
        var frames: [Data] = []
        while true {
            var index = buffer.startIndex
            guard let length = readVarint(buffer, &index), buffer.endIndex - index >= Int(length) else { break }
            let end = index + Int(length)
            frames.append(Data(buffer[index..<end]))
            buffer.removeSubrange(buffer.startIndex..<end)
        }
        return frames
    }

    static func parse(_ data: Data) -> [(Int, Value)] {
        var fields: [(Int, Value)] = []
        var index = data.startIndex
        while index < data.endIndex {
            guard let key = readVarint(data, &index) else { break }
            let number = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let value = readVarint(data, &index) else { return fields }
                fields.append((number, .varint(value)))
            case 2:
                guard let length = readVarint(data, &index), data.endIndex - index >= Int(length) else { return fields }
                fields.append((number, .bytes(Data(data[index..<index + Int(length)]))))
                index += Int(length)
            case 5: index += 4
            case 1: index += 8
            default: return fields
            }
        }
        return fields
    }

    private static func readVarint(_ data: Data, _ index: inout Data.Index) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.endIndex, shift < 64 {
            let byte = data[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }
}

nonisolated extension Array where Element == (Int, Proto.Value) {
    func varint(_ number: Int) -> UInt64? {
        for (n, value) in self where n == number { if case let .varint(v) = value { return v } }
        return nil
    }

    func bytes(_ number: Int) -> Data? {
        for (n, value) in self where n == number { if case let .bytes(b) = value { return b } }
        return nil
    }

    func has(_ number: Int) -> Bool { contains { $0.0 == number } }
}
