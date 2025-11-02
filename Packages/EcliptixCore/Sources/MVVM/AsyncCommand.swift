import Combine
import Foundation

@MainActor
public protocol AsyncCommand {

    var canExecute: Bool { get }

    var canExecutePublisher: AnyPublisher<Bool, Never> { get }

    var isExecuting: Bool { get }

    var isExecutingPublisher: AnyPublisher<Bool, Never> { get }

    var errorPublisher: AnyPublisher<Error, Never> { get }
}

@MainActor
public final class DefaultAsyncCommand<Input: Sendable, Output: Sendable>: AsyncCommand, ObservableObject {

    private let execute: @Sendable (Input) async throws -> Output
    private let canExecuteSubject: CurrentValueSubject<Bool, Never>
    private let isExecutingSubject = CurrentValueSubject<Bool, Never>(false)
    private let errorSubject = PassthroughSubject<Error, Never>()

    private var cancellables = Set<AnyCancellable>()
    private var currentTask: Task<Void, Never>?
    private var executionTask: Task<Void, Never>?

    @Published public private(set) var canExecute: Bool
    @Published public private(set) var isExecuting: Bool = false

    public init(
        canExecute: Bool = true,
        execute: @escaping @Sendable (Input) async throws -> Output
    ) {
        self.execute = execute
        self.canExecute = canExecute
        self.canExecuteSubject = CurrentValueSubject(canExecute)

        setupBindings()
    }

    public init(
        canExecute: AnyPublisher<Bool, Never>,
        execute: @escaping @Sendable (Input) async throws -> Output
    ) {
        self.execute = execute
        self.canExecute = true
        self.canExecuteSubject = CurrentValueSubject(true)

        setupBindings()

        canExecute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canExecute in
                self?.updateCanExecute(canExecute)
            }
            .store(in: &cancellables)
    }


    public var canExecutePublisher: AnyPublisher<Bool, Never> {
        canExecuteSubject.eraseToAnyPublisher()
    }

    public var isExecutingPublisher: AnyPublisher<Bool, Never> {
        isExecutingSubject.eraseToAnyPublisher()
    }

    public var errorPublisher: AnyPublisher<Error, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    @discardableResult
    public func execute(with input: Input) async -> Result<Output, Error> {
        guard canExecute && !isExecuting else {
            Log.warning("[AsyncCommand] Cannot execute - canExecute: \(canExecute), isExecuting: \(isExecuting)")
            return .failure(AsyncCommandError.cannotExecute)
        }

        updateIsExecuting(true)

        let execTask = Task<Result<Output, Error>, Never> { @Sendable in
            do {
                let result = try await execute(input)
                return .success(result)
            } catch {
                return .failure(error)
            }
        }

        executionTask = Task { @Sendable in
            _ = await execTask.value
        }

        currentTask = Task { @MainActor in
            let result = await execTask.value
            self.handleExecutionResult(result)
        }

        return await execTask.value
    }

    @discardableResult
    public func execute() async -> Result<Output, Error> where Input == Void {
        return await execute(with: ())
    }

    public func cancel() {
        executionTask?.cancel()
        executionTask = nil
        currentTask?.cancel()
        currentTask = nil
        updateIsExecuting(false)
    }

    public func updateCanExecute(_ value: Bool) {
        canExecute = value
        canExecuteSubject.send(value)
    }

    private func setupBindings() {
        canExecuteSubject
            .receive(on: DispatchQueue.main)
            .assign(to: &$canExecute)

        isExecutingSubject
            .receive(on: DispatchQueue.main)
            .assign(to: &$isExecuting)

        isExecutingSubject
            .sink { [weak self] isExecuting in
                guard let self = self else { return }
                if isExecuting && self.canExecute {
                    self.canExecuteSubject.send(false)
                }
            }
            .store(in: &cancellables)
    }

    private func updateIsExecuting(_ value: Bool) {
        isExecuting = value
        isExecutingSubject.send(value)

        if !value {
            canExecuteSubject.send(canExecute)
        }
    }

    private func handleExecutionResult(_ result: Result<Output, Error>) {
        updateIsExecuting(false)

        if case .failure(let error) = result {
            Log.error("[AsyncCommand] Execution failed: \(error.localizedDescription)")
            errorSubject.send(error)
        }
    }
}

