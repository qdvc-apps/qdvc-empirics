import AppKit
import EmpiricsCore
import SwiftUI

// Attribute Sheet questions as columns in the tables of the items attribute sheets apply
// to (empirical files, interviewees, open codes, axial codes). Right-click a
// column heading to show or hide them: the tables use SwiftUI's column
// customization, in which only the question columns take part. Which
// questions are shown is saved in the workspace (project.yml,
// `table_columns`), so everyone sharing it sees the same columns. A cell
// shows the answer; when researchers' answers differ, each answer with the
// initials of those who gave it.

/// An attribute sheet question that can be shown as a table column.
struct QuestionColumn: Identifiable, Hashable {
    var attributeSheet: String
    var question: String
    /// The column heading (and its name in the headings' menu).
    var title: String

    var id: String { question }
}

extension AppModel {
    /// The questions a table can show: those of the attribute sheets that apply
    /// to its items, attribute sheets by title, questions in attribute sheet order.
    func questionColumns(for target: AttributeSheetTarget) -> [QuestionColumn] {
        let books = project.attributeSheets.values.filter { $0.appliesTo.contains(target) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        var labelCount: [String: Int] = [:]
        for cb in books {
            for q in cb.questions { labelCount[label(q), default: 0] += 1 }
        }
        var seen = Set<String>()
        var result: [QuestionColumn] = []
        for cb in books {
            for q in cb.questions where !seen.contains(q.key) {
                seen.insert(q.key)
                let l = label(q)
                // The same label in two attribute sheets: say which is which.
                let title = (labelCount[l] ?? 0) > 1 ? "\(cb.title): \(l)" : l
                result.append(QuestionColumn(attributeSheet: cb.key, question: q.key, title: title))
            }
        }
        return result
    }

    private func label(_ q: AttributeSheetQuestion) -> String {
        let l = q.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return l.isEmpty ? "Question" : l
    }

    /// The question columns a table shows.
    func shownQuestionColumns(for target: AttributeSheetTarget) -> [QuestionColumn] {
        let shown = Set(project.settings.tableColumns[target] ?? [])
        return questionColumns(for: target).filter { shown.contains($0.question) }
    }

    /// Saves which questions a table shows (one step of Edit › Undo).
    func setTableColumns(_ questions: [String], for target: AttributeSheetTarget) {
        let old = project.settings.tableColumns[target] ?? []
        guard questions != old else { return }
        perform(questions.count >= old.count ? "Show Column" : "Hide Column") { p in
            p.settings.tableColumns[target] = questions.isEmpty ? nil : questions
        }
    }

    /// What a question column shows for an item: the answer when everyone
    /// who answered agrees, otherwise each answer with the initials of those
    /// who gave it ("Yes (AB) · No (CD)"); and a tooltip with everyone's
    /// answer by name.
    func answerSummary(_ column: QuestionColumn, target: String) -> (text: String, help: String, differs: Bool) {
        let given = project.answers(attributeSheet: column.attributeSheet, question: column.question, target: target)
        guard !given.isEmpty else { return ("", "", false) }
        var groups: [(text: String, who: [String])] = []
        for g in given {
            let text = g.answer.summary
            if let i = groups.firstIndex(where: { $0.text == text }) {
                groups[i].who.append(g.researcher)
            } else {
                groups.append((text, [g.researcher]))
            }
        }
        let help = given.map { g in
            g.researcher.isEmpty ? g.answer.summary : "\(personName(g.researcher) ?? "Someone"): \(g.answer.summary)"
        }.joined(separator: "\n")
        if groups.count == 1 { return (groups[0].text, help, false) }
        let text = groups.map { g in
            "\(g.text) (\(g.who.map { initials($0) }.joined(separator: ", ")))"
        }.joined(separator: " · ")
        return (text, help, true)
    }

    /// A researcher's initials, from the name shown (pseudonym or real).
    func initials(_ person: String) -> String {
        guard !person.isEmpty, let name = personName(person) else { return "?" }
        let letters = name.split(separator: " ").compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// The table's column customization as the workspace says: each
    /// question column visible if shown, hidden otherwise, with the rest
    /// (widths, order) kept in `state` for the session. Showing or hiding a
    /// question from the headings' menu saves it to the workspace.
    func questionColumnCustomization<Row: Identifiable>(
        _ state: Binding<TableColumnCustomization<Row>>, columns: [QuestionColumn], target: AttributeSheetTarget
    ) -> Binding<TableColumnCustomization<Row>> {
        Binding(
            get: {
                var c = state.wrappedValue
                let shown = Set(self.project.settings.tableColumns[target] ?? [])
                for column in columns {
                    c[visibility: column.id] = shown.contains(column.id) ? .visible : .hidden
                }
                return c
            },
            set: { new in
                state.wrappedValue = new
                let shown = columns.filter { new[visibility: $0.id] == .visible }.map(\.question)
                self.setTableColumns(shown, for: target)
            }
        )
    }
}

/// The texts of the shown question columns, by question and item, for
/// sorting by them. A reference, refreshed each time the table is drawn,
/// so a sort chosen earlier still sorts by the current answers.
final class AnswerTexts: @unchecked Sendable {
    var values: [String: [String: String]] = [:]

    @MainActor
    func update(_ model: AppModel, columns: [QuestionColumn], targets: [String]) {
        var v: [String: [String: String]] = [:]
        for c in columns {
            var byTarget: [String: String] = [:]
            for t in targets { byTarget[t] = model.answerSummary(c, target: t).text }
            v[c.question] = byTarget
        }
        values = v
    }
}

/// Orders items (by key) by their text in a question column, unanswered
/// last. Equal for the same question and order whatever the texts, so the
/// table recognises its column as sorted.
struct AnswerOrder: SortComparator {
    var question: String
    var texts: AnswerTexts
    var order: SortOrder = .forward

    func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = texts.values[question]?[lhs] ?? ""
        let b = texts.values[question]?[rhs] ?? ""
        if a.isEmpty != b.isEmpty { return a.isEmpty ? .orderedDescending : .orderedAscending }
        let result = a.localizedStandardCompare(b)
        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    static func == (lhs: AnswerOrder, rhs: AnswerOrder) -> Bool {
        lhs.question == rhs.question && lhs.order == rhs.order
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(question)
        hasher.combine(order == .forward)
    }
}

/// A question column's cell: the answer (or answers, if they differ, in
/// orange); everyone's answer by name in the tooltip.
struct AnswerCell: View {
    let model: AppModel
    var column: QuestionColumn
    var target: String

    var body: some View {
        let s = model.answerSummary(column, target: target)
        Text(s.text)
            .lineLimit(1)
            .foregroundStyle(s.differs ? Color.orange : Color.primary)
            .help(s.help)
    }
}
