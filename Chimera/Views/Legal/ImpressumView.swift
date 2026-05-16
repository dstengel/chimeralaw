// ImpressumView.swift
// Chimera Law
// Impressum -- compliant with DDG (Digitale-Dienste-Gesetz), MStV, and VSBG
// Bilingual: German (legally binding) and English (courtesy translation)

import SwiftUI

struct ImpressumView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Text("Impressum / Legal Notice")
                    .font(.dkHeadline)
                    .foregroundColor(.dkPrimary)

                // Provider
                sectionBlock(title: "Angaben gemäß § 5 DDG / Information pursuant to § 5 DDG") {
                    Text("Daniel Stengel-Dori")
                        .font(.dkBody.weight(.medium))
                    Text("Ostendstr. 88")
                    Text("60314 Frankfurt am Main")
                    Text("Germany / Deutschland")
                }

                // Contact
                sectionBlock(title: "Kontakt / Contact") {
                    Text("E-Mail: support@medienkommission.de")
                    Link(destination: URL(string: "tel:+496920022574")!) {
                        Text("Tel.: +49\u{00A0}\u{00B7}\u{00A0}69\u{00A0}\u{00B7}\u{00A0}20022574")
                    }
                    .foregroundColor(.dkPrimary)
                }

                // VAT
                sectionBlock(title: "Umsatzsteuer / VAT") {
                    paragraph("""
                    Umsatzsteuer-Identifikationsnummer gemäß § 27a UStG: \
                    nicht vorhanden. Es wird die Kleinunternehmerregelung \
                    gemäß § 19 UStG angewendet.
                    """)
                    paragraph("""
                    VAT identification number pursuant to § 27a UStG: \
                    not available. The small business exemption under \
                    § 19 UStG applies.
                    """)
                }

                // Editorial responsibility
                sectionBlock(title: "Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV / Responsible for content pursuant to § 18(2) MStV") {
                    Text("Daniel Stengel-Dori")
                    Text("Ostendstr. 88")
                    Text("60314 Frankfurt am Main")
                }

                // Dispute resolution
                sectionBlock(title: "Streitschlichtung / Dispute Resolution") {
                    paragraph("""
                    Die Europäische Kommission stellt eine Plattform zur \
                    Online-Streitbeilegung (OS) bereit:
                    """)
                    paragraph("""
                    The European Commission provides a platform for online \
                    dispute resolution (ODR):
                    """)
                    Link("https://ec.europa.eu/consumers/odr/",
                         destination: URL(string: "https://ec.europa.eu/consumers/odr/")!)
                        .font(.dkCaption)
                        .foregroundColor(.dkPrimary)
                    paragraph("E-Mail: support@medienkommission.de")
                    paragraph("""
                    Wir sind nicht bereit oder verpflichtet, an \
                    Streitbeilegungsverfahren vor einer \
                    Verbraucherschlichtungsstelle teilzunehmen \
                    (§ 36 VSBG).
                    """)
                    paragraph("""
                    We are neither obligated nor willing to participate in \
                    dispute resolution proceedings before a consumer \
                    arbitration board (§ 36 VSBG).
                    """)
                }

                // Liability for content
                sectionBlock(title: "Haftung für Inhalte / Liability for Content") {
                    paragraph("""
                    Als Diensteanbieter sind wir gemäß § 7 Abs. 1 DDG für \
                    eigene Inhalte in dieser App nach den allgemeinen Gesetzen \
                    verantwortlich. Nach §§ 8 bis 10 DDG sind wir als \
                    Diensteanbieter jedoch nicht verpflichtet, übermittelte oder \
                    gespeicherte fremde Informationen zu überwachen oder nach \
                    Umständen zu forschen, die auf eine rechtswidrige Tätigkeit \
                    hinweisen. Verpflichtungen zur Entfernung oder Sperrung der \
                    Nutzung von Informationen nach den allgemeinen Gesetzen \
                    bleiben hiervon unberührt.
                    """)
                    paragraph("""
                    As a service provider, we are responsible for our own \
                    content in this app in accordance with § 7(1) DDG and \
                    general law. However, pursuant to §§ 8–10 DDG, we are \
                    not obligated to monitor transmitted or stored third-party \
                    information or to investigate circumstances indicating \
                    unlawful activity. Obligations to remove or block the use \
                    of information under general law remain unaffected.
                    """)
                }

                // Liability for links
                sectionBlock(title: "Haftung für Links / Liability for Links") {
                    paragraph("""
                    Diese App enthält Verknüpfungen zu externen Webseiten \
                    Dritter, auf deren Inhalte wir keinen Einfluss haben. \
                    Deshalb können wir für diese fremden Inhalte auch keine \
                    Gewähr übernehmen. Für die Inhalte der verlinkten Seiten ist \
                    stets der jeweilige Anbieter oder Betreiber der Seiten \
                    verantwortlich. Die verlinkten Seiten wurden zum Zeitpunkt \
                    der Verlinkung auf mögliche Rechtsverstöße überprüft. \
                    Rechtswidrige Inhalte waren zum Zeitpunkt der Verlinkung \
                    nicht erkennbar. Eine permanente inhaltliche Kontrolle der \
                    verlinkten Seiten ist jedoch ohne konkrete Anhaltspunkte \
                    einer Rechtsverletzung nicht zumutbar. Bei Bekanntwerden \
                    von Rechtsverletzungen werden wir derartige Links umgehend \
                    entfernen.
                    """)
                    paragraph("""
                    This app contains links to external third-party websites \
                    over whose content we have no influence. We therefore \
                    cannot accept any liability for such external content. \
                    The respective provider or operator is always responsible \
                    for the content of linked pages. Linked pages were checked \
                    for possible legal violations at the time of linking. No \
                    illegal content was identifiable at that time. Permanent \
                    monitoring of linked pages is unreasonable without concrete \
                    evidence of a legal violation. Upon notification of \
                    violations, we will remove such links immediately.
                    """)
                }

                // Copyright
                sectionBlock(title: "Urheberrecht / Copyright") {
                    paragraph("""
                    Die durch den Betreiber dieser App erstellten Inhalte und \
                    Werke unterliegen dem deutschen Urheberrecht. Die \
                    Vervielfältigung, Bearbeitung, Verbreitung und jede Art \
                    der Verwertung außerhalb der Grenzen des Urheberrechtes \
                    bedürfen der schriftlichen Zustimmung des jeweiligen Autors \
                    bzw. Erstellers. Downloads und Kopien dieser App sind nur \
                    für den privaten, nicht kommerziellen Gebrauch gestattet.
                    """)
                    paragraph("""
                    The content and works created by the operator of this app \
                    are subject to German copyright law. Reproduction, editing, \
                    distribution, and any form of exploitation beyond the limits \
                    of copyright law require the written consent of the \
                    respective author or creator. Downloads and copies of this \
                    app are permitted only for private, non-commercial use.
                    """)
                }
            }
            .padding(DKLayout.screenPadding)
        }
        .navigationTitle("Impressum")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionBlock(
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.dkSubheadline)
                .foregroundColor(.dkPrimary)
            content()
                .font(.dkBody)
                .foregroundColor(.dkTextPrimary)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.dkBody)
            .foregroundColor(.dkTextPrimary)
    }
}
