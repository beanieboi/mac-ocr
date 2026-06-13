import { describe, test, expect } from 'manten';
import { ocr, createSearchablePdf } from '../../src/index.ts';
import { fixtureData } from '../utils.ts';

/**
 * The realistic production pattern: a `Promise.all` burst over many inputs.
 * Every call spawns its own subprocess, so this exercises N simultaneous
 * Vision processes (ANE contention) end to end. Stress-audited at 16-way
 * parallelism with a 24 MP input; kept at 8 mixed calls here for CI time.
 */
await describe('concurrency', async () => {
	await test('a parallel burst of mixed calls all resolve correctly', async () => {
		const hello = fixtureData('hello.png');
		const multipage = fixtureData('multipage.pdf');

		const [pages, pdf, ...singles] = await Promise.all([
			Array.fromAsync(ocr.pages(multipage)),
			createSearchablePdf(hello),
			...Array.from({ length: 6 }, () => ocr(hello)),
		]);

		for (const result of singles) {
			expect(result.text).toContain('Hello World');
		}
		expect(pages.map(page => page.page)).toEqual([1, 2, 3]);
		expect(Buffer.from(pdf.subarray(0, 5)).toString('utf8')).toBe('%PDF-');
	});
});
