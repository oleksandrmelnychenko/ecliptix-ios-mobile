import Combine
import EcliptixCore
import Foundation
import Observation

public enum ApplicationState: Equatable {
    case initializing
    case anonymous
    case authenticated(membershipId: String)
}

@MainActor
@Observable
public final class ApplicationStateManager {

    public private(set) var currentState: ApplicationState = .initializing

    public var currentMembershipId: String? {
        switch currentState {
        case .authenticated(let membershipId):
            return membershipId
        default:
            return nil
        }
    }

    private let stateSubject = PassthroughSubject<ApplicationState, Never>()

    public var stateChanges: AnyPublisher<ApplicationState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    public init() {
        Log.debug("[ApplicationStateManager] Initialized in Initializing state")
    }

    public func transitionToAnonymous() async {
        Log.info("[ApplicationStateManager] Transitioning to Anonymous state")
        currentState = .anonymous
        stateSubject.send(.anonymous)
    }

    public func transitionToAuthenticated(membershipId: String) async throws {
        guard !membershipId.isEmpty else {
            let error = ApplicationStateError.invalidMembershipId("Membership ID cannot be empty")
            Log.error("[ApplicationStateManager] \(error.localizedDescription)")
            throw error
        }

        Log.info("[ApplicationStateManager] Transitioning to Authenticated state. MembershipId: \(membershipId)")
        currentState = .authenticated(membershipId: membershipId)
        stateSubject.send(.authenticated(membershipId: membershipId))
    }

    public func reset() async {
        Log.info("[ApplicationStateManager] Resetting to Initializing state")
        currentState = .initializing
        stateSubject.send(.initializing)
    }

    public var isAnonymous: Bool {
        if case .anonymous = currentState {
            return true
        }
        return false
    }

    public var isAuthenticated: Bool {
        if case .authenticated = currentState {
            return true
        }
        return false
    }

    public var isInitializing: Bool {
        if case .initializing = currentState {
            return true
        }
        return false
    }
}

public enum ApplicationStateError: LocalizedError {
    case invalidMembershipId(String)
    case invalidStateTransition(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMembershipId(let message),
             .invalidStateTransition(let message):
            return message
        }
    }
}

public extension ApplicationState {

    var message: String {
        switch self {
        case .initializing:
            return "Initializing"
        case .anonymous:
            return "Anonymous"
        case .authenticated(let membershipId):
            return "Authenticated (ID: \(membershipId))"
        }
    }

    var canAccessMainContent: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }

    var requiresAuthentication: Bool {
        switch self {
        case .initializing, .anonymous:
            return true
        case .authenticated:
            return false
        }
    }
}
