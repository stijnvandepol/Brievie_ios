#if os(iOS)
import BrievieUI
import SwiftUI

/// "Blijft liggen": two groups of letters, each with how long it lies there; a letter opens its screen.
public struct LingeringView<Destination: View>: View {
    private let model: LingeringModel
    private let destination: (UUID) -> Destination

    public init(model: LingeringModel, @ViewBuilder destination: @escaping (UUID) -> Destination) {
        self.model = model
        self.destination = destination
    }

    public var body: some View {
        List {
            switch model.state {
            case .loading:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(DocumentStrings.loading)
                    }
                    .accessibilityElement(children: .combine)
                }
            case let .failed(message):
                Section {
                    ErrorBanner(message, actionTitle: DocumentStrings.retry) { Task { await model.load() } }
                }
            case .loaded:
                if model.isEmpty {
                    Section { Text(DocumentStrings.lingeringEmpty).foregroundStyle(.secondary) }
                }
                ForEach(model.groups) { group in
                    Section {
                        ForEach(group.rows) { item in
                            if let documentID = item.row.documentID {
                                NavigationLink {
                                    destination(documentID)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        DocumentRowView(row: item.row)
                                        Text(item.age)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(BrievieColor.warning)
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(item.accessibilityLabel)
                                }
                            }
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(DocumentStrings.lingeringTitle)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.load() }
        .task { await model.load() }
    }
}
#endif
