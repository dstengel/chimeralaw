// PrivacyPolicyView.swift
// Chimera Law
// Privacy policy — bilingual (German legally binding, English courtesy translation)
// The authoritative version is hosted at medienkommission.de; this in-app text
// summarises it and satisfies Art. 13 GDPR transparency requirements.

import SwiftUI

struct PrivacyPolicyView: View {

    // MARK: - Versioning
    // Bump `version` on every published change. Use semantic MAJOR.MINOR:
    //   MAJOR: substantive rights/duties change; requires user-facing notice
    //   MINOR: clarifications, address updates, typo fixes
    // `effectiveDate` is the calendar date on which this version takes effect.
    static let version: String = "2.1"
    static let effectiveDate: String = "4. Mai 2026"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Group {
                    sectionNotice
                    section1Controller
                    section2Categories
                    section3LegalBases
                    section4Recipients
                    section5Transfers
                }
                Group {
                    section6Retention
                    section7Rights
                    section8NoAutomated
                    section9Necessity
                    section10Changes
                    section11VersionHistory
                }
                Divider()
                sectionContact
                Spacer(minLength: 40)
            }
            .padding(DKLayout.screenPadding)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Datenschutzerklärung / Privacy Policy")
                .font(.dkHeadline)
                .foregroundColor(.dkPrimary)
            paragraph("Stand / Effective date: \(Self.effectiveDate) · Version \(Self.version)")
        }
    }

    // MARK: - Sections

    private var sectionNotice: some View {
        sectionBlock(title: "Hinweis / Notice") {
            paragraph("""
            Die rechtlich verbindliche Fassung dieser Datenschutzerklärung \
            ist die deutsche Fassung; die englische Fassung dient \
            ausschließlich der Bequemlichkeit. Die jeweils aktuelle \
            autoritative Fassung ist unter dem nachstehenden Link abrufbar.
            """)
            paragraph("""
            The German version of this Privacy Policy is legally binding; \
            the English version is a courtesy translation. The current \
            authoritative version is available at the link below.
            """)
            linkRow("Chimera Law Datenschutzerklärung / Privacy Policy",
                    url: "https://medienkommission.de/de/chimera-law-privacy.html")
        }
    }

    private var section1Controller: some View {
        sectionBlock(title: "1. Verantwortlicher / Controller") {
            paragraph("""
            Verantwortlich im Sinne der DSGVO ist:
            Daniel Stengel-Dori, Ostendstr. 88, 60314 Frankfurt am Main, \
            Deutschland. Kontakt: support@medienkommission.de.
            """)
            paragraph("""
            The controller within the meaning of the GDPR is: \
            Daniel Stengel-Dori, Ostendstr. 88, 60314 Frankfurt am Main, \
            Germany. Contact: support@medienkommission.de.
            """)
            paragraph("""
            Ein Datenschutzbeauftragter ist nicht bestellt, da die \
            gesetzlichen Schwellenwerte (§ 38 BDSG) nicht erreicht \
            werden. Datenschutzanfragen richten Sie bitte an die \
            vorstehende E-Mail-Adresse.
            """)
            paragraph("""
            No Data Protection Officer is appointed because the statutory \
            thresholds (§ 38 BDSG) are not met. Please direct all data \
            protection enquiries to the email address above.
            """)
        }
    }

    private var section2Categories: some View {
        sectionBlock(title: "2. Verarbeitete Datenkategorien / Categories of Data") {
            Group {
                paragraph("""
                Im Rahmen der Nutzung von Chimera Law werden die folgenden \
                Kategorien personenbezogener und nutzungsbezogener Daten \
                verarbeitet:
                """)
                bulletPoint("Klauseltexte und Zusatzanweisungen, die Sie tippen, per OCR aus Bildern erfassen oder per Spracheingabe diktieren.")
                bulletPoint("Bilder von Vertragsseiten, die Sie zur Erkennung von Track-Changes-Markup aufnehmen oder aus der Mediathek auswählen.")
                bulletPoint("Spracheingaben, die durch Apple Speech Recognition transkribiert werden.")
                bulletPoint("Profilangaben (derzeit lediglich ein frei wählbarer Anzeigename und ein Einwilligungs-Flag) sowie Nutzungs- und Abrechnungsdaten (verbrauchte Eingabe-/Ausgabe-Tokens, geschätzte Kosten je Kalendermonat) in Ihrer privaten iCloud-Datenbank.")
                bulletPoint("Abonnement- und Transaktionsstatus, der vollständig durch Apple StoreKit verwaltet wird.")
                bulletPoint("Lokale Einstellungen (z. B. gewählter Drafting-Stil, Erscheinungsbild) in den UserDefaults des Geräts.")
                bulletPoint("Ihr optionaler Anthropic-API-Schlüssel, der im iOS-Keychain Ihres Geräts abgelegt wird und das Gerät ausschließlich als Authentifizierungs-Header ausgehender API-Aufrufe verlässt.")
                bulletPoint("Lokale Diagnoseprotokolle (os.Logger), die auf dem Gerät verbleiben und nicht an den Anbieter übertragen werden.")
            }
            Group {
                paragraph("""
                When you use Chimera Law, the following categories of personal \
                and usage-related data are processed:
                """)
                bulletPoint("Clause text and additional instructions that you type, capture via OCR from images, or dictate via voice input.")
                bulletPoint("Photographs of contract pages that you capture or select from your library for Track Changes detection.")
                bulletPoint("Voice input transcribed by Apple Speech Recognition.")
                bulletPoint("Profile data (currently only a free-text display name and a consent flag) and usage/billing records (input/output tokens consumed, estimated cost per calendar month) stored in your private iCloud database.")
                bulletPoint("Subscription and transaction status, managed in full by Apple StoreKit.")
                bulletPoint("Local settings (e.g. selected drafting style, appearance) in the device's UserDefaults.")
                bulletPoint("Your optional Anthropic API key, stored in the iOS Keychain on your device and leaving the device only as an authentication header on outbound API calls.")
                bulletPoint("Local diagnostic logs (os.Logger) that remain on the device and are not transmitted to the Provider.")
            }
        }
    }

    private var section3LegalBases: some View {
        sectionBlock(title: "3. Zwecke und Rechtsgrundlagen / Purposes and Legal Bases") {
            bulletPoint("Art. 6 Abs. 1 lit. b DSGVO — Vertragserfüllung: Bereitstellung der Umformulierungs-, Analyse- („Tell Me\u{201C}), Mehrfach-Varianten-, Track-Changes-Erkennungs- und Exportfunktionen sowie Abwicklung des Abonnements.")
            bulletPoint("Art. 6 Abs. 1 lit. a DSGVO — Einwilligung: Verarbeitung von Kamera-, Foto- und Mikrofoneingaben; die Einwilligung ist jederzeit über die iOS-Systemeinstellungen widerruflich.")
            bulletPoint("Art. 6 Abs. 1 lit. f DSGVO — Berechtigtes Interesse: lokale Diagnoseprotokolle zur Fehleranalyse und die Kurz-Speicherung von API-Inhalten durch Anthropic zur Missbrauchsprävention.")

            bulletPoint("Art. 6(1)(b) GDPR — Contract performance: providing the rephrasing, analysis (\"Tell Me\"), multi-variant, Track Changes detection, and export functions, and administering the subscription.")
            bulletPoint("Art. 6(1)(a) GDPR — Consent: processing of camera, photo, and microphone input; consent is revocable at any time via iOS system settings.")
            bulletPoint("Art. 6(1)(f) GDPR — Legitimate interest: local diagnostic logs for error analysis and Anthropic's short-term retention of API content for abuse prevention.")
        }
    }

    private var section4Recipients: some View {
        sectionBlock(title: "4. Empfänger und Drittanbieter / Recipients and Third-Party Providers") {
            Group {
                subHeader("Anthropic, PBC (USA)")
                paragraph("""
                Wenn Sie eine Klausel umformulieren, analysieren lassen, \
                mehrere Varianten erzeugen oder eine Seite zur \
                Track-Changes-Erkennung fotografieren, werden die \
                entsprechenden Inhalte (Text bzw. Bild) über die Anthropic \
                API an Anthropic, PBC, San Francisco, USA, übermittelt. \
                Chimera Law nutzt die Standard-API-Bedingungen von Anthropic \
                ohne separaten Auftragsverarbeitungsvertrag. Anthropic \
                verarbeitet die übermittelten Inhalte zum Zwecke der \
                Antwortgenerierung als Dienstleister und speichert Eingaben \
                und Ausgaben zusätzlich zu eigenen Zwecken der \
                Missbrauchsprävention; insoweit ist Anthropic \
                eigenverantwortlicher Dritter.
                """)
                paragraph("""
                When you rephrase a clause, run an analysis, generate \
                multiple variants, or photograph a page for Track Changes \
                detection, the respective content (text or image) is \
                transmitted via the Anthropic API to Anthropic, PBC, \
                San Francisco, USA. Chimera Law uses Anthropic's standard API \
                terms without a separate data processing agreement. \
                Anthropic processes the transmitted content for the purpose \
                of generating a response as a service provider and \
                additionally retains inputs and outputs for its own \
                trust-and-safety purposes; to that extent, Anthropic is an \
                independent controller.
                """)
                linkRow("Anthropic Privacy Policy (English)",
                        url: "https://privacy.claude.com/en/")
                linkRow("Anthropic Datenschutzrichtlinie (Deutsch)",
                        url: "https://privacy.claude.com/de/")
            }
            Group {
                subHeader("Apple Inc. / Apple Distribution International Ltd.")
                paragraph("""
                Ihre Profilangaben, Nutzungs- und Abrechnungsdaten werden \
                in Ihrer privaten iCloud-Datenbank über Apple CloudKit \
                gespeichert. Abonnementkäufe werden vollständig durch Apple \
                abgewickelt; Chimera Law erhält und speichert keine \
                Zahlungsinformationen. Spracheingaben können je nach \
                Gerätemodell auf dem Gerät oder auf Apple-Servern \
                verarbeitet werden. Für in der EU bereitgestellte Dienste \
                ist Apple Distribution International Ltd. (Irland) \
                Vertragspartner; Apple überträgt bestimmte Daten in die \
                USA auf Grundlage der EU-Standardvertragsklauseln.
                """)
                paragraph("""
                Your profile data and usage/billing records are stored in \
                your private iCloud database via Apple CloudKit. \
                Subscription purchases are handled entirely by Apple; \
                Chimera Law does not receive or store payment information. \
                Voice input may be processed on-device or on Apple servers \
                depending on your device model. For services provided in \
                the EU, Apple Distribution International Ltd. (Ireland) is \
                the contracting party; Apple transfers certain data to the \
                USA on the basis of the EU Standard Contractual Clauses.
                """)
                linkRow("Apple Privacy Policy (English)",
                        url: "https://www.apple.com/legal/privacy/en-ww/")
                linkRow("Apple Datenschutzrichtlinie (Deutsch)",
                        url: "https://www.apple.com/legal/privacy/de-ww/")
            }
            paragraph("""
            Außer Anthropic und Apple werden keine weiteren \
            Drittanbieter, Analyse-Dienste oder Tracking-SDKs \
            eingesetzt.
            """)
            paragraph("""
            No third parties other than Anthropic and Apple, and no \
            analytics or tracking SDKs, are used.
            """)
        }
    }

    private var section5Transfers: some View {
        sectionBlock(title: "5. Drittlandübermittlung / International Transfers") {
            paragraph("""
            Anthropic verarbeitet Daten in den USA. Da Anthropic \
            derzeit nicht unter dem EU-US Data Privacy Framework \
            zertifiziert ist, stützen wir die Übermittlung auf die \
            EU-Standardvertragsklauseln (Durchführungsbeschluss (EU) \
            2021/914), die in die Standardbedingungen und \
            Datenschutzrichtlinie von Anthropic einbezogen sind. \
            Ergänzend greifen, soweit anwendbar, die Garantien nach \
            Art. 46 DSGVO sowie — für einzelne Konstellationen — die \
            Ausnahmen nach Art. 49 DSGVO. Eine Kopie der \
            Standardvertragsklauseln kann beim Anbieter angefordert \
            werden.
            """)
            paragraph("""
            Anthropic processes data in the USA. As Anthropic is not \
            currently certified under the EU-US Data Privacy Framework, \
            we rely on the EU Standard Contractual Clauses \
            (Implementing Decision (EU) 2021/914), which are \
            incorporated into Anthropic's standard terms and privacy \
            policy. The safeguards under Art. 46 GDPR and — where \
            applicable — the derogations under Art. 49 GDPR also \
            apply. A copy of the Standard Contractual Clauses can be \
            requested from the Provider.
            """)
        }
    }

    private var section6Retention: some View {
        sectionBlock(title: "6. Speicherdauer / Retention") {
            bulletPoint("Klausel- und Bildinhalte werden durch Chimera Law standardmäßig nicht persistent gespeichert; sie verbleiben nur flüchtig im Arbeitsspeicher während des API-Aufrufs. Sie können jedoch über die neue Funktion „Memory\u{201C} Ihre Entwürfe ausschließlich lokal auf dem Gerät ablegen: bis zu drei manuell zu belegende Speicherplätze („Memory 1\u{201C}, „Memory 2\u{201C}, „Memory 3\u{201C}) werden bei expliziter Antippung des Memory-Knopfes geschrieben; ein zusätzlicher vierter Speicherplatz („Auto\u{201C}) wird nur dann automatisch im Hintergrund aktualisiert, wenn Sie in den Einstellungen die Option „Aktuellen Entwurf automatisch speichern\u{201C} aktivieren. Alle vier Speicherplätze werden in einem gerätegeschützten Datenspeicher (iOS-Datenschutzklasse „nach erstmaliger Benutzerauthentifizierung\u{201C}) abgelegt. Eine Übertragung an Anthropic, Apple oder andere Dritte findet ausschließlich beim regulären API-Aufruf statt; eine Speicherung außerhalb Ihres Gerätes erfolgt nicht; verschlüsselte iOS-Gerätesicherungen können diese Daten jedoch enthalten. Sie können einzelne Speicherplätze überschreiben, die automatische Speicherung jederzeit in den Einstellungen abschalten oder alle vier Speicherplätze über den Knopf „Speicher löschen\u{201C} vollständig entfernen; bei Deinstallation werden die Daten zusammen mit der App durch iOS entfernt. Bilder bleiben von dieser Speicherung ausgeschlossen.")
            bulletPoint("Anthropic speichert API-Eingaben und -Ausgaben gemäß seiner Datenschutzrichtlinie standardmäßig bis zu 30 Tage; bei festgestellten Richtlinienverstößen bis zu 2 Jahre (Inhalte) bzw. bis zu 7 Jahre (Sicherheits-Klassifikationsscores). Nutzerfeedback wird bis zu 5 Jahre gespeichert.")
            bulletPoint("Profilangaben sowie Nutzungs- und Abrechnungsdaten in Ihrer privaten iCloud verbleiben dort für die längere der beiden Fristen: 24 Monate oder die gesetzlich vorgeschriebene Aufbewahrungsfrist, sofern Sie sie nicht früher selbst löschen.")
            bulletPoint("Lokale Einstellungen und Ihr optionaler Anthropic-API-Schlüssel verbleiben auf dem Gerät bis zur Deinstallation oder bis zu Ihrer manuellen Entfernung in den Einstellungen.")
            bulletPoint("Lokale Diagnoseprotokolle unterliegen der Verwaltung durch das Betriebssystem und verlassen das Gerät nicht.")

            bulletPoint("By default, clause and image content are not persistently stored by Chimera Law; they remain only transiently in memory during the API call. You may, however, use the new \"Memory\" feature to store drafts only on this device: up to three manual slots (\"Memory 1\", \"Memory 2\", \"Memory 3\") are written when you explicitly tap the Memory button; a fourth slot (\"Auto\") is updated automatically in the background only if you enable the \"Auto-save current draft\" setting. All four slots are held in a device-protected store (iOS Data Protection class \"after first user authentication\"). The data is transmitted to Anthropic, Apple, or other third parties only during the regular API call; no off-device copy is created, although encrypted iOS device backups may include this data. You can overwrite individual slots, disable auto-save at any time in Settings, or remove all four slots via the \"Wipe all memory\" button; on uninstall, the data is removed by iOS together with the App. Images are excluded from this storage.")
            bulletPoint("Anthropic retains API inputs and outputs under its privacy policy for up to 30 days by default; for detected policy violations, up to 2 years (content) or up to 7 years (safety classification scores). User feedback is retained for up to 5 years.")
            bulletPoint("Profile data and usage/billing records in your private iCloud are kept for the longer of 24 months or any retention period mandated by law, unless you delete them earlier.")
            bulletPoint("Local settings and your optional Anthropic API key remain on the device until uninstallation or manual removal in Settings.")
            bulletPoint("Local diagnostic logs are managed by the operating system and do not leave the device.")
        }
    }

    private var section7Rights: some View {
        sectionBlock(title: "7. Ihre Rechte / Your Rights") {
            paragraph("""
            Sie haben das Recht auf Auskunft (Art. 15), Berichtigung \
            (Art. 16), Löschung (Art. 17), Einschränkung der \
            Verarbeitung (Art. 18), Datenübertragbarkeit (Art. 20) und \
            Widerspruch (Art. 21 DSGVO) sowie das Recht, eine erteilte \
            Einwilligung jederzeit mit Wirkung für die Zukunft zu \
            widerrufen (Art. 7 Abs. 3 DSGVO). Anfragen richten Sie \
            bitte an support@medienkommission.de.
            """)
            paragraph("""
            You have the right to access (Art. 15), rectification \
            (Art. 16), erasure (Art. 17), restriction of processing \
            (Art. 18), data portability (Art. 20), and objection \
            (Art. 21 GDPR), as well as the right to withdraw any \
            consent you have given with effect for the future \
            (Art. 7(3) GDPR). Please direct requests to \
            support@medienkommission.de.
            """)
            paragraph("""
            Ferner haben Sie das Recht, sich bei einer \
            Datenschutz-Aufsichtsbehörde zu beschweren, insbesondere \
            beim Hessischen Beauftragten für Datenschutz und \
            Informationsfreiheit, Gustav-Stresemann-Ring 1, 65189 \
            Wiesbaden, poststelle@datenschutz.hessen.de.
            """)
            paragraph("""
            You also have the right to lodge a complaint with a data \
            protection supervisory authority, in particular the \
            Hessian Commissioner for Data Protection and Freedom of \
            Information, Gustav-Stresemann-Ring 1, 65189 Wiesbaden, \
            poststelle@datenschutz.hessen.de.
            """)
        }
    }

    private var section8NoAutomated: some View {
        sectionBlock(title: "8. Keine automatisierte Einzelentscheidung / No Automated Decision-Making") {
            paragraph("""
            Eine automatisierte Entscheidungsfindung einschließlich \
            Profiling im Sinne des Art. 22 DSGVO findet nicht statt. \
            KI-generierte Textvorschläge sind Entscheidungsvorschläge \
            des Nutzers; die Entscheidung über ihre Verwendung trifft \
            stets der Nutzer.
            """)
            paragraph("""
            No automated decision-making, including profiling within \
            the meaning of Art. 22 GDPR, takes place. AI-generated \
            text suggestions are proposals; the decision to use them \
            always rests with the User.
            """)
        }
    }

    private var section9Necessity: some View {
        sectionBlock(title: "9. Erforderlichkeit der Bereitstellung / Necessity of Provision") {
            paragraph("""
            Die Bereitstellung personenbezogener Daten ist weder \
            gesetzlich noch vertraglich vorgeschrieben. Ohne die \
            Verarbeitung der eingegebenen Klauseltexte bzw. Bilder \
            kann die KI-Funktionalität der App jedoch nicht erbracht \
            werden.
            """)
            paragraph("""
            Provision of personal data is neither legally nor \
            contractually required. Without processing of the entered \
            clause text or images, however, the App's AI functionality \
            cannot be delivered.
            """)
        }
    }

    private var section10Changes: some View {
        sectionBlock(title: "10. Änderungen dieser Erklärung / Changes to this Policy") {
            paragraph("""
            Wir behalten uns vor, diese Datenschutzerklärung \
            anzupassen, wenn Änderungen an der App oder an der \
            Rechtslage dies erfordern. Die jeweils aktuelle Fassung \
            ist in der App und unter dem oben genannten Link abrufbar.
            """)
            paragraph("""
            We reserve the right to amend this Privacy Policy if \
            changes to the App or the applicable law so require. The \
            current version is available within the App and at the \
            link above.
            """)
        }
    }

    private var section11VersionHistory: some View {
        sectionBlock(title: "11. Versionshistorie / Version History") {
            bulletPoint("Version 2.1 — 4. Mai 2026: Optionale lokale Memory-Funktion hinzugefügt (drei manuelle Speicherplätze plus optionaler Auto-Speicher). Klausel- und Bildinhalte sind weiterhin standardmäßig nicht persistent. Keine Übertragung an Anthropic, Apple oder andere Dritte über die regulären API-Aufrufe hinaus.")
            bulletPoint("Version 2.0 — 14. April 2026: Grundlegende Neufassung. Aufnahme aller tatsächlichen Datenflüsse (Track-Changes-Vision, „Tell Me\u{201C}-Analyse, BYOK-Schlüssel, lokale Protokolle, UserDefaults, Keychain); Ergänzung von Rechtsgrundlagen, Empfängern, Drittlandübermittlung (SCC statt DPF), Speicherdauern, Betroffenenrechten und Beschwerderecht.")
            bulletPoint("Version 1.x — bis 13. April 2026: Vorgängerfassung mit Kurzbeschreibung und Verweis auf Anthropic und Apple.")

            bulletPoint("Version 2.1 — 4 May 2026: Added optional local Memory feature (three manual slots plus an optional auto-save slot). Clause and image content remain non-persistent by default. No transmission to Anthropic, Apple, or other third parties beyond the regular API calls.")
            bulletPoint("Version 2.0 — 14 April 2026: Substantive rewrite. Addition of all actual data flows (Track Changes Vision, \"Tell Me\" analysis, BYOK key, local logs, UserDefaults, Keychain); legal bases, recipients, third-country transfers (SCCs instead of DPF), retention periods, data subject rights, and complaint right.")
            bulletPoint("Version 1.x — until 13 April 2026: Predecessor version with short description and reference to Anthropic and Apple.")
        }
    }

    private var sectionContact: some View {
        sectionBlock(title: "Kontakt / Contact") {
            paragraph("""
            Für alle Datenschutzanfragen / For all data protection \
            enquiries: support@medienkommission.de
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

    private func subHeader(_ text: String) -> some View {
        Text(text)
            .font(.dkBody.weight(.medium))
            .foregroundColor(.dkTextPrimary)
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

    private func linkRow(_ label: String, url: String) -> some View {
        Link(label, destination: URL(string: url)!)
            .font(.dkCaption)
            .foregroundColor(.dkPrimary)
    }
}
