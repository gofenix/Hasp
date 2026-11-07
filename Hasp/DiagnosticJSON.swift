import Foundation

/// Serialize on the producing worker so untyped Foundation values never
/// cross actor boundaries. The existing diagnostic JSON format is unchanged.
enum DiagnosticJSON {
    static func encode(_ build: () -> [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: build(), options: [.prettyPrinted, .sortedKeys]))
            ?? Data(#"{"failure":"Diagnostic encoding failed"}"#.utf8)
    }

    static func decode(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            ?? ["failure": "Diagnostic decoding failed"]
    }
}
