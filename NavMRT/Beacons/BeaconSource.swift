import Combine

protocol BeaconSource: AnyObject {
    var latestPublisher: AnyPublisher<[BeaconReading], Never> { get }
    var isRunning: Bool { get }
    func start()
    func stop()
}
