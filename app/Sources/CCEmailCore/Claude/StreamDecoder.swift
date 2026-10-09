import Foundation

/// Splits a byte stream into newline-delimited JSON events. Reads from a pipe can end
/// mid-line or mid-character, so incomplete bytes are held until the next chunk.
public struct StreamDecoder: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func feed(_ chunk: Data) -> [StreamEvent] {
        buffer.append(chunk)
        var events: [StreamEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let event = StreamEvent.decode(line: String(decoding: lineData, as: UTF8.self)) {
                events.append(event)
            }
        }
        return events
    }

    /// Decodes whatever is left when the stream closes without a final newline.
    public mutating func finish() -> [StreamEvent] {
        defer { buffer.removeAll() }
        guard let event = StreamEvent.decode(line: String(decoding: buffer, as: UTF8.self)) else { return [] }
        return [event]
    }
}
