import Foundation

/// Découpe le texte qui arrive en streaming en phrases prêtes à être dites.
/// Le modèle renvoie le texte cumulé (chaque fragment contient tout le début) :
/// on retient où l'on s'est arrêté et on ne renvoie que les phrases nouvelles et complètes.
struct SentenceChunker {
    /// Au-delà, on coupe à la dernière virgule pour ne pas faire attendre la voix.
    static let maxSentenceLength = 220

    private var emitted = 0
    private var lastText = ""

    mutating func feed(_ cumulative: String) -> [String] {
        lastText = cumulative
        let characters = Array(cumulative)
        guard emitted <= characters.count else {
            emitted = 0
            return []
        }

        var sentences: [String] = []
        var start = emitted
        var index = emitted
        while index < characters.count {
            let character = characters[index]
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            let endsSentence = (".!?…".contains(character) && next?.isWhitespace == true) || character == "\n"
            let tooLong = index - start >= Self.maxSentenceLength && character == "," && next?.isWhitespace == true
            if endsSentence || tooLong {
                if let sentence = Self.clean(String(characters[start...index])) {
                    sentences.append(sentence)
                }
                start = index + 1
            }
            index += 1
        }
        emitted = start
        return sentences
    }

    /// La fin du texte, une fois la génération terminée.
    mutating func flush() -> [String] {
        let characters = Array(lastText)
        defer { emitted = characters.count }
        guard emitted < characters.count, let rest = Self.clean(String(characters[emitted...])) else { return [] }
        return [rest]
    }

    /// Enlève la mise en forme Markdown, qu'une voix lirait telle quelle.
    static func clean(_ text: String) -> String? {
        let stripped = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return stripped.contains(where: \.isLetter) || stripped.contains(where: \.isNumber) ? stripped : nil
    }
}
