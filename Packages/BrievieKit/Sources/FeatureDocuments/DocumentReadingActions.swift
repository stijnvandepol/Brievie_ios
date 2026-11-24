#if os(iOS)
import BrievieUI
import SwiftUI

/// Marking a letter read or unread by hand.
struct ReadingControls {
    var markRead: (UUID) -> Void
    var markUnread: (UUID) -> Void
}

/// "Gelezen" / "Ongelezen" as a swipe, a context menu and a VoiceOver action, where the list shows what is unread.
struct ReadingActions: ViewModifier {
    let row: DocumentsModel.Row
    let documentID: UUID
    let reading: ReadingControls?

    func body(content: Content) -> some View {
        if let reading {
            content
                .swipeActions(edge: .leading) {
                    if row.isUnread {
                        Button(DocumentStrings.swipeRead, systemImage: "envelope.open") { reading.markRead(documentID) }
                            .tint(BrievieColor.brand)
                    } else {
                        Button(DocumentStrings.swipeUnread, systemImage: "envelope.badge") {
                            reading.markUnread(documentID)
                        }
                        .tint(BrievieColor.brand)
                    }
                }
                .contextMenu {
                    if row.isUnread {
                        Button(DocumentStrings.markRead, systemImage: "envelope.open") { reading.markRead(documentID) }
                    } else {
                        Button(DocumentStrings.markUnread, systemImage: "envelope.badge") {
                            reading.markUnread(documentID)
                        }
                    }
                }
                .accessibilityAction(named: row.isUnread ? DocumentStrings.markRead : DocumentStrings.markUnread) {
                    if row.isUnread { reading.markRead(documentID) } else { reading.markUnread(documentID) }
                }
        } else {
            content
        }
    }
}
#endif
