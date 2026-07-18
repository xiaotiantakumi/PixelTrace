import Foundation

public enum FourCCFormatting {
    public static func string(from value: UInt32) -> String {
        var result = ""
        for shift in stride(from: 24, through: 0, by: -8) {
            let byte = UInt8((value >> shift) & 0xFF)
            if byte < 32 || byte > 126 {
                return String(format: "0x%08X", value)
            }
            result.append(Character(UnicodeScalar(byte)))
        }
        return result
    }
}
