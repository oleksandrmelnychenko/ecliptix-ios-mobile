import Combine
import Foundation

public protocol ViewLifecycle: AnyObject {
    var isOffline: Bool { get }
    var offlinePublisher: AnyPublisher<Bool, Never> { get }

    func didAppear()
    func willDisappear()
    func connectivityRestored()
    func connectivityLost()
}

public extension ViewLifecycle {
    func didAppear() {}
    func willDisappear() {}
    func connectivityRestored() {}
    func connectivityLost() {}
}
