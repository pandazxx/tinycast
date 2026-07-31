// Harness for the `define <word>` prefix parser. Compiles the real source:
//
//   swiftc -swift-version 6 Tinycast/Core/Dictionary/DictionaryQuery.swift \
//     Tools/dictionary-test.swift -o /tmp/dictionary-test && /tmp/dictionary-test
//
// DictionaryQuery must stay Foundation-only for this to keep working — the CoreServices lookup
// lives in DictionaryLookup.swift precisely so it stays out of the way here.

import Foundation

@main
struct DictionaryTest {
    static func main() {
        var passed = 0
        var failed = 0

        func expect(_ query: String, _ want: String?, _ note: String) {
            let got = DictionaryQuery.term(in: query)
            if got == want {
                passed += 1
            } else {
                failed += 1
                let g = got.map { "\"\($0)\"" } ?? "nil"
                let w = want.map { "\"\($0)\"" } ?? "nil"
                print("FAIL  \(note): term(in: \"\(query)\") = \(g), want \(w)")
            }
        }

        // Recognised
        expect("define apple", "apple", "plain lookup")
        expect("define  apple", "apple", "extra space after keyword")
        expect("  define apple  ", "apple", "surrounding whitespace")
        expect("Define apple", "apple", "capitalised keyword")
        expect("DEFINE apple", "apple", "shouted keyword")
        expect("define apple pie", "apple pie", "multi-word term")
        expect("define a", "a", "single-letter term")
        expect("define café", "café", "non-ascii term")
        expect("define\tapple", "apple", "tab separator")

        // Not a lookup
        expect("define", nil, "keyword alone")
        expect("define ", nil, "keyword and a space")
        expect("   define   ", nil, "keyword and only whitespace")
        expect("defined", nil, "keyword is a prefix of a longer word")
        expect("defines apple", nil, "keyword pluralised")
        expect("redefine apple", nil, "keyword not at the start")
        expect("def apple", nil, "abbreviation is not the keyword")
        expect("", nil, "empty query")
        expect("   ", nil, "whitespace only")
        expect("apple define", nil, "keyword trailing")

        // The prefix must not swallow ordinary launcher searches for apps whose names start with it.
        expect("definition", nil, "a word that merely starts with the keyword")

        if failed == 0 {
            print("dictionary-test: all checks passed (\(passed) cases)")
        } else {
            print("dictionary-test: \(passed) passed, \(failed) failed")
            exit(1)
        }
    }
}
