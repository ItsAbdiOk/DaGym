import Foundation
import Testing
@testable import GymCore

@Suite("CSVParser")
struct CSVParserTests {
    @Test("splits plain rows")
    func plainRows() {
        let rows = CSVParser.parse("a,b,c\n1,2,3\n")
        #expect(rows == [["a", "b", "c"], ["1", "2", "3"]])
    }

    @Test("handles quoted fields with embedded commas and newlines")
    func quotedFields() {
        let text = "name,note\nBench,\"felt good, strong\"\nRow,\"line one\nline two\"\n"
        let rows = CSVParser.parse(text)
        #expect(rows[1] == ["Bench", "felt good, strong"])
        #expect(rows[2] == ["Row", "line one\nline two"])
    }

    @Test("doubled quote escapes a literal quote")
    func escapedQuote() {
        let rows = CSVParser.parse("note\n\"she said \"\"hi\"\"\"\n")
        #expect(rows[1] == ["she said \"hi\""])
    }

    @Test("handles CRLF line endings")
    func crlf() {
        let rows = CSVParser.parse("a,b\r\n1,2\r\n")
        #expect(rows == [["a", "b"], ["1", "2"]])
    }

    @Test("no trailing empty row for a file ending in a newline")
    func noTrailingBlankRow() {
        let rows = CSVParser.parse("a,b\n1,2\n")
        #expect(rows.count == 2)
    }
}
