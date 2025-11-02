import Foundation
import Combine

@MainActor
protocol ViewLifecycle: AnyObject {
    var isOffline: Bool { get }
    var offlinePublisher: AnyPublisher<Bool, Never> { get }
    
    func didAppear()
    func willDisappear()
}

extension ViewLifecycle {
    func didAppear() {}
    func willDisappear() {}
}
