import BrievieCore
import Foundation

/// The models of one workspace's screens, made together and dropped together on a workspace switch.
@MainActor
public struct WorkspaceScreens {
    public let tabs: WorkspaceTabsModel
    public let inbox: DocumentsModel
    public let myPost: DocumentsModel
    public let allPost: DocumentsModel
    public let tasks: MyTasksModel
    public let lingering: LingeringModel
    /// One scan flow per list: each pushes its preview on its own navigation stack.
    public let inboxScan: ScanFlowModel
    public let myPostScan: ScanFlowModel
    public let allPostScan: ScanFlowModel

    /// Makes every model of a workspace and ties them together: a list that loaded (or marked letters read) counts
    /// the menu again, "Zoeken" opens the search of "Alle post", and the lists offer "Gelezen" once the server
    /// said it keeps read marks.
    public init(
        documents: WorkspaceDocuments, uploads: any UploadQueue, canScan: Bool, camera: any ScanCameraAccess,
        openSettings: @escaping @MainActor () -> Void, onTasksChanged: @escaping @MainActor () -> Void,
        onRevoked: @escaping @MainActor () -> Void, onMissingPairing: @escaping @MainActor () -> Void
    ) {
        let tabs = WorkspaceTabsModel(documents: documents, onRevoked: onRevoked, onMissingPairing: onMissingPairing)
        func list(_ scope: DocumentsModel.Scope) -> DocumentsModel {
            let model = DocumentsModel(
                documents: documents, scope: scope, uploads: uploads, canScan: canScan, camera: camera,
                openSettings: openSettings, onRevoked: onRevoked, onMissingPairing: onMissingPairing
            )
            // A letter that goes to the trash or comes back takes its tasks along: the calendar and reminders follow.
            model.onTasksChanged = onTasksChanged
            model.onListChanged = { [weak model, weak tabs] in
                guard let model, let tabs else { return }
                if model.hasTrash { tabs.hasTrash = true }
                Task { await tabs.refreshCounts() }
            }
            return model
        }
        let inbox = list(.inbox)
        let myPost = list(.myPost)
        let allPost = list(.all)
        tabs.onSearch = { [weak allPost] in allPost?.isSearchPresented = true }
        tabs.onReadingSupport = { [weak myPost, weak allPost] supported in
            myPost?.tracksReading = supported
            allPost?.tracksReading = supported
        }
        self.tabs = tabs
        self.inbox = inbox
        self.myPost = myPost
        self.allPost = allPost
        tasks = inbox.makeMyTasksModel { [weak tabs] in tabs?.showInbox() }
        lingering = LingeringModel(
            documents: documents, persons: { [weak inbox] in inbox?.persons ?? [] },
            labels: { [weak inbox] in inbox?.labels ?? [] }, onRevoked: onRevoked, onMissingPairing: onMissingPairing
        )
        inboxScan = ScanFlowModel(workspaceID: documents.workspaceID, uploads: uploads)
        myPostScan = ScanFlowModel(workspaceID: documents.workspaceID, uploads: uploads)
        allPostScan = ScanFlowModel(workspaceID: documents.workspaceID, uploads: uploads)
    }
}
