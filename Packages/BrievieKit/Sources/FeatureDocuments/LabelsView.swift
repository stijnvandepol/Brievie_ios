#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// The workspace's labels; a label opens the letters that carry it (`WorkspaceTabsModel.Place.label`).
struct LabelsView: View {
    let model: LabelsModel
    let open: (UUID) -> Void

    var body: some View {
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
                Section {
                    if model.labels.isEmpty {
                        Text(DocumentStrings.labelsEmpty)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.labels) { label in
                        Button {
                            open(label.id)
                        } label: {
                            HStack {
                                LabelChip(name: label.name, colorKey: label.colorKey)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(label.name)
                        .accessibilityAddTraits(.isButton)
                    }
                } footer: {
                    Text(DocumentStrings.labelsFooter)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(DocumentStrings.labelsTitle)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.load() }
        .task { await model.load() }
    }
}

/// The letters of one label, with their model made once per visit.
struct LabelPostScreen<Destination: View, Compare: View>: View {
    @State private var model: DocumentsModel
    @State private var scanModel: ScanFlowModel
    private let destination: (UUID, DocumentsModel) -> Destination
    private let compare: (UUID, DocumentsModel) -> Compare

    init(
        label: UUID, from list: DocumentsModel, destination: @escaping (UUID, DocumentsModel) -> Destination,
        compare: @escaping (UUID, DocumentsModel) -> Compare
    ) {
        let model = list.makeLabelModel(label)
        _model = State(initialValue: model)
        _scanModel = State(initialValue: ScanFlowModel(workspaceID: list.workspaceID, uploads: list.uploads))
        self.destination = destination
        self.compare = compare
    }

    var body: some View {
        DocumentsView(
            model: model, scanModel: scanModel,
            destination: { id in destination(id, model) }, compare: { id in compare(id, model) }
        )
    }
}
#endif
