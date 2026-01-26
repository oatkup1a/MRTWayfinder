import Combine
import Foundation

final class BeaconDriver: ObservableObject {
    enum Mode {
        case mock
        case real
    }

    @Published private(set) var mode: Mode = .mock

    private let mock = MockBeaconManager()
    private let real = BeaconManager()

    private(set) var source: any BeaconSource = MockBeaconManager() // dummy, replaced in init
    private var cancellables = Set<AnyCancellable>()

    // Public publisher for the active source
    var latestPublisher: AnyPublisher<[BeaconReading], Never> {
        switch mode {
        case .mock: return mock.latestPublisher
        case .real: return real.latestPublisher
        }
    }

    init(initialMode: Mode) {
        setMode(initialMode, startIfRunning: false)
    }

    func configureReal(registry: BeaconRegistry) {
        real.configure(beacons: registry)
    }

    func setMode(_ newMode: Mode, startIfRunning: Bool) {
        // stop both to avoid double streams
        mock.stop()
        real.stop()

        mode = newMode
        switch newMode {
        case .mock:
            source = mock
            if startIfRunning { mock.start() }
        case .real:
            source = real
            if startIfRunning { real.start() }
        }
    }

    func start() {
        switch mode {
        case .mock: mock.start()
        case .real: real.start()
        }
    }

    func stop() {
        mock.stop()
        real.stop()
    }
}
