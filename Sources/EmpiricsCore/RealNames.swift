import Foundation

/// A small CSV reader and writer (RFC 4180: commas, double quotes, quotes
/// doubled inside quoted fields, CRLF or LF line endings).
public enum CSV {
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                quoted = true
            } else if c == "," {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field)
                field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        return rows
    }

    public static func field(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : s
    }

    public static func line(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }
}

/// Real names for researchers and interviewees, from mapping files (CSV)
/// kept in the full-texts folder. The workspace only ever holds pseudonyms.
///
///     key,pseudonym,real_first_name,real_last_name
///     i-05a17400,John Smith,Jonathan,Realname
///
/// Rows are matched by key; a row without a key is matched by pseudonym.
/// A single `real_name` column may be used instead of first and last.
public enum RealNames {
    public struct Problem: Error, LocalizedError, Equatable {
        public var message: String
        public var errorDescription: String? { message }
    }

    /// Real names by person key.
    public static func read(_ text: String, people: [(key: String, pseudonym: String)]) throws -> [String: String] {
        let rows = CSV.parse(text)
        guard let header = rows.first else { return [:] }
        func column(_ names: [String]) -> Int? {
            header.firstIndex { h in
                let n = h.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "_")
                return names.contains(n)
            }
        }
        let keyCol = column(["key"])
        let pseudoCol = column(["pseudonym", "pseudonym_name", "name"])
        let firstCol = column(["real_first_name", "real_first", "first_name", "first"])
        let lastCol = column(["real_last_name", "real_last", "last_name", "last"])
        let fullCol = column(["real_name", "real"])
        guard keyCol != nil || pseudoCol != nil else {
            throw Problem(message: "The mapping file needs a “key” or a “pseudonym” column.")
        }
        guard fullCol != nil || firstCol != nil || lastCol != nil else {
            throw Problem(message: "The mapping file needs “real_first_name” and “real_last_name” columns (or a “real_name” column).")
        }
        let byPseudonym = Dictionary(people.map { (TurnDetector.normalise($0.pseudonym), $0.key) }, uniquingKeysWith: { a, _ in a })
        var result: [String: String] = [:]
        for row in rows.dropFirst() {
            func value(_ c: Int?) -> String {
                guard let c, c < row.count else { return "" }
                return row[c].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var key = value(keyCol)
            if key.isEmpty { key = byPseudonym[TurnDetector.normalise(value(pseudoCol))] ?? "" }
            guard !key.isEmpty else { continue }
            var name = value(fullCol)
            if name.isEmpty { name = [value(firstCol), value(lastCol)].filter { !$0.isEmpty }.joined(separator: " ") }
            if !name.isEmpty { result[key] = name }
        }
        return result
    }

    /// A mapping file to fill in: every person's key and pseudonym, with
    /// empty real-name columns.
    public static func template(people: [(key: String, pseudonym: String)]) -> String {
        var lines = [CSV.line(["key", "pseudonym", "real_first_name", "real_last_name"])]
        for p in people { lines.append(CSV.line([p.key, p.pseudonym, "", ""])) }
        return lines.joined(separator: "\n") + "\n"
    }
}
