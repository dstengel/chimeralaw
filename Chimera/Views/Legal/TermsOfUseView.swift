// TermsOfUseView.swift
// Chimera Law
// Terms of Use — German law compliant, bilingual.
// German is legally binding; English is a courtesy translation.

import SwiftUI

struct TermsOfUseView: View {

    // MARK: - Versioning
    // Bump `version` on every published change. Use semantic MAJOR.MINOR:
    //   MAJOR: substantive rights/duties change; requires 30-day notice per § 11
    //   MINOR: clarifications, address updates, typo fixes
    // `effectiveDate` is the calendar date on which this version takes effect.
    static let version: String = "2.0"
    static let effectiveDate: String = "14. April 2026"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Group {
                    section1Scope
                    section2Service
                    section3Subscription
                    section4Trial
                    section5Withdrawal
                    section6AIDisclaimer
                    section7UserObligations
                    section8Budget
                    section9Liability
                }
                Group {
                    section10DataProtection
                    section11Changes
                    section12AppleEULA
                    section13ODR
                    section14Severability
                    section15GoverningLaw
                    section16VersionHistory
                    section17AbusePrevention
                }
            }
            .padding(DKLayout.screenPadding)
        }
        .navigationTitle("Nutzungsbedingungen")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nutzungsbedingungen / Terms of Use")
                .font(.dkHeadline)
                .foregroundColor(.dkPrimary)
            paragraph("Stand / Last updated: \(Self.effectiveDate) · Version \(Self.version)")
        }
    }

    // MARK: - Sections

    private var section1Scope: some View {
        sectionBlock(title: "1. Geltungsbereich und Anbieter / Scope and Provider") {
            paragraph("""
            Diese Nutzungsbedingungen („Bedingungen") regeln die \
            Nutzung der iOS-Anwendung Chimera Law („die App"), \
            bereitgestellt von Daniel Stengel-Dori, Ostendstr. 88, 60314 \
            Frankfurt am Main, Deutschland („Anbieter"). Mit der \
            Nutzung der App stimmt der Nutzer („Nutzer") diesen \
            Bedingungen zu. Stimmt der Nutzer nicht zu, darf die App \
            nicht genutzt werden.
            """)
            paragraph("""
            These Terms of Use ("Terms") govern the use of the iOS \
            application Chimera Law ("the App"), provided by \
            Daniel Stengel-Dori, Ostendstr. 88, 60314 Frankfurt am Main, \
            Germany ("Provider"). By using the App, you ("User") \
            agree to these Terms. If you do not agree, you must not \
            use the App.
            """)
            paragraph("""
            Die App wird über den Apple App Store weltweit \
            angeboten; anwendbar sind ergänzend die jeweiligen \
            Apple-Bedingungen (siehe § 12).
            """)
            paragraph("""
            The App is offered worldwide through the Apple App Store; \
            the applicable Apple terms apply in addition (see § 12).
            """)
        }
    }

    private var section2Service: some View {
        sectionBlock(title: "2. Leistungsbeschreibung / Service Description") {
            Group {
                paragraph("""
                Chimera Law ist ein KI-gestütztes Werkzeug zur Umformulierung \
                von Klauseln aus Venture-Capital-Finanzierungsdokumenten \
                (Term Sheets, Beteiligungsverträge, Gesellschaftervereinbarungen, \
                Satzungen, Side Letter, Wandeldarlehen). Die App bietet \
                insbesondere:
                """)
                bulletPoint("Klauselumformulierung in sieben Deal-Stage-Personas (Term Sheet, Series Seed, Series A und später, Convertible / Bridge, Secondary / Exit, Cross-Border (US/EU), Plain Language).")
                bulletPoint("Anpassung der Founder-/Investor-Ausrichtung über eine fünfstufige Steuerung (F2, F1, N, I1, I2).")
                bulletPoint("Parallele Erzeugung aller fünf Varianten in einem einzigen Aufruf.")
                bulletPoint("Klausel-Analyse („Tell Me\u{201C}) mit erläuterndem Kommentar (BVK / NVCA-Bezug).")
                bulletPoint("Erkennung von Track-Changes-Markup aus Fotos mittels Bildverarbeitung (Vision-API).")
                bulletPoint("OCR-Texterkennung aus Kamera- und Mediathek-Bildern.")
                bulletPoint("Spracheingabe für Zusatzanweisungen und Klauseltexte.")
                bulletPoint("Export der Ergebnisse als DOCX, PDF sowie Klartext (einschließlich Kopie in die Zwischenablage).")
            }
            Group {
                paragraph("""
                Chimera Law is an AI-powered tool for rephrasing clauses from \
                venture-capital financing documents (term sheets, investment \
                agreements (Beteiligungsverträge), shareholders' agreements \
                (Gesellschaftervereinbarungen), articles of association \
                (Satzungen), side letters, and convertible loan agreements \
                (Wandeldarlehen)). The App in particular offers:
                """)
                bulletPoint("Clause rephrasing in seven deal-stage personas (Term Sheet, Series Seed, Series A and later, Convertible / Bridge, Secondary / Exit, Cross-Border (US/EU), and Plain Language).")
                bulletPoint("Founder/investor orientation adjustment via a five-level heat control (F2, F1, N, I1, I2).")
                bulletPoint("Parallel generation of all five variants in a single call.")
                bulletPoint("Clause analysis (\"Tell Me\") with explanatory commentary referenced to BVK / NVCA standards.")
                bulletPoint("Track Changes detection from photographs via image processing (Vision API).")
                bulletPoint("OCR text recognition from camera and photo library images.")
                bulletPoint("Voice input for additional instructions and clause text.")
                bulletPoint("Export of results as DOCX, PDF, and plain text (including clipboard copy).")
            }
            paragraph("""
            Die App stellt keine Rechtsberatung dar. Die KI-generierten \
            Ergebnisse sind Textvorschläge und ersetzen keine \
            professionelle rechtliche Prüfung. Der Nutzer trägt die \
            alleinige Verantwortung für die Überprüfung der \
            Richtigkeit, Vollständigkeit und rechtlichen Eignung jeder \
            Ausgabe vor deren Verwendung.
            """)
            paragraph("""
            The App does not provide legal advice. The AI-generated \
            output is a text suggestion and does not replace \
            professional legal review. The User bears sole \
            responsibility for verifying the correctness, \
            completeness, and legal suitability of any output before \
            use.
            """)
        }
    }

    private var section3Subscription: some View {
        sectionBlock(title: "3. Abonnement und Zahlung / Subscription and Payment") {
            paragraph("""
            Die Nutzung der KI-Funktionen von Chimera Law setzt ein \
            aktives Abonnement voraus, das über die Apple-ID des \
            Nutzers im App Store verwaltet wird. Dies gilt auch für \
            Nutzer, die einen eigenen Anthropic-API-Schlüssel \
            hinterlegen („BYOK"): der eigene Schlüssel ersetzt nicht \
            das Abonnement, sondern hebt lediglich die vom Anbieter \
            gesetzte monatliche Nutzungsgrenze auf (siehe § 8).
            """)
            paragraph("""
            Use of Chimera Law's AI features requires an active \
            subscription, managed through the User's Apple ID via the \
            App Store. This also applies to users who provide their \
            own Anthropic API key ("BYOK"): the user-supplied key \
            does not replace the subscription; it only lifts the \
            Provider's monthly usage cap (see § 8).
            """)
            paragraph("""
            Das Abonnement wird monatlich abgerechnet und verlängert \
            sich automatisch, sofern es nicht mindestens 24 Stunden \
            vor Ende des aktuellen Abrechnungszeitraums gekündigt \
            wird. Die Kündigung erfolgt über die Apple-ID-Konto- \
            einstellungen (Einstellungen > Apple-ID > Abonnements). \
            Nach Ablauf des Abonnements werden die KI-Funktionen \
            ausgesetzt. In iCloud gespeicherte Daten bleiben verfügbar \
            und sind bei Reaktivierung wieder zugänglich.
            """)
            paragraph("""
            The subscription is billed monthly and renews \
            automatically unless cancelled at least 24 hours before \
            the end of the current billing period. Cancellation is \
            performed through the User's Apple ID account settings \
            (Settings > Apple ID > Subscriptions). On expiry of the \
            subscription, the AI features are suspended. Data stored \
            in iCloud remains available and is accessible again upon \
            reactivation.
            """)
            paragraph("""
            Der jeweils gültige Abonnementpreis wird zum Zeitpunkt \
            des Kaufs im App Store angezeigt. Alle Zahlungen werden \
            von Apple abgewickelt; der Anbieter erhält und speichert \
            keine Zahlungsinformationen. Es gelten ergänzend die \
            jeweils aktuellen Bedingungen der Apple Media Services.
            """)
            paragraph("""
            The applicable subscription price is displayed in the App \
            Store at the time of purchase. All payments are processed \
            by Apple; the Provider does not receive or store payment \
            information. The then-current Apple Media Services terms \
            apply in addition.
            """)
        }
    }

    private var section4Trial: some View {
        sectionBlock(title: "4. Kostenlose Testphase / Free Trial") {
            paragraph("""
            Neue Nutzer können eine kostenlose Testphase erhalten, \
            deren Dauer zum Zeitpunkt des Abonnementabschlusses im \
            App Store angezeigt wird. Für die Testphase gelten im \
            Übrigen die Bedingungen des App Stores vorrangig. Wird \
            das Abonnement nicht vor Ablauf der Testphase gekündigt, \
            wird das reguläre kostenpflichtige Abonnement automatisch \
            aktiviert und das Apple-ID-Konto des Nutzers belastet.
            """)
            paragraph("""
            New users may receive a free trial period; its length is \
            displayed in the App Store at the time of subscription. \
            Otherwise, the App Store terms govern the trial with \
            priority. If the subscription is not cancelled before the \
            trial ends, the regular paid subscription is automatically \
            activated and the User's Apple ID account is charged.
            """)
        }
    }

    private var section5Withdrawal: some View {
        sectionBlock(title: "5. Widerrufsrecht / Right of Withdrawal") {
            paragraph("""
            Sind Sie Verbraucher im Sinne von § 13 BGB, haben Sie das \
            Recht, den Abonnementvertrag innerhalb von 14 Tagen ohne \
            Angabe von Gründen zu widerrufen. Die Widerrufsfrist \
            beginnt an dem Tag, an dem der Vertrag geschlossen wird \
            (d. h. am Tag des Kaufs oder der Aktivierung der \
            Testphase im App Store).
            """)
            paragraph("""
            If you are a consumer within the meaning of Section 13 \
            BGB, you have the right to withdraw from the subscription \
            contract within 14 days without giving any reason. The \
            withdrawal period begins on the day the contract is \
            concluded (i.e. the date of purchase or trial activation \
            in the App Store).
            """)
            paragraph("""
            Da der Abonnementvertrag über den Apple App Store \
            geschlossen wird, ist Ihr Vertragspartner insoweit Apple; \
            die Widerrufsbelehrung und die Einholung der Einwilligung \
            zum sofortigen Leistungsbeginn nach § 356 Abs. 5 BGB \
            erfolgen durch Apple im Rahmen des Kaufvorgangs. Sie \
            bestätigen dort ausdrücklich den sofortigen Beginn der \
            Leistung und nehmen zur Kenntnis, dass Sie Ihr \
            Widerrufsrecht mit vollständiger Bereitstellung des \
            digitalen Inhalts verlieren.
            """)
            paragraph("""
            Because the subscription contract is concluded through \
            the Apple App Store, Apple is your contracting party in \
            that respect; the withdrawal notice and the collection of \
            consent to immediate performance under Section 356(5) BGB \
            are carried out by Apple as part of the purchase flow. At \
            that point, you expressly request immediate performance \
            and acknowledge that you will lose your right of \
            withdrawal once the digital content has been fully \
            provided.
            """)
            paragraph("""
            Unabhängig davon können Sie das Abonnement jederzeit für \
            künftige Abrechnungszeiträume über die \
            Abonnementverwaltung in Ihren Apple-ID-Einstellungen \
            kündigen. Rückerstattungsanfragen sind an Apple zu \
            richten; für Kulanzanfragen können Sie uns ergänzend unter \
            support@medienkommission.de kontaktieren.
            """)
            paragraph("""
            Independently, you may cancel the subscription at any \
            time for future billing periods via the subscription \
            management in your Apple ID settings. Refund requests \
            must be directed to Apple; for goodwill enquiries you may \
            additionally contact us at support@medienkommission.de.
            """)
        }
    }

    private var section6AIDisclaimer: some View {
        sectionBlock(title: "6. KI-generierte Ausgaben — Haftungsausschluss / AI-Generated Output — Disclaimer") {
            Group {
                paragraph("""
                Chimera Law verwendet künstliche Intelligenz (Anthropic \
                Claude API) zur Erzeugung umformulierter Klauseltexte und \
                analytischer Kommentare. Der Nutzer nimmt zur Kenntnis \
                und stimmt zu, dass:
                """)
                bulletPoint("KI-generierte Ausgaben Fehler, Auslassungen, Mehrdeutigkeiten, erfundene Bezugnahmen („Halluzinationen\u{201C}) oder rechtlich fehlerhafte Formulierungen enthalten können.")
                bulletPoint("Generierte Klauseln Verweise auf Normen, Standardverträge (z. B. BVK Standards Documentation, NVCA-Modelldokumente) oder Marktusancen enthalten können, die in der konkreten Transaktion nicht einschlägig sind oder nicht der aktuellen Marktpraxis entsprechen.")
                bulletPoint("Die Ausgaben keine Rechtsberatung darstellen und nicht als solche herangezogen werden dürfen.")
                bulletPoint("Der Nutzer allein für die Überprüfung, Verifizierung und Freigabe aller Ausgaben vor deren Verwendung in Rechtsdokumenten verantwortlich ist.")
                bulletPoint("Der Anbieter ausdrücklich jede Gewährleistung für die rechtliche Richtigkeit, Vollständigkeit oder Eignung der KI-generierten Ausgaben für einen bestimmten Zweck ausschließt.")
            }
            Group {
                paragraph("""
                Chimera Law uses artificial intelligence (Anthropic Claude \
                API) to generate rephrased clause text and analytical \
                commentary. The User acknowledges and agrees that:
                """)
                bulletPoint("AI-generated output may contain errors, omissions, ambiguities, fabricated references (\"hallucinations\"), or legally incorrect formulations.")
                bulletPoint("Generated clauses may contain references to statutes, standard forms (e.g. BVK Standards Documentation, NVCA model documents), or market practices that are not relevant to the specific transaction or do not reflect current market practice.")
                bulletPoint("The output does not constitute legal advice and must not be relied upon as such.")
                bulletPoint("The User is solely responsible for reviewing, verifying, and approving all output before use in any legal document.")
                bulletPoint("The Provider expressly disclaims any warranty as to the legal correctness, completeness, or fitness for a particular purpose of the AI-generated output.")
            }
            paragraph("""
            Die App ist nicht geeignet für den unmittelbaren Einsatz in \
            Rechtsdokumenten, rechtlichen Verfahren oder Transaktionen ohne \
            vorherige vollständige fachliche Prüfung durch einen qualifizierten \
            Rechtsanwalt. / The app is not suitable for direct use in legal \
            documents, legal proceedings, or transactions without prior \
            comprehensive review by a qualified legal professional.
            """)
        }
    }

    private var section7UserObligations: some View {
        sectionBlock(title: "7. Pflichten des Nutzers / User Obligations") {
            paragraph("""
            Der Nutzer darf die App nicht für Zwecke verwenden, die \
            gegen geltendes Recht verstoßen. Der Nutzer darf nicht \
            versuchen, die App zurückzuentwickeln, zu dekompilieren \
            oder deren Quellcode zu extrahieren; zwingende \
            gesetzliche Rechte nach §§ 69d, 69e UrhG bleiben \
            unberührt. Der Nutzer ist für die Wahrung der \
            Vertraulichkeit seiner Apple-ID-Zugangsdaten und etwaiger \
            in der App eingegebener API-Schlüssel verantwortlich. Der \
            Nutzer darf keine Inhalte einreichen, die Rechte an \
            geistigem Eigentum Dritter verletzen oder illegales \
            Material enthalten, und hat dafür zu sorgen, dass er für \
            die Verarbeitung von eingegebenen Vertragstexten \
            berechtigt ist (insbesondere in Bezug auf \
            Vertraulichkeits- und Datenschutzpflichten gegenüber \
            Dritten).
            """)
            paragraph("""
            The User shall not use the App for any purpose that \
            violates applicable law. The User shall not attempt to \
            reverse-engineer, decompile, or extract source code from \
            the App; mandatory statutory rights under Sections 69d, \
            69e UrhG remain unaffected. The User is responsible for \
            maintaining the confidentiality of their Apple ID \
            credentials and any API key entered in the App. The User \
            shall not submit content that infringes third-party \
            intellectual property rights or contains illegal \
            material, and is responsible for ensuring that they are \
            authorised to process the entered contract texts \
            (including in relation to confidentiality and data \
            protection obligations owed to third parties).
            """)
        }
    }

    private var section8Budget: some View {
        sectionBlock(title: "8. Monatliches KI-Nutzungskontingent / Monthly AI Usage Budget") {
            paragraph("""
            Das Abonnement umfasst ein monatliches KI-Nutzungs- \
            kontingent, das der Anbieter in der App ausweist. Bei \
            Erschöpfung des Kontingents ist die KI-Funktionalität \
            vorübergehend bis zum nächsten Kalendermonat nicht \
            verfügbar. Nutzer können in den Einstellungen einen \
            eigenen Anthropic-API-Schlüssel hinterlegen, um das \
            Systemkontingent zu umgehen; die Nutzung eines solchen \
            Schlüssels unterliegt den eigenen Bedingungen und Preisen \
            von Anthropic und erfolgt auf eigene Rechnung des Nutzers.
            """)
            paragraph("""
            The subscription includes a monthly AI usage budget, as \
            shown in the App. When the budget is exhausted, the AI \
            functionality is temporarily unavailable until the next \
            calendar month. Users may enter their own Anthropic API \
            key in Settings to bypass the system budget; use of such \
            a key is subject to Anthropic's own terms and pricing and \
            is at the User's own cost.
            """)
            paragraph("""
            Der Anbieter kann das monatliche Kontingent mit Wirkung \
            für künftige Abrechnungszeiträume anpassen. Eine \
            Änderung, die das bisher vereinbarte Leistungsverhältnis \
            wesentlich zu Lasten des Nutzers verschiebt, wird mit \
            einer Frist von mindestens 30 Tagen angekündigt und \
            berechtigt den Nutzer zur Sonderkündigung zum \
            Wirksamkeitsdatum der Änderung.
            """)
            paragraph("""
            The Provider may adjust the monthly budget with effect \
            for future billing periods. Any change that materially \
            alters the agreed balance of services to the User's \
            detriment will be announced at least 30 days in advance \
            and entitles the User to terminate the subscription with \
            effect from the date the change takes effect.
            """)
        }
    }

    private var section9Liability: some View {
        sectionBlock(title: "9. Haftungsbeschränkung / Limitation of Liability") {
            Group {
                paragraph("""
                Die Haftung des Anbieters ist, soweit gesetzlich zulässig, \
                wie folgt beschränkt:
                """)
                bulletPoint("Der Anbieter haftet unbeschränkt für Schäden, die durch Vorsatz oder grobe Fahrlässigkeit verursacht werden, sowie für Schäden aus der Verletzung des Lebens, des Körpers oder der Gesundheit.")
                bulletPoint("Bei Verletzung wesentlicher Vertragspflichten (Kardinalpflichten) durch einfache Fahrlässigkeit ist die Haftung des Anbieters auf den vorhersehbaren, vertragstypischen Schaden begrenzt. Wesentliche Vertragspflichten sind solche, deren Erfüllung die ordnungsgemäße Durchführung des Vertrags überhaupt erst ermöglicht und auf deren Einhaltung der Nutzer regelmäßig vertrauen darf.")
                bulletPoint("Die Haftung für einfache Fahrlässigkeit ist im Übrigen ausgeschlossen.")
                bulletPoint("Die Haftung nach dem Produkthaftungsgesetz bleibt unberührt.")
            }
            Group {
                paragraph("""
                The Provider's liability is limited as follows, to the \
                extent permitted by law:
                """)
                bulletPoint("The Provider is liable without limitation for damages caused by intent (Vorsatz) or gross negligence (grobe Fahrlässigkeit), as well as for damages resulting from injury to life, body, or health.")
                bulletPoint("For breaches of material contractual obligations (wesentliche Vertragspflichten / Kardinalpflichten) caused by ordinary negligence, the Provider's liability is limited to the foreseeable, contract-typical damage. Material contractual obligations are those whose fulfilment is essential for the proper performance of the contract and on whose compliance the User may regularly rely.")
                bulletPoint("Liability for ordinary negligence is otherwise excluded.")
                bulletPoint("Liability under the German Product Liability Act (Produkthaftungsgesetz) remains unaffected.")
            }
            paragraph("""
            Der Anbieter garantiert keinen ununterbrochenen Zugang \
            oder fehlerfreien Betrieb der App. Vorübergehende \
            Unterbrechungen aufgrund von Wartung, Updates oder \
            Umständen außerhalb der Kontrolle des Anbieters \
            (einschließlich der Nichtverfügbarkeit der Anthropic-API \
            oder von Apple-Diensten) stellen keinen Vertragsbruch dar.
            """)
            paragraph("""
            The Provider does not guarantee uninterrupted \
            availability or error-free operation of the App. \
            Temporary interruptions due to maintenance, updates, or \
            circumstances beyond the Provider's control (including \
            unavailability of the Anthropic API or Apple services) do \
            not constitute a breach of contract.
            """)
        }
    }

    private var section10DataProtection: some View {
        sectionBlock(title: "10. Datenschutz / Data Protection") {
            paragraph("""
            Die Verarbeitung personenbezogener Daten richtet sich \
            nach der Datenschutzerklärung des Anbieters, die in der \
            App unter Einstellungen > Datenschutz abrufbar und \
            autoritativ unter www.medienkommission.de verfügbar ist. \
            Mit der Nutzung der App bestätigt der Nutzer, die \
            Datenschutzerklärung zur Kenntnis genommen zu haben.
            """)
            paragraph("""
            The processing of personal data is governed by the \
            Provider's Privacy Policy, available within the App under \
            Settings > Privacy and authoritatively at \
            www.medienkommission.de. By using the App, the User \
            acknowledges having read the Privacy Policy.
            """)
        }
    }

    private var section11Changes: some View {
        sectionBlock(title: "11. Änderungen dieser Bedingungen / Changes to These Terms") {
            paragraph("""
            Der Anbieter behält sich das Recht vor, diese Bedingungen \
            mit Wirkung für die Zukunft zu ändern. Wesentliche \
            Änderungen werden mindestens 30 Tage vor Inkrafttreten \
            über einen In-App-Hinweis beim nächsten Programmstart \
            mitgeteilt, der eine ausdrückliche erneute Kenntnisnahme \
            erfordert, bevor die App weiter genutzt werden kann. Die \
            jeweils aktuelle Fassung ist jederzeit in der App sowie \
            unter dem in § 10 genannten Link verfügbar. Stimmt der \
            Nutzer nicht zu, kann er das Abonnement vor Inkrafttreten \
            der Änderungen kündigen.
            """)
            paragraph("""
            The Provider reserves the right to modify these Terms \
            with effect for the future. Material changes will be \
            communicated at least 30 days before the changes take \
            effect via an in-app notice on next launch, requiring \
            explicit re-acknowledgement before the App can be used. \
            The current version is available at any time in the App \
            and at the link in § 10. If the User does not agree, \
            they may cancel the subscription before the changes \
            take effect.
            """)
        }
    }

    private var section12AppleEULA: some View {
        sectionBlock(title: "12. Apple-Standard-EULA / Apple Standard EULA") {
            paragraph("""
            Zusätzlich zu diesen Bedingungen gilt die \
            Standard-Endbenutzer-Lizenzvereinbarung (EULA) von Apple \
            für lizenzierte Anwendungen, abrufbar unter \
            https://www.apple.com/legal/internet-services/itunes/dev/stdeula/. \
            Soweit Apples Standard-EULA Sachverhalte regelt, die das \
            Verhältnis zwischen Nutzer und Apple betreffen \
            (insbesondere Lizenzumfang, Gewährleistung gegenüber \
            Apple und Ansprüche wegen Verletzung von Rechten Dritter), \
            gehen die Bestimmungen der Apple-EULA diesen Bedingungen \
            vor. Im Übrigen gelten diese Bedingungen.
            """)
            paragraph("""
            In addition to these Terms, Apple's Standard End User \
            Licence Agreement (EULA) for Licensed Applications \
            applies, available at \
            https://www.apple.com/legal/internet-services/itunes/dev/stdeula/. \
            To the extent that Apple's Standard EULA governs matters \
            relating to the relationship between the User and Apple \
            (in particular the scope of the licence, warranty claims \
            against Apple, and third-party IP claims), the \
            provisions of the Apple EULA prevail over these Terms. \
            Otherwise, these Terms apply.
            """)
        }
    }

    private var section13ODR: some View {
        sectionBlock(title: "13. Online-Streitbeilegung / Online Dispute Resolution") {
            paragraph("""
            Die Europäische Kommission stellt eine Plattform zur \
            Online-Streitbeilegung (OS) bereit: \
            https://ec.europa.eu/consumers/odr/. Die E-Mail-Adresse \
            des Anbieters lautet support@medienkommission.de. Der Anbieter \
            ist weder verpflichtet noch bereit, an \
            Streitbeilegungsverfahren vor einer \
            Verbraucherschlichtungsstelle gemäß § 36 VSBG \
            teilzunehmen.
            """)
            paragraph("""
            The European Commission provides a platform for online \
            dispute resolution (ODR) at \
            https://ec.europa.eu/consumers/odr/. The Provider's \
            email address is support@medienkommission.de. The Provider is \
            neither obligated nor willing to participate in dispute \
            resolution proceedings before a consumer arbitration \
            board (Verbraucherschlichtungsstelle) pursuant to \
            Section 36 VSBG.
            """)
        }
    }

    private var section14Severability: some View {
        sectionBlock(title: "14. Salvatorische Klausel / Severability") {
            paragraph("""
            Sollte eine Bestimmung dieser Bedingungen unwirksam sein \
            oder werden, bleiben die übrigen Bestimmungen in vollem \
            Umfang wirksam. Die unwirksame Bestimmung wird durch eine \
            wirksame Bestimmung ersetzt, die dem wirtschaftlichen \
            Zweck der unwirksamen Bestimmung am nächsten kommt.
            """)
            paragraph("""
            Should any provision of these Terms be or become invalid \
            or unenforceable, the remaining provisions shall remain \
            in full force and effect. The invalid or unenforceable \
            provision shall be replaced by a valid provision that \
            most closely reflects the economic purpose of the invalid \
            provision.
            """)
        }
    }

    private var section15GoverningLaw: some View {
        sectionBlock(title: "15. Anwendbares Recht, Gerichtsstand, Sprache / Governing Law, Jurisdiction, Language") {
            paragraph("""
            Diese Bedingungen unterliegen dem Recht der Bundesrepublik \
            Deutschland unter Ausschluss des UN-Kaufrechts (CISG). \
            Für Verbraucher mit gewöhnlichem Aufenthalt in der EU \
            gelten zusätzlich die zwingenden Verbraucherschutz- \
            vorschriften ihres Wohnsitzlandes. Gerichtsstand für \
            Kaufleute ist Frankfurt am Main. Für Verbraucher gelten \
            die gesetzlichen Gerichtsstände.
            """)
            paragraph("""
            These Terms are governed by the laws of the Federal \
            Republic of Germany, excluding the UN Convention on \
            Contracts for the International Sale of Goods (CISG). \
            For consumers habitually resident in the EU, mandatory \
            consumer protection provisions of their country of \
            residence apply in addition. The place of jurisdiction \
            for merchants (Kaufleute) is Frankfurt am Main. For \
            consumers, the statutory places of jurisdiction apply.
            """)
            paragraph("""
            Rechtlich verbindlich ist ausschließlich die deutsche \
            Fassung dieser Bedingungen; die englische Fassung ist \
            eine Übersetzung zur Bequemlichkeit. Bei Abweichungen \
            zwischen den Fassungen geht die deutsche Fassung vor.
            """)
            paragraph("""
            Only the German version of these Terms is legally \
            binding; the English version is a courtesy translation. \
            In the event of discrepancies between the versions, the \
            German version prevails.
            """)
        }
    }

    private var section16VersionHistory: some View {
        sectionBlock(title: "16. Versionshistorie / Version History") {
            bulletPoint("Version 2.0 — 14. April 2026: Grundlegende Neufassung. Erweiterte Leistungsbeschreibung (Tell Me, Mehrfach-Varianten, Track-Changes, Export); Klarstellung, dass BYOK das Abonnement nicht ersetzt; Widerrufsbelehrung an Apple-Kaufvorgang angelehnt (§ 356 Abs. 5 BGB); § 7 Carve-out nach §§ 69d, 69e UrhG; § 8 Sonderkündigungsrecht bei wesentlicher Kontingentänderung; § 12 Vorrang der Apple-EULA korrigiert; § 15 Sprachregelung ergänzt; neuer § 17 zur Missbrauchsprävention.")
            bulletPoint("Version 1.x — bis 13. April 2026 (Stand 26.03.2026): Erstfassung.")

            bulletPoint("Version 2.0 — 14 April 2026: Substantive rewrite. Expanded service description (Tell Me, multi-variant, Track Changes, export); BYOK does not replace the subscription; withdrawal notice aligned with Apple's purchase flow (Section 356(5) BGB); § 7 carve-out for Sections 69d, 69e UrhG; § 8 special termination right on material budget changes; § 12 Apple EULA priority corrected; § 15 language clause added; new § 17 on abuse prevention.")
            bulletPoint("Version 1.x — until 13 April 2026 (Stand 26 March 2026): First version.")
        }
    }

    private var section17AbusePrevention: some View {
        sectionBlock(title: "17. Missbrauchsprävention und Dienstunterbrechung / Abuse Prevention and Service Interruption") {
            paragraph("""
            Der Anbieter ist berechtigt, den Zugang zur KI- \
            Funktionalität ganz oder teilweise auszusetzen, zu \
            beschränken oder zu beenden, wenn der Nutzer gegen diese \
            Bedingungen, gegen die Bedingungen oder Usage Policy von \
            Anthropic oder gegen geltendes Recht verstößt, oder wenn \
            Anthropic eine entsprechende Missbrauchskennzeichnung \
            signalisiert. Eine derartige Maßnahme stellt keine \
            Vertragsverletzung durch den Anbieter dar.
            """)
            paragraph("""
            The Provider is entitled to suspend, restrict, or \
            terminate access to the AI functionality in whole or in \
            part if the User breaches these Terms, Anthropic's terms \
            or Usage Policy, or applicable law, or if Anthropic \
            signals an abuse flag in respect of the User's traffic. \
            Such a measure does not constitute a breach of contract \
            by the Provider.
            """)
            paragraph("""
            Der Anbieter wird den Nutzer über die Maßnahme und deren \
            Gründe informieren, soweit dies rechtlich zulässig und \
            angemessen ist. Bei versehentlichen oder geringfügigen \
            Verstößen wird der Anbieter eine angemessene Gelegenheit \
            zur Abhilfe einräumen, bevor er dauerhafte Maßnahmen \
            ergreift.
            """)
            paragraph("""
            The Provider will inform the User of the measure and its \
            reasons to the extent legally permissible and \
            appropriate. For inadvertent or minor breaches, the \
            Provider will grant a reasonable opportunity to cure \
            before taking permanent measures.
            """)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionBlock(
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.dkSubheadline)
                .foregroundColor(.dkPrimary)
            content()
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.dkBody)
            .foregroundColor(.dkTextPrimary)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("  \u{2022}")
                .font(.dkBody)
                .foregroundColor(.dkTextSecondary)
            Text(text)
                .font(.dkBody)
                .foregroundColor(.dkTextPrimary)
        }
    }
}
