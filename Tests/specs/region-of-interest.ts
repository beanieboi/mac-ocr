import { describe, test, expect } from 'manten';
import { serializeRegionOfInterest } from '../../src/args.ts';

await describe('serializeRegionOfInterest', async () => {
	await test('object form', () => {
		expect(serializeRegionOfInterest({
			x: 0.1,
			y: 0.2,
			width: 0.5,
			height: 0.6,
		})).toBe('0.1,0.2,0.5,0.6');
	});

	await test('tuple form', () => {
		expect(serializeRegionOfInterest([0, 0, 1, 0.5])).toBe('0,0,1,0.5');
	});

	await test('string passthrough', () => {
		expect(serializeRegionOfInterest('0,0,1,1')).toBe('0,0,1,1');
	});

	await test('rejects out-of-range coordinates', () => {
		expect(() => serializeRegionOfInterest({
			x: -0.1,
			y: 0,
			width: 1,
			height: 1,
		})).toThrow(/\[0, 1\]/);
	});

	await test('rejects non-positive dimensions', () => {
		expect(() => serializeRegionOfInterest([0, 0, 0, 0.5])).toThrow(/positive/);
	});

	await test('rejects a region that extends past the image', () => {
		expect(() => serializeRegionOfInterest({
			x: 0.6,
			y: 0,
			width: 0.6,
			height: 0.5,
		})).toThrow(/past the image/);
	});

	await test('rejects a tuple of the wrong length', () => {
		expect(() => serializeRegionOfInterest([0, 0, 1] as never)).toThrow(/four values/);
	});
});
