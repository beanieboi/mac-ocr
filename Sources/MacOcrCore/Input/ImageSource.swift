import Foundation

/// Runtime discriminant + tagged JSON union shared with the result schema.
/// Buffer inputs from the Node wrapper reach the CLI via stdin and encode as
/// `{"type": "stdin"}`; the wrapper strips the `source` field entirely before
/// returning results to its caller.
///
/// `Sendable`: the three cases are immutable value-only metadata (strings or
/// no payload), so the type is trivially safe to share across actor boundaries.
public enum ImageSource: Encodable, Equatable, Sendable {
	case file(String)
	case url(String)
	case stdin

	public init(argument: String) {
		if argument == "-" {
			self = .stdin
		} else if isURLArgument(argument) {
			self = .url(argument)
		} else {
			self = .file(argument)
		}
	}

	public var displayName: String {
		switch self {
		case .file(let path): return path
		case .url(let url): return url
		case .stdin: return "stdin"
		}
	}

	private enum CodingKeys: String, CodingKey {
		case type, path, url
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		switch self {
		case .file(let path):
			try container.encode("file", forKey: .type)
			try container.encode(path, forKey: .path)
		case .url(let urlString):
			try container.encode("url", forKey: .type)
			try container.encode(urlString, forKey: .url)
		case .stdin:
			try container.encode("stdin", forKey: .type)
		}
	}
}

public func isURLArgument(_ argument: String) -> Bool {
	argument.hasPrefix("https://") || argument.hasPrefix("http://")
}

public func outputSourcePath(for source: ImageSource) -> String? {
	switch source {
	case .file(let path):
		return path
	case .url(let urlString):
		return urlOutputFilename(from: urlString)
	case .stdin:
		return nil
	}
}

public func urlOutputFilename(from urlString: String) -> String? {
	guard let components = URLComponents(string: urlString) else { return nil }
	let encodedPath = components.percentEncodedPath
	guard !encodedPath.isEmpty, encodedPath != "/", !encodedPath.hasSuffix("/") else { return nil }
	guard let encodedName = encodedPath.split(separator: "/", omittingEmptySubsequences: true).last else { return nil }

	let filename = String(encodedName).removingPercentEncoding ?? String(encodedName)
	guard !filename.isEmpty, filename != ".", filename != ".." else { return nil }
	guard !filename.contains("/") else { return nil }
	guard !filename.unicodeScalars.contains(where: { $0.value == 0 }) else { return nil }
	return filename
}
