import Combine
import Foundation

final class BeaconDriver: ObservableObject {
    enum Mode {
        case mock
        case real
    }

    @Published private(set) var mode: Mode

    private let mock = MockBeaconManager()
    private let real = BeaconManager()

    private var realConfigured = false

    private let subject = CurrentValueSubject<[BeaconReading], Never>([])
    private var forwardingCancellable: AnyCancellable?

    /// Stable publisher: subscribers keep receiving updates even when mode changes.
    var latestPublisher: AnyPublisher<[BeaconReading], Never> {
        subject.eraseToAnyPublisher()
    }

    init(initialMode: Mode) {
        self.mode = initialMode
        attachForwarder(for: initialMode)
    }

    func configureReal(registry: BeaconRegistry) {
        real.configure(beacons: registry)
        realConfigured = true
    }

    func setMode(_ newMode: Mode, startIfRunning: Bool) {
        // stop both to avoid double streams
        mock.stop()
        real.stop()

        mode = newMode
        attachForwarder(for: newMode)

        if startIfRunning {
            start()
        } else {
            // ensure UI clears immediately on mode change when not running
            subject.send([])
        }
    }

    func start() {
        switch mode {
        case .mock:
            mock.start()
        case .real:
            guard realConfigured else {
                subject.send([])
                return
            }
            
            real.start()
        }
    }

    func stop() {
        mock.stop()
        real.stop()
        subject.send([])
    }

    // MARK: - Private

    private func attachForwarder(for mode: Mode) {
        forwardingCancellable?.cancel()

        let upstream: AnyPublisher<[BeaconReading], Never> = {
            switch mode {
            case .mock: return mock.latestPublisher
            case .real: return real.latestPublisher
            }
        }()

        // Forward upstream into a stable subject
        forwardingCancellable =
            upstream
            .receive(on: RunLoop.main)  // guarantee main-thread delivery to UI
            .sink { [weak self] readings in
                self?.subject.send(readings)
            }
    }
}
