import Darwin
import Foundation

/// Pseudo-terminal plumbing shared by the tests that need the binary to see an
/// interactive terminal (`isatty` true) on one of its standard streams.
enum PTYSupport {
	struct PTY {
		/// Parent-side end; read from it to capture what the child writes.
		let master: Int32
		/// Child-side end; hand it to `Process.standardOutput`/`standardError`.
		let slave: Int32
	}

	/// Open a master/slave pty pair. The caller owns both descriptors.
	static func open() throws -> PTY {
		let master = posix_openpt(O_RDWR | O_NOCTTY)
		guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
			let namePointer = ptsname(master)
		else {
			if master >= 0 { close(master) }
			throw NSError(domain: "pty", code: Int(errno))
		}
		let slaveName = String(cString: namePointer)
		let slave = Darwin.open(slaveName, O_RDWR | O_NOCTTY)
		guard slave >= 0 else {
			close(master)
			throw NSError(domain: "pty-slave", code: Int(errno))
		}
		return PTY(master: master, slave: slave)
	}
}
