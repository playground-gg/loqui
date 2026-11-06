import Foundation

/// Testo inserito durante la sessione: serve per annulla, pulizia e, in fase 2, modifica vocale.
public struct DictationBuffer: Sendable, Equatable {
    public private(set) var insertions: [String] = []

    public init() {}

    public var text: String { insertions.joined() }
    public var canUndo: Bool { !insertions.isEmpty }

    /// Testo da inserire davvero, con lo spazio se la dettatura si attacca a una parola.
    public static func textToInsert(_ text: String, after context: String?) -> String {
        guard let last = context?.last, !last.isWhitespace, !last.isNewline else { return text }
        if let first = text.first, first.isPunctuation { return text }
        // Dopo un'apertura di parentesi o virgolette lo spazio sarebbe un errore.
        if "([{«“‘\"'".contains(last) { return text }
        return " " + text
    }

    public mutating func record(_ inserted: String) {
        insertions.append(inserted)
    }

    /// Quanti caratteri cancellare per annullare l'ultimo inserimento. Nil se non c'è nulla.
    public mutating func popLast() -> Int? {
        insertions.popLast()?.count
    }

    public mutating func reset() {
        insertions.removeAll()
    }
}
