#if os(iOS)
import BrievieUI
import SwiftUI

/// The sheet of the workspace pill: every workspace as a large row (initial, name, kind and role), the current one
/// checked. Each workspace is a space of its own; no counts of other workspaces are shown here.
public struct WorkspacePickerSheet: View {
    private let model: WorkspacesModel

    public init(model: WorkspacesModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            WorkspacePickerList(
                rows: model.rows, currentWorkspaceID: model.currentWorkspaceID, choose: { model.choose($0) }
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        model.isShowingPicker = false
                    } label: {
                        Text("workspaces.picker.done", bundle: .module)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// The pill of the current workspace, for the top left of a screen: opens the picker when there is another
/// workspace. Nothing while no workspace is shown.
public struct WorkspacePillButton: View {
    private let model: WorkspacesModel

    public init(model: WorkspacesModel) {
        self.model = model
    }

    public var body: some View {
        if let row = model.currentRow {
            WorkspacePill(
                name: row.name, accessibilityLabel: model.pillAccessibilityLabel(for: row),
                action: model.canSwitch ? { model.showPicker() } : nil
            )
        }
    }
}

/// The rendering of the picker, free of the model so previews can feed it plain rows.
struct WorkspacePickerList: View {
    let rows: [WorkspacesModel.Row]
    let currentWorkspaceID: UUID?
    let choose: (UUID) -> Void

    var body: some View {
        List {
            Section {
                ForEach(rows) { row in
                    rowButton(row)
                }
            } footer: {
                Text("workspaces.picker.footer", bundle: .module)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("workspaces.picker.title", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rowButton(_ row: WorkspacesModel.Row) -> some View {
        let isCurrent = row.id == currentWorkspaceID
        return Button {
            choose(row.id)
        } label: {
            HStack(spacing: 12) {
                WorkspaceInitial(name: row.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.headline)
                    Text(row.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 6)
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityHint(isCurrent ? Text(verbatim: "") : Text("settings.workspace.hint", bundle: .module))
    }
}

/// A workspace's initial in a brand-coloured circle, as in the pill.
private struct WorkspaceInitial: View {
    let name: String
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 44

    var body: some View {
        Text(WorkspacePill.initial(of: name))
            .font(.title3.weight(.bold))
            .foregroundStyle(BrievieColor.onBrand)
            .frame(width: size, height: size)
            .background(BrievieColor.brand, in: Circle())
            .accessibilityHidden(true)
    }
}

#if DEBUG
private let previewCurrent = UUID()
private var previewRows: [WorkspacesModel.Row] {
    [
        WorkspacesModel.Row(
            id: previewCurrent, name: "Thuis", kind: .home, kindLabel: WorkspaceStrings.kindHome,
            roleLabel: WorkspaceStrings.roleAdmin
        ),
        WorkspacesModel.Row(
            id: UUID(), name: "Bedrijf", kind: .business, kindLabel: WorkspaceStrings.kindBusiness,
            roleLabel: WorkspaceStrings.roleMember
        )
    ]
}

#Preview("Light") {
    NavigationStack { WorkspacePickerList(rows: previewRows, currentWorkspaceID: previewCurrent, choose: { _ in }) }
        .tint(BrievieColor.brand)
}

#Preview("Dark") {
    NavigationStack { WorkspacePickerList(rows: previewRows, currentWorkspaceID: previewCurrent, choose: { _ in }) }
        .tint(BrievieColor.brand)
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    NavigationStack { WorkspacePickerList(rows: previewRows, currentWorkspaceID: previewCurrent, choose: { _ in }) }
        .tint(BrievieColor.brand)
        .dynamicTypeSize(.accessibility5)
}
#endif
#endif
