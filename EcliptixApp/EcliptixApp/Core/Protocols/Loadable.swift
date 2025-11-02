import Foundation

enum LoadingState: Equatable {
    case idle
    case loading
    case loaded
    case failed(Error)

    static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var error: Error? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

protocol Loadable: AnyObject, ObservableObject {
    var state: LoadingState { get set }
}

extension Loadable {
    var isLoading: Bool { state.isLoading }
    var error: Error? { state.error }

    @MainActor
    func perform<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        state = .loading

        do {
            let value = try await operation()
            state = .loaded
            return .success(value)
        } catch {
            state = .failed(error)
            return .failure(error)
        }
    }

    @MainActor
    func reset() {
        state = .idle
    }
}
