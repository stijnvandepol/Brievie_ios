#if os(iOS)
import BrievieUI
import SwiftUI
import UIKit

/// A new scan, pushed on the post's navigation stack: which page is being read, then every page as it will
/// be uploaded, each with "Draai", and "Bewaren". Pushed, not a sheet: the paired app stays under the lock
/// screen, and a sheet would lie above it.
struct ScanFlowView: View {
    let model: ScanFlowModel
    @State private var asksDiscard = false

    var body: some View {
        content
            .navigationTitle(DocumentStrings.scanTitle)
            .navigationBarTitleDisplayMode(.inline)
            // Leaving goes through "Annuleren", which asks first once there are pages to lose.
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DocumentStrings.scanCancel) {
                        if model.phase == .reviewing { asksDiscard = true } else { model.discard() }
                    }
                    .disabled(model.phase == .saving)
                }
                if model.phase == .reviewing || model.phase == .saving {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(DocumentStrings.scanSave) { Task { await model.save() } }
                            .disabled(!model.canSave)
                    }
                }
            }
            .confirmationDialog(
                DocumentStrings.scanDiscardTitle, isPresented: $asksDiscard, titleVisibility: .visible
            ) {
                Button(DocumentStrings.scanDiscard, role: .destructive) { model.discard() }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case let .failed(message):
            VStack(spacing: 16) {
                ErrorBanner(message)
                PrimaryButton(DocumentStrings.scanClose) { model.reset() }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .reviewing, .saving:
            pages
        case .idle, .recognising, .finished:
            VStack(spacing: 16) {
                ProgressView()
                Text(model.phase.label)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var pages: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                Text(DocumentStrings.scanPreviewIntro)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(model.pages) { page in
                    ScanPreviewPage(page: page, total: model.pages.count, canTurn: model.canSave) {
                        Task { await model.turn(page: page.id) }
                    }
                }
                if model.phase == .saving {
                    ProgressView(DocumentStrings.scanSaving)
                }
            }
            .padding()
        }
    }
}

/// One page of the preview: exactly the pixels that will be uploaded, and its "Draai" button.
private struct ScanPreviewPage: View {
    let page: ScanFlowModel.Page
    let total: Int
    let canTurn: Bool
    let turn: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if let image = UIImage(data: page.preview) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 420)
                        .border(.separator)
                        .opacity(page.isTurning ? 0.4 : 1)
                }
                if page.isTurning {
                    ProgressView(DocumentStrings.scanTurning)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(imageLabel)
            .accessibilityAddTraits(.isImage)
            if page.turnedAutomatically {
                Label(DocumentStrings.scanTurnedAutomatically, systemImage: "rotate.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Button(action: turn) {
                Label(DocumentStrings.scanTurn, systemImage: "rotate.right")
            }
            .buttonStyle(.bordered)
            .disabled(!canTurn)
            .accessibilityLabel(String(format: DocumentStrings.scanTurnLabelFormat, page.id + 1))
            .accessibilityHint(DocumentStrings.scanTurnHint)
        }
    }

    private var imageLabel: String {
        var parts = [String(format: DocumentStrings.pageFormat, page.id + 1, total)]
        if page.turnedAutomatically { parts.append(DocumentStrings.scanTurnedAutomatically) }
        if page.isTurning { parts.append(DocumentStrings.scanTurning) }
        return parts.joined(separator: ". ")
    }
}
#endif
