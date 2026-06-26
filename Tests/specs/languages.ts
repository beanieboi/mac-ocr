import { describe, test, expect } from 'manten';
import { supportedLanguages } from '../../src/index.ts';

describe('supportedLanguages', () => {
	test('returns a non-empty list including en-US', async () => {
		const languages = await supportedLanguages();
		expect(Array.isArray(languages)).toBe(true);
		expect(languages.length).toBeGreaterThan(0);
		expect(languages).toContain('en-US');
	});

	test('accepts the fast option', async () => {
		const languages = await supportedLanguages({ fast: true });
		expect(languages.length).toBeGreaterThan(0);
	});
});
