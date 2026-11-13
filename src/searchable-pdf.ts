import fs from 'node:fs/promises';
import path from 'node:path';
import { isMainThread } from 'node:worker_threads';
import { buildArgs } from './args.ts';
import { MacOcrError } from './errors.ts';
import { collectStdout, spawnBinary, waitForExit } from './process.ts';
import { searchablePdfWithService } from './service/index.ts';
import type { Input, SearchablePdfOptions } from './types.ts';

const flagArgument = (flag: string, enabled?: boolean): string[] => (
	enabled ? [flag] : []
);

const valueArgument = (flag: string, value?: number | string): string[] => (
	value === undefined ? [] : [flag, String(value)]
);

const buildSearchablePdfOptions = (options?: SearchablePdfOptions): string[] => [
	...buildArgs(options),
	...flagArgument('--ocr-all-pages', options?.ocrAllPages),
	...valueArgument('--image-quality', options?.imageQuality),
	...valueArgument('--image-page-dpi', options?.imagePageDpi),
	...valueArgument('--image-downsample-dpi', options?.imageDownsampleDpi),
	...valueArgument('--ocr-strategy', options?.ocrStrategy),
];

const buildSearchablePdfArgs = (options?: SearchablePdfOptions): string[] => [
	'searchable-pdf',
	...buildSearchablePdfOptions(options),
];

type SearchablePdfFileOptions = SearchablePdfOptions & {
	inputPath: string;
	outputPath: string;
};

type SearchablePdfArguments =
	| [input: Input, options?: SearchablePdfOptions]
	| [options: SearchablePdfFileOptions];

type BytesBackend = (input: Input, options?: SearchablePdfOptions) => Promise<Uint8Array>;

const bytesOneShot: BytesBackend = (input, options) => collectStdout(
	spawnBinary([...buildSearchablePdfArgs(options), '-o', '-', '-'], {
		input,
		signal: options?.signal,
		password: options?.password,
	}),
	'mac-ocr searchable-pdf',
);

const bytesShared: BytesBackend = (input, options) => (
	isMainThread
		? searchablePdfWithService(
			input,
			buildSearchablePdfOptions(options),
			options?.password || process.env.MAC_OCR_PDF_PASSWORD,
			options?.signal,
		)
		: bytesOneShot(input, options)
);

const dispatch = async (
	args: unknown[],
	bytes: BytesBackend,
): Promise<Uint8Array | void> => {
	if (args.length > 2) {
		throw new TypeError('createSearchablePdf accepts at most two arguments.');
	}
	const [input, options] = args as [unknown, SearchablePdfOptions | undefined];
	if (!(input instanceof Uint8Array) && !(input instanceof ArrayBuffer)) {
		if (!input || typeof input !== 'object' || args.length !== 1) {
			throw new TypeError('File mode requires one options object with inputPath and outputPath.');
		}
		return writeSearchablePdf(input as SearchablePdfFileOptions);
	}
	if (options && ('inputPath' in options || 'outputPath' in options)) {
		throw new TypeError('Byte input cannot be combined with file paths.');
	}
	return bytes(input, options);
};

type CreateSearchablePdf = {

	/**
	 * Produce a searchable PDF from image or PDF bytes — the same content with an
	 * invisible, selectable OCR text layer added. Returns the PDF bytes.
	 *
	 * ```ts
	 * const pdf = await createSearchablePdf(await fs.readFile('scan.pdf'))
	 * await fs.writeFile('scan.ocr.pdf', pdf)
	 * ```
	 */
	(input: Input, options?: SearchablePdfOptions): Promise<Uint8Array>;

	/**
	 * Write a searchable PDF between literal local paths with atomic publication.
	 * File output avoids retaining the complete encoded PDF in an application-owned
	 * buffer. Input/output aliases are rejected. Abort waits for child closure;
	 * publication can win the race, and a killed child can leave a sibling temp file.
	 */
	(options: SearchablePdfFileOptions): Promise<void>;
};

export const createSearchablePdf = (
	(...args: SearchablePdfArguments) => dispatch(args, bytesShared)
) as CreateSearchablePdf;

/** {@link createSearchablePdf} without the shared native service (one-shot process per call). */
export const createSearchablePdfSingleProcess = (
	(...args: SearchablePdfArguments) => dispatch(args, bytesOneShot)
) as CreateSearchablePdf;

const checkAborted = (signal?: AbortSignal) => {
	if (signal?.aborted) {
		throw new MacOcrError('mac-ocr searchable-pdf was aborted', { kind: 'abort' });
	}
};

const destinationStat = async (outputPath: string) => {
	try {
		return await fs.stat(outputPath);
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code !== 'ENOENT') {
			throw error;
		}
	}
};

const validateFilePath = (value: string): void => {
	if (typeof value !== 'string' || !value || value.includes('\0')) {
		throw new TypeError('Input and output paths must be non-empty local file paths.');
	}
};

/**
 * Write a searchable PDF from a local file to a local file, without retaining
 * the complete encoded output PDF in an application-owned memory buffer.
 * Paths are literal and relative to the calling process's working directory.
 * Input/output aliases are rejected. Successful output atomically replaces the
 * destination; cancellation racing with publication can leave a complete PDF.
 * A killed child can leave a sibling .<destination-name>.<uuid>.tmp file.
 */
const writeSearchablePdf = async (
	options: SearchablePdfFileOptions,
): Promise<void> => {
	const { inputPath, outputPath } = options;
	validateFilePath(inputPath);
	validateFilePath(outputPath);
	checkAborted(options?.signal);
	const input = path.resolve(inputPath);
	const output = path.resolve(outputPath);
	if (input === output) {
		throw new TypeError('Input and output paths must refer to different files.');
	}
	const [inputStat, outputStat] = await Promise.all([fs.stat(input), destinationStat(output)]);
	if (outputStat && inputStat.dev === outputStat.dev && inputStat.ino === outputStat.ino) {
		throw new TypeError('Input and output paths must refer to different files.');
	}
	checkAborted(options?.signal);
	const spawned = spawnBinary([...buildSearchablePdfArgs(options), '--output-file', output, '--', input], {
		signal: options?.signal,
		password: options?.password,
	});
	spawned.proc.stdout.resume();
	await waitForExit(spawned, 'mac-ocr searchable-pdf');
};
