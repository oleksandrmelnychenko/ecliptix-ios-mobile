import Combine
import Foundation
import Combine


public protocol Message: Sendable {
    var messageId: UUID { get }
    var timestamp: Date { get }
}

public protocol MessageRequest: Message {
    var correlationId: UUID { get }
    var timeout: TimeInterval { get }
}

public protocol MessageResponse: Message {
    var correlationId: UUID { get }
    var requestId: UUID { get }
}


public enum SubscriptionLifetime {
    case strong

    case scoped

    case weak
}


public protocol MessageBusProtocol: Actor {

    func publish<T: Message>(_ message: T) async

    func subscribe<T: Message>(
        lifetime: SubscriptionLifetime,
        handler: @escaping @Sendable (T) async -> Void
    ) -> AnyCancellable

    func subscribe<T: Message>(
        filter: @escaping @Sendable (T) -> Bool,
        lifetime: SubscriptionLifetime,
        handler: @escaping @Sendable (T) async -> Void
    ) -> AnyCancellable

    func request<TRequest: MessageRequest, TResponse: MessageResponse>(
        _ request: TRequest,
        timeout: TimeInterval
    ) async throws -> TResponse
}


public actor MessageBus: MessageBusProtocol {


    private class SubjectWrapper<T: Message>: @unchecked Sendable {
        let subject: PassthroughSubject<T, Never>
        private var referenceCount: Int = 0
        private let queue = DispatchQueue(label: "SubjectWrapper", attributes: .concurrent)

        init() {
            self.subject = PassthroughSubject<T, Never>()
        }

        func incrementReference() {
            queue.async(flags: .barrier) {
                self.referenceCount += 1
            }
        }

        func decrementReference() {
            queue.async(flags: .barrier) {
                self.referenceCount -= 1
            }
        }

        var hasReferences: Bool {
            return queue.sync { referenceCount > 0 }
        }
    }


    private var subjects: [String: Any] = [:]
    private var pendingRequests: [UUID: Any] = [:]
    private var responseContinuations: [UUID: CheckedContinuation<Any, Error>] = [:]


    public init() {
        Log.info("[MessageBus] Initialized")
    }


    public func publish<T: Message>(_ message: T) async {
        let typeName = String(describing: T.self)

        Log.debug("[MessageBus] Publishing \(typeName) [ID: \(message.messageId)]")

        let wrapper = getOrCreateSubject(for: T.self)

        wrapper.subject.send(message)

        if let response = message as? MessageResponse {
            await handleResponse(response)
        }
    }


    public func subscribe<T: Message>(
        lifetime: SubscriptionLifetime = .strong,
        handler: @escaping @Sendable (T) async -> Void
    ) -> AnyCancellable {
        subscribe(filter: { _ in true }, lifetime: lifetime, handler: handler)
    }

    public func subscribe<T: Message>(
        filter: @escaping @Sendable (T) -> Bool,
        lifetime: SubscriptionLifetime = .strong,
        handler: @escaping @Sendable (T) async -> Void
    ) -> AnyCancellable {
        let typeName = String(describing: T.self)

        Log.debug("[MessageBus] Subscribing to \(typeName) [lifetime: \(lifetime)]")

        let wrapper = getOrCreateSubject(for: T.self)
        wrapper.incrementReference()

        let subscription = wrapper.subject
            .filter(filter)
            .sink { message in
                Task {
                    await handler(message)
                }
            }

        return AnyCancellable {
            subscription.cancel()
            wrapper.decrementReference()

            Task { [weak self] in
                await self?.cleanupSubjectIfNeeded(for: T.self)
            }
        }
    }


    public func request<TRequest: MessageRequest, TResponse: MessageResponse>(
        _ request: TRequest,
        timeout: TimeInterval = 30.0
    ) async throws -> TResponse {

        let requestId = request.messageId
        let correlationId = request.correlationId

        Log.debug("[MessageBus] Sending request [ID: \(requestId), Correlation: \(correlationId)]")

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TResponse, Error>) in
            Task { [weak self] in
                guard let self = self else { return }
                await self.storeContinuation(continuation, for: correlationId)

                await self.publish(request)

                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                    guard let self = self else { return }
                    if await self.hasPendingRequest(correlationId) {
                        Log.warning("[MessageBus] Request timed out [ID: \(requestId)]")
                        await self.removeContinuation(for: correlationId)
                        continuation.resume(throwing: MessageBusError.timeout)
                    }
                }
            }
        }
    }


    private func getOrCreateSubject<T: Message>(for type: T.Type) -> SubjectWrapper<T> {
        let typeName = String(describing: T.self)

        if let existing = subjects[typeName] as? SubjectWrapper<T> {
            return existing
        }

        let wrapper = SubjectWrapper<T>()
        subjects[typeName] = wrapper

        Log.debug("[MessageBus] Created subject for \(typeName)")
        return wrapper
    }

    private func cleanupSubjectIfNeeded<T: Message>(for type: T.Type) {
        let typeName = String(describing: T.self)

        if let wrapper = subjects[typeName] as? SubjectWrapper<T>, !wrapper.hasReferences {
            subjects.removeValue(forKey: typeName)
            Log.debug("[MessageBus] Cleaned up subject for \(typeName)")
        }
    }

    private func handleResponse<T: MessageResponse>(_ response: T) async {
        let correlationId = response.correlationId

        Log.debug("[MessageBus] Received response [Correlation: \(correlationId)]")

        if let continuation = responseContinuations[correlationId] {
            responseContinuations.removeValue(forKey: correlationId)
            pendingRequests.removeValue(forKey: correlationId)

            continuation.resume(returning: response as Any)
            Log.debug("[MessageBus] Resumed continuation for [Correlation: \(correlationId)]")
        }
    }

    private func storeContinuation<T>(_ continuation: CheckedContinuation<T, Error>, for correlationId: UUID) {
        responseContinuations[correlationId] = continuation as? CheckedContinuation<Any, Error>
        pendingRequests[correlationId] = true
    }

    private func removeContinuation(for correlationId: UUID) {
        responseContinuations.removeValue(forKey: correlationId)
        pendingRequests.removeValue(forKey: correlationId)
    }

    private func hasPendingRequest(_ correlationId: UUID) -> Bool {
        return pendingRequests[correlationId] != nil
    }
}


public enum MessageBusError: Error {
    case timeout
    case invalidResponse
    case noSubscribers
}


public struct BaseMessage: Message {
    public let messageId: UUID
    public let timestamp: Date

    public init(messageId: UUID = UUID(), timestamp: Date = Date()) {
        self.messageId = messageId
        self.timestamp = timestamp
    }
}

public struct BaseRequest: MessageRequest {
    public let messageId: UUID
    public let timestamp: Date
    public let correlationId: UUID
    public let timeout: TimeInterval

    public init(
        messageId: UUID = UUID(),
        timestamp: Date = Date(),
        correlationId: UUID = UUID(),
        timeout: TimeInterval = 30.0
    ) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.correlationId = correlationId
        self.timeout = timeout
    }
}

public struct BaseResponse: MessageResponse {
    public let messageId: UUID
    public let timestamp: Date
    public let correlationId: UUID
    public let requestId: UUID

    public init(
        messageId: UUID = UUID(),
        timestamp: Date = Date(),
        correlationId: UUID,
        requestId: UUID
    ) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.correlationId = correlationId
        self.requestId = requestId
    }
}


public let GlobalMessageBus = MessageBus()
