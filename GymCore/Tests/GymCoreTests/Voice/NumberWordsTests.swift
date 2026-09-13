import Testing
@testable import GymCore

@Suite("NumberWords")
struct NumberWordsTests {
    private func value(_ text: String) -> Double? {
        NumberWords.parse(Tokenizer.words(text), at: 0)?.value
    }

    @Test("units and teens")
    func units() {
        #expect(value("eight") == 8)
        #expect(value("eleven") == 11)
        #expect(value("nineteen") == 19)
    }

    @Test("tens and compounds")
    func tens() {
        #expect(value("twenty") == 20)
        #expect(value("twenty five") == 25)
        #expect(value("ninety") == 90)
    }

    @Test("a hundred and compound hundreds")
    func hundreds() {
        #expect(value("a hundred") == 100)
        #expect(value("one hundred and two and a half") == 102.5)
        #expect(value("hundred and two and a half") == 102.5)
    }

    @Test("one twenty reads as a hundred-group")
    func digitTensCompound() {
        #expect(value("one twenty") == 120)
    }

    @Test("digit-by-digit with a decimal point")
    func digitString() {
        #expect(value("one oh two point five") == 102.5)
    }

    @Test("fractions: and a half / and a quarter")
    func fractions() {
        #expect(value("two and a half") == 2.5)
        #expect(value("eight and a half") == 8.5)
        #expect(value("a quarter") == 0.25)
        #expect(value("a half") == 0.5)
    }

    @Test("plain digit strings parse directly")
    func digits() {
        #expect(value("8") == 8)
        #expect(value("225") == 225)
    }

    @Test("non-numeric words return nil")
    func nonNumeric() {
        #expect(value("bench") == nil)
        #expect(value("blah") == nil)
    }

    @Test("parseSingleWord never compounds")
    func singleWord() {
        #expect(NumberWords.parseSingleWord("twenty") == 20)
        #expect(NumberWords.parseSingleWord("eight") == 8)
        #expect(NumberWords.parseSingleWord("bench") == nil)
    }
}