public enum AsyncCommandError: Error, LocalizedError {
    case cannotExecute
    case cancelled
    case executionFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .cannotExecute:
            return "Command cannot be executed at this time"
        case .cancelled:
            return "Command execution was cancelled"
        case .executionFailed(let error):
            return "Command execution failed: \(error.localizedDescription)"
        }
    }
}

public extension DefaultAsyncCommand {

    static func create<T: Sendable>(
        canExecute: Bool = true,
        execute: @escaping @Sendable () async throws -> T
    ) -> DefaultAsyncCommand<Void, T> {
        return DefaultAsyncCommand<Void, T>(canExecute: canExecute) { _ in
            try await execute()
        }
    }

    static func create<T: Sendable>(
        canExecute: AnyPublisher<Bool, Never>,
        execute: @escaping @Sendable () async throws -> T
    ) -> DefaultAsyncCommand<Void, T> {
        return DefaultAsyncCommand<Void, T>(canExecute: canExecute) { _ in
            try await execute()
        }
    }

    static func createVoid<T: Sendable>(
        canExecute: Bool = true,
        execute: @escaping @Sendable (T) async throws -> Void
    ) -> DefaultAsyncCommand<T, Void> {
        return DefaultAsyncCommand<T, Void>(canExecute: canExecute, execute: execute)
    }

    static func createAction(
        canExecute: Bool = true,
        execute: @escaping @Sendable () async throws -> Void
    ) -> DefaultAsyncCommand<Void, Void> {
        return DefaultAsyncCommand<Void, Void>(canExecute: canExecute) { _ in
            try await execute()
        }
    }

    static func createAction(
        canExecute: AnyPublisher<Bool, Never>,
        execute: @escaping @Sendable () async throws -> Void
    ) -> DefaultAsyncCommand<Void, Void> {
        return DefaultAsyncCommand<Void, Void>(canExecute: canExecute) { _ in
            try await execute()
        }
    }
}

public extension DefaultAsyncCommand {

    static func createConnectivityAware<V: ViewLifecycle>(
        lifecycle: V,
        execute: @escaping @Sendable (Input) async throws -> Output
    ) -> DefaultAsyncCommand<Input, Output> {
        let canExecute = lifecycle.offlinePublisher
            .map { !$0 }
            .eraseToAnyPublisher()

        return DefaultAsyncCommand(canExecute: canExecute, execute: execute)
    }

    static func createConnectivityAwareAction<V: ViewLifecycle>(
        lifecycle: V,
        execute: @escaping @Sendable () async throws -> Void
    ) -> DefaultAsyncCommand<Void, Void> {
        let canExecute = lifecycle.offlinePublisher
            .map { !$0 }
            .eraseToAnyPublisher()

        return DefaultAsyncCommand<Void, Void>(canExecute: canExecute) { _ in
            try await execute()
        }
    }
}

public extension DefaultAsyncCommand {

    static func combineCanExecute(
        _ publishers: AnyPublisher<Bool, Never>...
    ) -> AnyPublisher<Bool, Never> {
        guard !publishers.isEmpty else {
            return Just(true).eraseToAnyPublisher()
        }

        return publishers.dropFirst().reduce(publishers[0]) { combined, next in
            combined.combineLatest(next)
                .map { $0 && $1 }
                .eraseToAnyPublisher()
        }
    }

    static func combineCanExecute(
        _ first: AnyPublisher<Bool, Never>,
        _ second: AnyPublisher<Bool, Never>
    ) -> AnyPublisher<Bool, Never> {
        first.combineLatest(second)
            .map { $0 && $1 }
            .eraseToAnyPublisher()
    }
}
