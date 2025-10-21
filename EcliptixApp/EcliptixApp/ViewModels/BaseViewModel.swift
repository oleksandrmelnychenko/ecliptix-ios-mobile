import Foundation
import Combine
import EcliptixCore

// MARK: - View State
/// Common view states for ViewModels
public enum ViewState: Equatable {
    case idle
    case loading
    case success
    case error(String)

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var isError: Bool {
        if case .error = self { return true }
        return false
    }

    public var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}

// MARK: - Base ViewModel
/// Base class for all ViewModels with common functionality
/// Migrated from: Ecliptix.Core/MVVM/ViewModelBase.cs
open class BaseViewModel: ObservableObject {

    // MARK: - Properties
    @Published public var viewState: ViewState = .idle
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var hasError: Bool = false

    // Cancellables for Combine subscriptions
    protected var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    public init() {
        setupBindings()
    }

    // MARK: - Setup Bindings
    private func setupBindings() {
        // Bind viewState to individual properties
        $viewState
            .map { $0.isLoading }
            .assign(to: &$isLoading)

        $viewState
            .map { $0.errorMessage }
            .assign(to: &$errorMessage)

        $viewState
            .map { $0.isError }
            .assign(to: &$hasError)
    }

    // MARK: - State Management

    /// Sets the view to loading state
    @MainActor
    public func setLoading() {
        viewState = .loading
        Log.debug("[\(type(of: self))] State: Loading")
    }

    /// Sets the view to success state
    @MainActor
    public func setSuccess() {
        viewState = .success
        Log.debug("[\(type(of: self))] State: Success")
    }

    /// Sets the view to error state
    @MainActor
    public func setError(_ message: String) {
        viewState = .error(message)
        Log.error("[\(type(of: self))] State: Error - \(message)")
    }

    /// Resets the view to idle state
    @MainActor
    public func resetState() {
        viewState = .idle
        Log.debug("[\(type(of: self))] State: Idle")
    }

    // MARK: - Error Handling

    /// Handles an error and updates the view state
    @MainActor
    public func handleError(_ error: Error) {
        let message = error.localizedDescription
        setError(message)
    }

    /// Handles a NetworkFailure and updates the view state
    @MainActor
    public func handleNetworkFailure(_ failure: NetworkFailure) {
        let userError = UserFacingError.from(failure)
        setError(userError.message)
    }

    // MARK: - Async Operations

    /// Executes an async operation with automatic state management
    @MainActor
    public func executeAsync<T>(
        _ operation: @escaping () async throws -> T,
        onSuccess: ((T) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        Task {
            setLoading()

            do {
                let result = try await operation()
                setSuccess()
                onSuccess?(result)
            } catch {
                handleError(error)
                onError?(error)
            }
        }
    }

    /// Executes an operation returning Result with automatic state management
    @MainActor
    public func executeWithResult<T, E: Error>(
        _ operation: @escaping () async -> Result<T, E>,
        onSuccess: ((T) -> Void)? = nil,
        onError: ((E) -> Void)? = nil
    ) {
        Task {
            setLoading()

            let result = await operation()

            switch result {
            case .success(let value):
                setSuccess()
                onSuccess?(value)

            case .failure(let error):
                handleError(error)
                onError?(error)
            }
        }
    }

    // MARK: - Validation

    /// Override in subclasses to provide validation logic
    open func validate() -> Bool {
        return true
    }

    // MARK: - Reset

    /// Override in subclasses to reset specific state
    open func reset() {
        resetState()
        errorMessage = nil
        hasError = false
    }
}

// MARK: - Form Field Error
/// Represents a validation error for a form field
public struct FormFieldError: Equatable {
    public let field: String
    public let message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

// MARK: - Validation Result
/// Result of form validation
public enum ValidationResult: Equatable {
    case valid
    case invalid([FormFieldError])

    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    public var errors: [FormFieldError] {
        if case .invalid(let errors) = self { return errors }
        return []
    }

    public func errorFor(field: String) -> String? {
        errors.first { $0.field == field }?.message
    }
}
