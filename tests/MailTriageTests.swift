import Foundation

@main
enum MailTriageTests {
    static func main() {
        words()
        decisions()
        search()
        scripts()
        print("MailTriage tests: all passed")
        MailPlanTests.run()
    }

    static func facts(_ sender: String = "Paul <paul@client.fr>", subject: String = "Devis mai",
                      text: String? = nil, account: String = "Pro") -> MailFacts {
        MailFacts(sender: sender, subject: subject, account: account, text: text)
    }

    static func words() {
        precondition(MailTriage.normalize("  Réunion ÉTÉ ") == "reunion ete")
        precondition(MailTriage.containsWord("Big SALE today", "sale"))
        precondition(!MailTriage.containsWord("Salesforce update", "sale"), "whole words only")
        precondition(MailTriage.containsWord("Promo d'été -50%", "promo"))
        precondition(MailTriage.containsWord("Votre facture du mois", "facture du mois"))
        precondition(MailTriage.containsWord("from news@shop.com", "news@shop.com"))
        precondition(MailTriage.containsWord("bonjour, réunion demain", "reunion"))
        precondition(!MailTriage.containsWord("anything", ""))
        precondition(facts().address == "paul@client.fr")
        precondition(facts("paul@client.fr").address == "paul@client.fr")
    }

    static func decisions() {
        var s = MailTriageSettings()
        precondition(MailTriage.decide(facts(), s) == nil, "no settings: left alone")
        // VIP by address or domain, and VIP wins over everything.
        s.vip = ["@client.fr"]
        s.banned = ["devis"]
        precondition(MailTriage.decide(facts(), s) == MailDecision(action: .important, reason: .vip("@client.fr")))
        s.vip = ["client.fr"]
        precondition(MailTriage.decide(facts("x@mail.client.fr"), s)?.reason == .vip("client.fr"), "subdomain")
        precondition(MailTriage.decide(facts("x@notclient.fr"), s)?.reason == .banned("devis"), "not the same domain")
        s.vip = ["paul@client.fr"]
        precondition(MailTriage.decide(facts(), s)?.action == .important)
        precondition(MailTriage.decide(facts("Anne <anne@client.fr>"), s)?.action == .junk)
        // Banned words in the sender, subject or text.
        s.vip = []
        s.banned = ["unsubscribe"]
        precondition(MailTriage.decide(facts(text: "Click to UNSUBSCRIBE"), s)?.action == .junk)
        precondition(MailTriage.decide(facts(text: nil), s) == nil, "no text read: no text match")
        precondition(MailTriage.needsText(s))
        // Rules in order, every condition must match, disabled ones skipped.
        s.banned = []
        precondition(!MailTriage.needsText(s))
        let off = MailRule(name: "Off", enabled: false, conditions: [MailCondition(field: .sender, value: "paul")], action: .junk)
        let news = MailRule(name: "News", conditions: [MailCondition(field: .domain, value: "@client.fr"),
                                                        MailCondition(field: .subject, value: "devis")], action: .move("Clients"))
        let read = MailRule(name: "Read", conditions: [MailCondition(field: .account, value: "pro")], action: .markRead)
        s.rules = [off, news, read]
        precondition(MailTriage.decide(facts(), s) == MailDecision(action: .move("Clients"), reason: .rule("News")))
        precondition(MailTriage.decide(facts(subject: "Bonjour"), s)?.reason == .rule("Read"))
        precondition(MailTriage.decide(facts(subject: "Bonjour", account: "Perso"), s) == nil)
        s.rules = [MailRule(name: "T", conditions: [MailCondition(field: .text, value: "facture")], action: .important)]
        precondition(MailTriage.needsText(s))
        precondition(MailTriage.decide(facts(text: "Votre Facture"), s)?.action == .important)
        // Settings survive a round trip (the store saves JSON).
        let data = try! JSONEncoder().encode(s)
        precondition(try! JSONDecoder().decode(MailTriageSettings.self, from: data) == s)
    }

    static func search() {
        let q = MailQuery.parse("de:dupont objet:\"devis mai\" facture urgent")
        precondition(q.from == ["dupont"] && q.subject == ["devis mai"] && q.words == ["facture", "urgent"], "\(q)")
        precondition(MailQuery.parse("from: anne").from == ["anne"])
        precondition(MailQuery.parse("Subject:Hello").subject == ["Hello"])
        precondition(MailQuery.parse("   ").isEmpty)
        precondition(MailScript.whoseClause(MailQuery(), .all) == nil)
        let w = MailScript.whoseClause(q, .unread)!
        precondition(w.contains("sender contains \"dupont\""))
        precondition(w.contains("subject contains \"devis mai\""))
        precondition(w.contains("(subject contains \"facture\" or sender contains \"facture\")"))
        precondition(w.hasSuffix("read status is false"))
        precondition(MailScript.whoseClause(MailQuery(), .today) == "date received > d0")
        precondition(MailScript.whoseClause(MailQuery(), .flagged) == "flagged status is true")
        // Quotes and backslashes can't break out of the script.
        precondition(MailScript.quote("a\"b\\c") == "\"a\\\"b\\\\c\"")
    }

    static func scripts() {
        let a = MailScript.applyScript(account: "Pro", mailbox: "INBOX", messageId: 42, action: .junk)
        precondition(a.contains("account \"Pro\"") && a.contains("whose id is 42"))
        precondition(a.contains("set junk mail status of m to true") && a.contains("move m to junk mailbox"))
        precondition(a.contains("message id of m"))
        let mv = MailScript.applyScript(account: "Pro", mailbox: "INBOX", messageId: 1, action: .move("Clients"))
        precondition(mv.contains("move m to mailbox \"Clients\" of acc"))
        let u = MailScript.undoScript(account: "Pro", fromMailbox: "INBOX", rfcId: "<x@y>", action: .junk)
        precondition(u.contains("whose message id is \"<x@y>\""))
        precondition(u.contains("junk mailbox}") && u.contains("mailbox \"Junk\" of acc"))
        precondition(u.contains("set junk mail status of m to false") && u.contains("move m to mailbox \"INBOX\" of acc"))
        let uf = MailScript.undoScript(account: "Pro", fromMailbox: "INBOX", rfcId: "<x@y>", action: .important)
        precondition(uf.contains("set flagged status of m to false"))
        precondition(!a.contains("delete"), "Coucou never deletes a message")
        let sc = MailScript.searchScript(whose: "read status is false", today: false)
        precondition(sc.contains("id of (every message of mb whose read status is false)"))
        precondition(sc.contains("flagged status of (every message of mb whose read status is false)"))
        precondition(!sc.contains("set d0"))
        precondition(sc.contains("if c > 60 then") && sc.contains("repeat with i from a to b"), "the newest 60 at most")
        precondition(MailScript.searchScript(whose: "read status is false", today: false, limit: 5).contains("set a to c - 5 + 1"))
        precondition(MailScript.searchScript(whose: "date received > d0", today: true).contains(MailScript.todayPrelude))
    }
}
