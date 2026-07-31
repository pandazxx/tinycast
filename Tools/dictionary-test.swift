// Harness for the dictionary prefix parser and the definition parser. Compiles the real sources:
//
//   swiftc -swift-version 6 Tinycast/Core/Dictionary/DictionaryQuery.swift \
//     Tinycast/Core/Dictionary/DefinitionParser.swift Tools/dictionary-test.swift \
//     -o /tmp/dictionary-test && /tmp/dictionary-test
//
// Both must stay Foundation-only for this to keep working — the CoreServices lookup lives in
// DictionaryLookup.swift precisely so it stays out of the way here.
//
// The definition fixtures below are REAL `DCSCopyTextDefinition` output, captured on macOS 26.
// They are the only source of truth for a format Apple does not document, so treat them as
// recordings: extend them, don't edit them to make a test pass.

import Foundation

@main
struct DictionaryTest {
    static func main() {
        var passed = 0
        var failed = 0

        func check(_ note: String, _ condition: Bool) {
            if condition {
                passed += 1
            } else {
                failed += 1
                print("FAIL  \(note)")
            }
        }

        func expectTerm(_ query: String, _ want: String?, _ note: String) {
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

        // MARK: - Prefix parsing

        expectTerm("define apple", "apple", "plain lookup")
        expectTerm("define  apple", "apple", "extra space after keyword")
        expectTerm("  define apple  ", "apple", "surrounding whitespace")
        expectTerm("Define apple", "apple", "capitalised keyword")
        expectTerm("DEFINE apple", "apple", "shouted keyword")
        expectTerm("define apple pie", "apple pie", "multi-word term")
        expectTerm("define a", "a", "single-letter term")
        expectTerm("define caf\u{e9}", "caf\u{e9}", "non-ascii term")
        expectTerm("define\tapple", "apple", "tab separator")

        expectTerm("define", nil, "keyword alone")
        expectTerm("define ", nil, "keyword and a space")
        expectTerm("   define   ", nil, "keyword and only whitespace")
        expectTerm("defined", nil, "keyword is a prefix of a longer word")
        expectTerm("defines apple", nil, "keyword pluralised")
        expectTerm("redefine apple", nil, "keyword not at the start")
        expectTerm("def apple", nil, "abbreviation is not the keyword")
        expectTerm("", nil, "empty query")
        expectTerm("   ", nil, "whitespace only")
        expectTerm("apple define", nil, "keyword trailing")
        expectTerm("definition", nil, "a word that merely starts with the keyword")

        // MARK: - Definition parsing
        //
        // Real DCSCopyTextDefinition output. One line, no newlines, no documented grammar.

        // three parts of speech, no numbered senses, leading variant forms
        let hello = "hello hel·lo | həˈlō, heˈlō | (hallo) (mainly British English hullo) exclamation used as a greeting or to begin a phone conversation: hello there, Katie!. • British English used to express surprise: hello, what's all this then?. • used as a cry to attract someone's attention: “Hello below!” he cried. • expressing sarcasm or anger: Hello! Did you even get what the play was about?. noun (plural hellos) an utterance of “hello”; a greeting: she was getting polite nods and hellos from people. verb (helloes, helloing, helloed) [no object] say or shout “hello”; greet someone: I pressed the phone button and helloed. ORIGIN early 19th century: variant of earlier hollo; related to holla."
        // EXCERPT of the real 20 KB entry, cut at sense boundaries: numbered senses across two parts of speech, plus every trailer marker
        let run = "run | rən | verb (runs) (, running | ˈrəniNG |) (past; ran | ran |) (past participle; run | rən |) 1 [no object] move at a speed faster than a walk, never having both or all the feet on the ground at the same time: the dog ran across the road | she ran the last few yards, breathing heavily | he hasn't paid for his drinks—run and catch him. • run as a sport or for exercise: I run every morning. • (of an athlete or a racehorse) compete in a race: she ran in the 200 meters | [with object] : Dave has run 42 marathons. • [with object] enter (a racehorse) for a race. • move about in a hurried and hectic way: I've spent the whole day running around after the kids. • Cricket (of a batter) run from one wicket to the other in scoring or attempting to score a run. • Baseball (of a batter or base runner) attempt to advance to the next base. • [with object] West Indian English chase (someone) away: ah went tuh eat the mangoes but the people run mih. • (of hounds) chase or hunt their quarry: the hounds are running. • (of a boat) sail directly before the wind, especially in bad weather: we slanted across to the far bank and ran before the wind. • (of a migratory fish) go upriver from the sea in order to spawn. noun 1 an act or spell of running: I usually go for a run in the morning | a cross-country run. • a running pace: Bobby set off at a run. • an annual mass migration of fish up a river to spawn, or their return migration afterward: the annual salmon runs. PHRASES come running be eager to do what someone wants: he  ... ORIGIN Old English rinnan, irnan (verb), of Germanic origin, probably"
        // numbered senses, PHRASES trailer, parentheticals that must survive
        let apple = "apple ap·ple | ˈap(ə)l | noun 1 the round fruit of a tree of the rose family, which typically has thin red or green skin and crisp flesh. Many varieties have been developed as dessert or cooking fruit or for making cider. • an unrelated fruit that resembles an apple in some way. See also custard apple,, thorn apple 2 (also apple tree) the tree which bears apples. Genus Malus, family Rosaceae: numerous hybrids and cultivars 3 (the Apple) short for Big Apple PHRASES the apple never falls far from the tree proverb family characteristics are usually inherited: he's a fool, Mary, as his father was—the apple never falls far from the tree. the apple of one's eye | T͟Hē ˌap(ə)l əv ˌwənz ˈī | a person of whom one is extremely fond and proud: a daughter who had ceased to be the apple of her father's eye. [originally denoting the pupil of the eye, considered to be a globular solid body, extended as a symbol of something cherished]apples and oranges (also apples to oranges) used with reference to two things that are fundamentally different and therefore not suited to comparison: comparing them is apples and oranges but they were both outstanding leaders with vision | it's like comparing apples and oranges | an apples and oranges comparison. apples to apples [often with negative] North American English used with reference to a comparison regarded as valid because it concerns two things that are fundamentally the same: there is no apples-to-apples comparison when comparing a foreign currency to USD | you want to compare us to Australia or Great Britain, like it’s apples to apples. upset the applecart spoil a plan or disturb the status quo. ORIGIN Old English æppel, of Germanic origin; related to Dutch appel and German Apfel."
        // one part of speech, one sense, no numbering
        let serendipity = "serendipity ser·en·dip·i·ty | ˌserənˈdipədē | noun the occurrence and development of events by chance in a happy or beneficial way: a fortunate stroke of serendipity | a series of small serendipities. ORIGIN 1754: coined by Horace Walpole, suggested by The Three Princes of Serendip, the title of a fairy tale in which the heroes ‘were always making discoveries, by accidents and sagacity, of things they were not in quest of’."
        // no part of speech at all, no syllabification, numbers in the prose
        let new_york = "New York | ˌn(y)o͞o ˈyôrk, no͞oːˈyôːrk | 1 (also New York State) a state in the northeastern US; population 19,490,297 (est. 2008); capital, Albany. It stretches from the Canadian border and Lake Ontario in the northwest to the Atlantic Ocean in the east. Originally settled by the Dutch, it was surrendered to the British in 1664 and became one of the original thirteen states of the Union, ratifying the US Constitution in 1788. 2 (also New York City) a major city and port in southeastern New York, situated on the Atlantic coast at the mouth of the Hudson River; population 8,363,710 (est. 2008). It is situated mainly on islands, linked by bridges, and consists of five boroughs: Manhattan, Brooklyn, the Bronx, Queens, and Staten Island. Manhattan is the economic and cultural heart of the city, containing the stock exchange on Wall Street and the headquarters of the United Nations. Former name (until 1664) New Amsterdam"
        // one sense with a sub-sense bullet, no trailers
        let quickly = "quickly quick·ly | ˈkwiklē | adverb at a fast speed; rapidly: Reg's illness progressed frighteningly quickly. • with little or no delay; promptly: we moved quickly to deal with our auditor's questions."

        // part-of-speech words used as ordinary prose mid-sense, plus a two-word part of speech
        let her = "her | hər, (h)ər | pronoun [third person singular] 1 used as the object of a verb or preposition to refer to a female person or animal previously mentioned or easily identified. Compare with she: she knew I hated her | I told Hannah I would wait for her. • referring to a ship, country, or other inanimate thing regarded as female: the crew tried to sail her through a narrow gap. • often used in place of “she” after the verb “to be” and after “than” or “as” to refer to a female person or animal: it must be her | he was younger than her. 2 archaic, or dialect herself: peevishly she flung her on her face. possessive determiner 1 belonging to or associated with a female person or animal previously mentioned or easily identified: Patricia loved her job | how the mother crane treats her babies. • belonging to or associated with a ship, country, or other inanimate thing regarded as female: at her launch, she was the ultimate in luxury transatlantic travel. 2 (Her) used in titles: Her Royal Highness. USAGE On whether her or she is the correct pronoun in a comparative construction (“younger than her” or “younger than she”?), see personal pronoun and than ORIGIN Old English hire, genitive and dative of hīo, hēo ‘she’."
        // no numbered senses; bullets only, across two parts of speech
        let he = "he | hē | pronoun [third person singular] used to refer to a man, boy, or male animal previously mentioned or easily identified: everyone liked my father—he was the perfect gentleman. • used to refer to a person or animal of unspecified sex (in modern use, now chiefly replaced by “he or she” or “they”): every child needs to know that he is loved. • any person (in modern use, now chiefly replaced by “anyone” or “the person”): he who is silent consents. noun [in singular] a male; a man: is that a he or a she?. • [in combination] male: a he-goat. USAGE Until recently, he was used to refer to a person of unspecified sex, as in ‘every child needs to know that he is loved’, but this is now generally regarded as old-fashioned or sexist. ORIGIN Old English he, hē, of Germanic origin; related to Dutch hij."
        // a homograph number in the headword slot
        let ha = "ha 1 | hä | (also hah) exclamation used to express surprise, suspicion, triumph, or some other emotion: Ha! That'll teach you!. ORIGIN natural utterance: first recorded in Middle English."

        // hello: three parts of speech, each with a single sense.
        let h = DefinitionParser.parse(hello, term: "hello")
        check("hello headword drops the syllabified duplicate", h.headword == "hello")
        check("hello pronunciation", h.pronunciation == "h\u{259}\u{2C8}l\u{14D}, he\u{2C8}l\u{14D}")
        check("hello has three parts of speech", h.sections.count == 3)
        check(
            "hello parts of speech in order",
            h.sections.map { $0.partOfSpeech } == ["exclamation", "noun", "verb"])
        check(
            "hello leading variant forms are not a sense",
            h.sections.allSatisfy { $0.partOfSpeech != nil })
        check(
            "hello exclamation sense drops its example",
            h.sections[0].senses == ["used as a greeting or to begin a phone conversation"])
        check(
            "hello verb sense drops the inflection list and grammar label",
            h.sections[2].senses == ["say or shout \u{201C}hello\u{201D}; greet someone"])

        // run: numbered senses across two parts of speech, and every trailer marker.
        let r = DefinitionParser.parse(run, term: "run")
        check("run headword", r.headword == "run")
        check("run has verb and noun", r.sections.map { $0.partOfSpeech } == ["verb", "noun"])
        check(
            "run verb sense 1 strips [no object]",
            r.sections[0].senses.first?.hasPrefix("move at a speed faster than a walk") == true)
        check("run noun sense 1", r.sections[1].senses.first == "an act or spell of running")
        check(
            "run drops PHRASES, PHRASAL VERBS, DERIVATIVES, USAGE and ORIGIN",
            !r.sections.contains { $0.senses.contains { $0.contains("ORIGIN") || $0.contains("PHRASES") } })
        check(
            "run inflections in parentheses do not become senses",
            r.sections[0].senses.allSatisfy { !$0.hasPrefix("(runs)") })

        // apple: numbered senses, and parentheticals that carry meaning must survive.
        let a = DefinitionParser.parse(apple, term: "apple")
        check("apple headword", a.headword == "apple")
        check("apple is one part of speech", a.sections.count == 1)
        check("apple has three senses", a.sections[0].senses.count == 3)
        check(
            "apple keeps a meaningful parenthetical",
            a.sections[0].senses[1].hasPrefix("(also apple tree)"))
        check(
            "apple drops the PHRASES trailer",
            !a.sections[0].senses.contains { $0.contains("upset the applecart") })

        // serendipity: a single unnumbered sense.
        let s = DefinitionParser.parse(serendipity, term: "serendipity")
        check("serendipity headword", s.headword == "serendipity")
        check(
            "serendipity is one noun sense",
            s.sections.count == 1 && s.sections[0].senses.count == 1)
        check(
            "serendipity drops its example",
            s.sections[0].senses[0]
                == "the occurrence and development of events by chance in a happy or beneficial way")

        // New York: no part of speech at all, and numbers in the prose that must not split senses.
        let n = DefinitionParser.parse(new_york, term: "New York")
        check("New York keeps a two-word headword", n.headword == "New York")
        check("New York has no part of speech", n.sections.count == 1)
        check("New York part of speech is nil", n.sections[0].partOfSpeech == nil)
        check("New York has two senses", n.sections[0].senses.count == 2)
        check(
            "years and populations are not sense markers",
            n.sections[0].senses[0].contains("19,490,297"))

        // quickly: one sense plus a sub-sense bullet.
        let q = DefinitionParser.parse(quickly, term: "quickly")
        check("quickly is one adverb sense", q.sections.map { $0.partOfSpeech } == ["adverb"])
        check("quickly drops the sub-sense", q.sections[0].senses == ["at a fast speed; rapidly"])

        // her: the phantom-section case. "used as the object of a verb or preposition" must not
        // split, and "possessive determiner" must not be lost to the bare "determiner" it contains.
        let herEntry = DefinitionParser.parse(her, term: "her")
        check("her headword", herEntry.headword == "her")
        check(
            "her has exactly two parts of speech",
            herEntry.sections.map { $0.partOfSpeech } == ["pronoun", "possessive determiner"])
        check(
            "prose mentions of verb/preposition do not split a sense",
            herEntry.sections[0].senses.first?.hasPrefix(
                "used as the object of a verb or preposition") == true)
        check("her pronoun has two numbered senses", herEntry.sections[0].senses.count == 2)
        check(
            "her possessive determiner survives", herEntry.sections[1].senses.count == 2)

        // he: bullets and no numbering, across two parts of speech.
        let heEntry = DefinitionParser.parse(he, term: "he")
        check("he has pronoun then noun", heEntry.sections.map { $0.partOfSpeech } == ["pronoun", "noun"])
        check(
            "he pronoun sense drops its example and grammar label",
            heEntry.sections[0].senses
                == ["used to refer to a man, boy, or male animal previously mentioned or easily identified"])
        check("he noun sense", heEntry.sections[1].senses == ["a male; a man"])

        // ha: `ha 1` is the first of several entries for the spelling, not a headword called "ha 1".
        let haEntry = DefinitionParser.parse(ha, term: "ha")
        check("homograph number is dropped from the headword", haEntry.headword == "ha")
        check("ha is one exclamation", haEntry.sections.map { $0.partOfSpeech } == ["exclamation"])
        check(
            "ha sense drops its example",
            haEntry.sections[0].senses
                == ["used to express surprise, suspicion, triumph, or some other emotion"])

        // Degenerate input must still produce something displayable rather than crash or vanish.
        let empty = DefinitionParser.parse("", term: "zzz")
        check("empty input keeps the term as headword", empty.headword == "zzz")
        check("empty input has no sections", empty.sections.isEmpty)

        let garbage = DefinitionParser.parse("qqq zzz wibble", term: "qqq")
        check("unparseable input still yields one section", garbage.sections.count == 1)
        check(
            "unparseable input falls back to the raw text",
            garbage.sections[0].partOfSpeech == nil
                && garbage.sections[0].senses == ["qqq zzz wibble"])

        // Invented, not a recording: every captured entry carries a `| pronunciation |`, so there is
        // no evidence for what a bar-less one looks like. It must degrade to the raw fallback rather
        // than guess — asserting a part of speech here would encode an assumption nothing supports.
        let noBars = DefinitionParser.parse("wibble noun a thing that wibbles", term: "wibble")
        check(
            "a bar-less entry degrades to the raw fallback",
            noBars.sections.count == 1 && noBars.sections[0].partOfSpeech == nil)

        check("plainText carries every sense", r.plainText.contains("an act or spell of running"))

        if failed == 0 {
            print("dictionary-test: all checks passed (\(passed) cases)")
        } else {
            print("dictionary-test: \(passed) passed, \(failed) failed")
            exit(1)
        }
    }
}
