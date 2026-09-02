import Darwin
import Foundation

/// Process-wide advisory lock. It is released automatically by the kernel when
/// the app exits, including after a crash, so a stale file cannot block launch.
final class SingleInstanceLock {
    private let fileDescriptor: Int32

    convenience init?() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("app.macpulse.MacPulse.instance.lock")
        self.init(lockFileURL: url)
    }

    init?(lockFileURL: URL) {
        let descriptor = open(lockFileURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        fileDescriptor = descriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}
