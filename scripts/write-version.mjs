import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const packageJsonPath = fileURLToPath(new URL('../package.json', import.meta.url));
const versionSwiftPath = fileURLToPath(new URL('../Sources/MacOcrCore/Version.swift', import.meta.url));

const { version } = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));

// semantic-release uses "0.0.0-semantic-release" as the in-repo placeholder
// and bumps it before publishing. When the placeholder is still present
// (local dev), keep the committed dev default instead of baking a placeholder
// string into the binary.
if (!version.includes('semantic-release')) {
	const contents = `// Generated at build time by scripts/write-version.mjs. Do not edit.
// The committed value is used by \`swift build\` / \`swift test\` for local dev.
public let macOcrVersion = ${JSON.stringify(version)}
`;

	fs.writeFileSync(versionSwiftPath, contents);
}
