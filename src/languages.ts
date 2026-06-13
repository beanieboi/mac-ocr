import { collectStdout, spawnBinary } from './process.ts';

/**
 * List the recognition languages supported on this macOS version (BCP-47
 * codes, e.g. `en-US`). These apply to both {@link ocr} and
 * {@link createSearchablePdf} — they share the same Vision recognizer. Pass
 * `{ fast: true }` for the set available to the fast recognizer.
 */
export const supportedLanguages = async (options?: { fast?: boolean }): Promise<string[]> => {
	const args = ['languages'];
	if (options?.fast) {
		args.push('--fast');
	}
	const stdout = await collectStdout(spawnBinary(args), 'mac-ocr languages');
	return stdout.toString('utf8').trim().split('\n').filter(Boolean);
};
