import { describe } from 'manten';

await describe('mac-ocr', async () => {
	await import('./specs/ocr.ts');
	await import('./specs/pages.ts');
	await import('./specs/searchable-pdf.ts');
	await import('./specs/languages.ts');
	await import('./specs/region-of-interest.ts');
	await import('./specs/process.ts');
	await import('./specs/wrapper.ts');
	await import('./specs/concurrency.ts');
});
