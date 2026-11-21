import BrievieCore
import Foundation

// What the compare screen shows: the head of each letter's column and the compare rows.
extension DuplicateModel {
    /// "Mogelijk dubbel" screen's line under the description: "Lijkt op elkaar voor 92%".
    public var similarityLine: String? {
        pair.map { String(format: DocumentStrings.duplicateSimilarityFormat, $0.similarity) }
    }

    /// "Brief 1" and "Brief 2", in the server's order.
    public var letters: [Letter] {
        guard let pair else { return [] }
        return [pair.first, pair.second].enumerated().map { offset, summary in
            let number = offset + 1
            return Letter(
                id: summary.id,
                title: String(format: DocumentStrings.duplicateLetterFormat, number),
                scanned: String(format: DocumentStrings.duplicateScannedFormat, longDate(summary.createdAt)),
                pageLabel: String(format: DocumentStrings.duplicateFirstPageFormat, number),
                keepLabel: String(format: DocumentStrings.duplicateKeepLabelFormat, number)
            )
        }
    }

    /// Afzender, Soort, Datum, Bedrag, Factuurnummer, Kenmerk, Pagina's, Labels, Op naam van, Taken. Bedrag,
    /// Factuurnummer and Kenmerk only when they differ: the server gives their values only then. A field the server
    /// found different is marked. Taken only when both letters' details are loaded.
    public var rows: [CompareRow] {
        guard let pair else { return [] }
        let letters = (pair.first, pair.second)
        var rows = [
            factRow(.sender, DocumentStrings.duplicateSender, letters) { $0.sender.isEmpty ? nil : $0.sender },
            factRow(.documentType, DocumentStrings.duplicateKind, letters) { letter in
                letter.documentType.isEmpty ? nil : DocumentTypes.documentTypeLabel(letter.documentType)
            },
            factRow(.letterDate, DocumentStrings.duplicateDate, letters) { $0.letterDate?.display(locale: locale) }
        ]
        let onlyWhenDiffering: [(DuplicateField, String)] = [
            (.amount, DocumentStrings.duplicateAmount),
            (.invoiceNumber, DocumentStrings.duplicateInvoiceNumber),
            (.paymentReference, DocumentStrings.duplicateReference)
        ]
        for (field, title) in onlyWhenDiffering {
            guard let difference = difference(of: field) else { continue }
            rows.append(CompareRow(
                id: field.rawValue, title: title, first: display(difference.first, of: field),
                second: display(difference.second, of: field), mark: mark(of: field)
            ))
        }
        rows.append(factRow(.pageCount, DocumentStrings.duplicatePages, letters) { Self.pages($0.pageCount) })
        rows.append(listRow("labels", DocumentStrings.duplicateLabels, letters) { letter in
            labels.filter { letter.labelIDs.contains($0.id) }.map(\.name)
        })
        rows.append(listRow("addressees", DocumentStrings.duplicateAddressees, letters) { letter in
            persons.filter { letter.addresseeIDs.contains($0.id) }.map(\.displayName)
        })
        if let first = details[pair.first.id], let second = details[pair.second.id] {
            rows.append(CompareRow(
                id: "tasks", title: DocumentStrings.duplicateTasks, first: tasks(first), second: tasks(second),
                mark: nil
            ))
        }
        return rows
    }

    // MARK: - Private

    private func difference(of field: DuplicateField) -> DuplicateDifference? {
        pair?.differences.first { $0.field == field }
    }

    private func mark(of field: DuplicateField) -> Mark? {
        difference(of: field).map { $0.isUncertain ? .mayDiffer : .differs }
    }

    /// A fact as the server compared it when it differs (so the values match the mark), else each letter's own.
    private func factRow(
        _ field: DuplicateField, _ title: String, _ letters: (DocumentSummary, DocumentSummary),
        value: (DocumentSummary) -> String?
    ) -> CompareRow {
        let empty = field == .sender ? DocumentStrings.unknownSender : DocumentStrings.duplicateNone
        if let difference = difference(of: field) {
            return CompareRow(
                id: field.rawValue, title: title, first: display(difference.first, of: field),
                second: display(difference.second, of: field), mark: mark(of: field)
            )
        }
        return CompareRow(
            id: field.rawValue, title: title, first: value(letters.0) ?? empty, second: value(letters.1) ?? empty,
            mark: nil
        )
    }

    private func listRow(
        _ id: String, _ title: String, _ letters: (DocumentSummary, DocumentSummary),
        names: (DocumentSummary) -> [String]
    ) -> CompareRow {
        func joined(_ names: [String]) -> String {
            names.isEmpty ? DocumentStrings.duplicateNone : names.joined(separator: ", ")
        }
        return CompareRow(
            id: id, title: title, first: joined(names(letters.0)), second: joined(names(letters.1)), mark: nil
        )
    }

    /// The server's text of a differing value in the user's words: a date, an amount in euros, a kind, pages.
    private func display(_ value: String, of field: DuplicateField) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return DocumentStrings.duplicateNone }
        switch field {
        case .letterDate:
            return CalendarDate(iso: value)?.display(locale: locale) ?? value
        case .amount:
            guard let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return value }
            return amount.formatted(.currency(code: "EUR").locale(locale))
        case .documentType:
            return DocumentTypes.documentTypeLabel(value)
        case .pageCount:
            return Int(value).map(Self.pages) ?? value
        case .sender, .invoiceNumber, .paymentReference, .unknown:
            return value
        }
    }

    private func tasks(_ detail: DocumentDetail) -> String {
        guard !detail.tasks.isEmpty else { return DocumentStrings.duplicateNone }
        return detail.tasks.map { task in
            let name = task.description.isEmpty ? DocumentTypes.taskTypeLabel(task.type) : task.description
            return task.isDone ? String(format: DocumentStrings.duplicateTaskDoneFormat, name) : name
        }
        .joined(separator: "\n")
    }

    /// With the time: two scans of one letter are usually made on the same day.
    private func longDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: locale))
    }

    private static func pages(_ count: Int) -> String {
        count == 1 ? DocumentStrings.pagesOne : String(format: DocumentStrings.pagesManyFormat, count)
    }
}
