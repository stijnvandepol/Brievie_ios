import BrievieCore
import Foundation

extension DocumentsModel {
    /// Where the rows of a scope come from: the three inbox lists, or one list.
    enum Source: Equatable {
        case inbox
        case list(DocumentFilter)
    }

    /// The most letters the server sends in one list (the newest ones).
    static let listLimit = 200

    /// The inbox states in the order of their groups.
    static let inboxStates: [InboxState] = [.review, .unassigned, .new]

    /// What a letter on the server needs. A read letter on nobody's name says "Naam kiezen" in every scope, as
    /// in the web: "Klaar" only when nothing waits.
    static func status(of document: DocumentSummary) -> RowStatus {
        switch document.status {
        case .processing: .processing
        case .needsReview: .needsReview
        case .failed: .failed
        // A status this app does not know yet is at least a document that can be opened.
        case .done, .unknown: document.inboxState == .unassigned ? .needsName : .done
        }
    }

    static func source(for scope: Scope) -> Source {
        switch scope {
        case .inbox: .inbox
        case .myPost: .list(.myPost)
        case .myPostUnread: .list(DocumentFilter(addressedToMe: true, unreadOnly: true))
        case .all: .list(.all)
        case let .person(id): .list(DocumentFilter(personID: id))
        case let .label(id): .list(DocumentFilter(labelID: id))
        }
    }

    /// What the server said about some of the inbox states.
    struct InboxAnswer: Sendable {
        /// Per state, only the letters that are in that state.
        var lists: [InboxState: [DocumentSummary]] = [:]
        /// Per state, how many letters the server sent before they were sorted out.
        var fetched: [InboxState: Int] = [:]
        /// `nil` when the counts were not asked for or could not be read (a 1b server has none).
        var counts: InboxCounts?
    }

    /// The lists of `states` side by side, and the counts when `withCounts`. A 1b server ignores the filter and
    /// sends everything, so each list keeps only the letters in its own (derived) state. A failing count is
    /// not an error; a failing list is.
    nonisolated static func fetchInbox(
        _ states: [InboxState], withCounts: Bool, from documents: WorkspaceDocuments
    ) async throws(DocumentsError) -> InboxAnswer {
        async let counts = withCounts ? try? documents.inboxCounts() : nil
        let results = await withTaskGroup(of: (InboxState, Result<[DocumentSummary], DocumentsError>).self) { group in
            for state in states {
                group.addTask {
                    do throws(DocumentsError) {
                        return (state, .success(try await documents.list(filter: DocumentFilter(inboxState: state))))
                    } catch {
                        return (state, .failure(error))
                    }
                }
            }
            var results: [InboxState: Result<[DocumentSummary], DocumentsError>] = [:]
            for await (state, result) in group { results[state] = result }
            return results
        }
        var answer = InboxAnswer(counts: await counts)
        for state in states {
            guard let result = results[state] else { continue }
            let listed = try result.get()
            answer.fetched[state] = listed.count
            answer.lists[state] = listed.filter { $0.inboxState == state }
        }
        return answer
    }

    /// The number a group's header names. A list shorter than the server's limit holds every letter in that
    /// state; a full one may hold only the newest, and then the count says how many there are.
    static func total(fetched: Int, shown: Int, counted: Int?) -> Int {
        guard fetched >= listLimit, let counted else { return shown }
        return max(counted, shown)
    }
}
