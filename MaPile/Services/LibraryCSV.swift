import Foundation

/// Import (Goodreads, Babelio, tableur) et export de la bibliothèque au format CSV.
enum LibraryCSV {

    // MARK: - Lecture d'un CSV

    /// Découpe un CSV (virgules ou points-virgules, champs entre guillemets) en lignes de cellules.
    static func parse(_ text: String) -> [[String]] {
        // En Swift, « \r\n » forme un seul caractère : on le traite comme une fin de ligne.
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" && $0 != "\r\n" }
        let separator: Character = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil
        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" {
                inQuotes = true
            } else if char == separator {
                row.append(field)
                field = ""
            } else if char == "\n" || char == "\r" || char == "\r\n" {
                if char == "\r", let next = iterator.next(), next != "\n" { pending = next }
                row.append(field)
                field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(char)
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }

    struct ImportedBook: Identifiable, Hashable {
        let id = UUID()
        var title: String
        var author: String
        var isbn: String?
        var status: ReadingStatus
        var rating: Int
        var dateRead: Date?
        var dateAdded: Date?
        var pages: Int
        var review: String
        var seriesName: String
        var seriesIndex: Int
    }

    private static func normalizeHeader(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Trouve la colonne correspondant à l'un des noms possibles (Goodreads, Babelio, MaPile…).
    private static func column(_ headers: [String], _ names: [String]) -> Int? {
        let wanted = names.map(normalizeHeader)
        return headers.firstIndex { wanted.contains(normalizeHeader($0)) }
    }

    private static func parseDate(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        for format in ["yyyy/MM/dd", "yyyy-MM-dd", "dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func cleanISBN(_ raw: String) -> String? {
        let digits = raw.uppercased().filter { $0.isNumber || $0 == "X" }
        return (digits.count == 13 || digits.count == 10) ? digits : nil
    }

    private static func status(from raw: String, hasReadDate: Bool) -> ReadingStatus {
        let value = normalizeHeader(raw)
        if ["read", "lu", "lus", "dejalu", "termine"].contains(value) { return .read }
        if ["currentlyreading", "encours", "enlecture"].contains(value) { return .reading }
        if ["toread", "pal", "alire", "pileàlire", "pilealire", "envie"].contains(value) { return .toRead }
        return hasReadDate ? .read : .toRead
    }

    /// Transforme un fichier CSV en livres (formats Goodreads, Babelio ou un tableur simple « Titre / Auteur »).
    static func importBooks(from text: String) -> [ImportedBook] {
        let rows = parse(text)
        guard let headers = rows.first, rows.count > 1 else { return [] }
        guard let titleCol = column(headers, ["Title", "Titre", "Titre du livre", "Livre"]) else { return [] }
        let authorCol = column(headers, ["Author", "Auteur", "Auteurs", "Author l-f", "Auteur(s)"])
        let isbn13Col = column(headers, ["ISBN13", "ISBN 13", "EAN"])
        let isbnCol = column(headers, ["ISBN", "ISBN10"])
        let ratingCol = column(headers, ["My Rating", "Ma note", "Note", "Rating"])
        let shelfCol = column(headers, ["Exclusive Shelf", "Statut", "Etagere", "Étagère", "Status"])
        let readCol = column(headers, ["Date Read", "Date de lecture", "Lu le", "Date lecture", "Date de fin"])
        let addedCol = column(headers, ["Date Added", "Date d'ajout", "Ajouté le"])
        let pagesCol = column(headers, ["Number of Pages", "Pages", "Nombre de pages", "Nb pages"])
        let reviewCol = column(headers, ["My Review", "Mon avis", "Critique", "Avis", "Review"])
        let seriesCol = column(headers, ["Série", "Serie", "Series"])
        let tomeCol = column(headers, ["Tome", "Volume"])

        func cell(_ row: [String], _ index: Int?) -> String {
            guard let index, index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var result: [ImportedBook] = []
        for row in rows.dropFirst() {
            let title = cell(row, titleCol)
            guard !title.isEmpty else { continue }
            let dateRead = parseDate(cell(row, readCol))
            let ratingValue = Double(cell(row, ratingCol).replacingOccurrences(of: ",", with: ".")) ?? 0
            let isbn = cleanISBN(cell(row, isbn13Col)) ?? cleanISBN(cell(row, isbnCol))
            result.append(ImportedBook(
                title: title,
                author: cell(row, authorCol),
                isbn: isbn,
                status: status(from: cell(row, shelfCol), hasReadDate: dateRead != nil),
                rating: min(max(Int(ratingValue.rounded()), 0), 5),
                dateRead: dateRead,
                dateAdded: parseDate(cell(row, addedCol)),
                pages: Int(cell(row, pagesCol)) ?? 0,
                review: cell(row, reviewCol),
                seriesName: cell(row, seriesCol),
                seriesIndex: Int(cell(row, tomeCol)) ?? 0))
        }
        return result
    }

    // MARK: - Export

    private static func escape(_ value: String) -> String {
        if value.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "," }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    /// Fichier CSV (séparateur « ; », lisible par Excel, Numbers, Google Sheets) de toute la bibliothèque.
    static func exportFile(books: [Book]) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        var lines = ["Titre;Auteur;ISBN;Statut;Ma note;Date de lecture;Date d'ajout;Pages;Genres;Série;Tome;Mon avis"]
        for book in books {
            let status: String
            switch book.status {
            case .read: status = "Lu"
            case .reading: status = "En cours"
            case .toRead: status = "PAL"
            }
            let fields: [String] = [
                book.title, book.authors, book.isbn ?? "", status,
                book.myRating > 0 ? String(book.myRating) : "",
                book.dateFinished.map { dateFormatter.string(from: $0) } ?? "",
                dateFormatter.string(from: book.dateAdded),
                book.pageCount > 0 ? String(book.pageCount) : "",
                book.categories, book.seriesName,
                book.seriesIndex > 0 ? String(book.seriesIndex) : "",
                book.myReview,
            ]
            lines.append(fields.map(escape).joined(separator: ";"))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MaPile-bibliotheque.csv")
        // BOM UTF-8 pour qu'Excel affiche correctement les accents.
        let content = "\u{FEFF}" + lines.joined(separator: "\n")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
