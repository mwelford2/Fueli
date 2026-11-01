import Foundation

struct RetailBarcode: Equatable {
    enum Format { case gtin8, upca, ean13, upce }
    let canonical: String

    init(_ payload: String, format: Format? = nil) throws {
        guard payload.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw BarcodeLookupError.requestFailed("Barcode must contain digits only.") }
        var code = payload
        if format == .upce {
            guard code.count == 8 else { throw BarcodeLookupError.requestFailed("UPC-E requires eight digits.") }
            let d = Array(code).map(String.init)
            guard d[0] == "0" || d[0] == "1" else { throw BarcodeLookupError.requestFailed("Unsupported UPC-E number system.") }
            switch d[6] {
            case "0", "1", "2": code = d[0] + d[1] + d[2] + d[6] + "0000" + d[3] + d[4] + d[5] + d[7]
            case "3": code = d[0] + d[1] + d[2] + d[3] + "00000" + d[4] + d[5] + d[7]
            case "4": code = d[0] + d[1] + d[2] + d[3] + d[4] + "00000" + d[5] + d[7]
            default: code = d[0] + d[1] + d[2] + d[3] + d[4] + d[5] + "0000" + d[6] + d[7]
            }
        }
        guard [8, 12, 13].contains(code.count), Self.validChecksum(code) else {
            throw BarcodeLookupError.requestFailed("Invalid retail barcode or checksum. Try scanning again.")
        }
        canonical = code.count == 12 ? "0" + code : code
    }

    static func validChecksum(_ value: String) -> Bool {
        let digits = value.compactMap(\.wholeNumberValue)
        guard digits.count == value.count, let check = digits.last else { return false }
        let sum = digits.dropLast().reversed().enumerated().reduce(0) { $0 + $1.element * ($1.offset.isMultiple(of: 2) ? 3 : 1) }
        return (10 - sum % 10) % 10 == check
    }
}
