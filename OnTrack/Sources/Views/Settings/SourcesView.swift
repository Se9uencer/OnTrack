import SwiftUI

/// Citations for the formulas behind daily calorie/macro targets (App Store
/// Guideline 1.4.1 requires easy-to-find sources for medical/health info).
struct SourcesView: View {
    private struct Citation: Identifiable {
        let id = UUID()
        let topic: String
        let title: String
        let journal: String
        let url: URL
    }

    private let citations: [Citation] = [
        Citation(topic: "Basal metabolic rate (Mifflin-St Jeor equation)",
                 title: "A new predictive equation for resting energy expenditure in healthy individuals",
                 journal: "Mifflin MD et al., Am J Clin Nutr, 1990",
                 url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/")!),
        Citation(topic: "Activity multipliers (TDEE)",
                 title: "Human Energy Requirements",
                 journal: "FAO/WHO/UNU",
                 url: URL(string: "https://www.fao.org/4/y5686e/y5686e00.htm")!),
        Citation(topic: "Weight-change rate (~500 kcal/day per lb/week)",
                 title: "Caloric equivalents of gained or lost weight",
                 journal: "Wishnofsky M, Am J Clin Nutr, 1958",
                 url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/13594881/")!),
        Citation(topic: "Protein target (1.8 g/kg)",
                 title: "ISSN Position Stand: Protein and Exercise",
                 journal: "Jäger R et al., JISSN, 2017",
                 url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/28642676/")!),
        Citation(topic: "Fat target (25% of calories, within 20-35% AMDR)",
                 title: "Dietary Reference Intakes for Energy, Carbohydrate, Fiber, Fat, Fatty Acids, Cholesterol, Protein, and Amino Acids",
                 journal: "Institute of Medicine",
                 url: URL(string: "https://www.nationalacademies.org/publications/10490")!),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(citations) { citation in
                    Link(destination: citation.url) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(citation.topic)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(citation.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text(citation.journal)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Research behind your targets")
            } footer: {
                Text("Your daily targets are general estimates based on published research, not medical advice. Consult a healthcare professional before changing your diet or exercise routine.")
            }
        }
        .navigationTitle("Sources")
    }
}
