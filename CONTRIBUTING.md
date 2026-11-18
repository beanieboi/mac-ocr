# Contributing

Project posture, development setup, and conventions for working on `mac-ocr`.

## Posture

This project follows [semantic versioning](https://semver.org/). The version reported by `mac-ocr --version` lives in `Sources/MacOcrCore/Version.swift` and is bumped by hand.

- **Semver is the deprecation strategy.** Breaking changes (flag removals, output schema changes) require a `BREAKING CHANGE:` footer and trigger a major bump. Additive changes (new flags) are non-breaking minors.
- **Correctness over speed.** Read the docs, trace behavior end-to-end, verify against a real input — then decide.
- **Developer experience is the product.** If a command feels clunky, redesign it.

## What lives where

The deliverable is the CLI: a Swift binary (`Sources/`) built on Apple's Vision framework.

User-facing docs: [README.md](README.md), [docs/CLI.md](docs/CLI.md), and the agent skill in [skills/mac-ocr/SKILL.md](skills/mac-ocr/SKILL.md). All three must be updated for user-facing changes.

## Requirements

- macOS 10.15+ (deployment target; development uses a current Xcode)
- A recent full Xcode (not just Command Line Tools — `swift test` uses the Swift Testing framework) with a Swift 6 toolchain (`Package.swift` is tools 6.0, Swift 6 language mode with strict concurrency)

## Development

### Build and run

```sh
swift build
swift run mac-ocr receipt.jpg
swift run mac-ocr scan.pdf --format jsonl
swift run mac-ocr searchable-pdf scan.pdf -o out.pdf
swift run mac-ocr --help
```

### Test

```sh
swift test --no-parallel # Swift suites (spawn .build/debug/mac-ocr)
swift format lint --strict --recursive --parallel Sources Tests
```

**Why `--no-parallel`?** Swift Testing runs suites in parallel by default. Integration suites spawn the `mac-ocr` subprocess while engine suites call Vision in-process; Vision pins the Apple Neural Engine (a shared resource), so concurrent suites cause ANE contention and sandbox resource kills. Serialization is enforced two ways:

1. **`@Suite(.serialized)`** on every top-level suite.
2. **`VisionGate`** (`Tests/mac-ocrTests/VisionGate.swift`) — a process-wide semaphore that `TestSupport.run()` acquires before spawning the binary, serializing Vision access across suite boundaries.

Run one suite: `swift test --no-parallel --filter SearchablePDFTests`

**Schema snapshots:** the JSON/JSONL output schema and the fd-3 error envelope are pinned by golden files (`Tests/mac-ocrTests/Snapshots/`). A deliberate schema change regenerates them with `MAC_OCR_UPDATE_SNAPSHOTS=1 swift test --no-parallel --filter SchemaSnapshotTests` — the golden diff in review *is* the schema change. Remember the `BREAKING CHANGE:` footer.

### Release build (universal binary)

```sh
swift build -c release --arch arm64 --arch x86_64 -Xswiftc -Osize -Xlinker -dead_strip
mkdir -p bin && cp .build/apple/Products/Release/mac-ocr bin/mac-ocr && strip -rSTx bin/mac-ocr
```

Builds a universal (arm64 + x86_64) release binary into `bin/mac-ocr`. The flags are tuned for binary size: `-Xswiftc -Osize` (runtime is Vision/ANE-bound, so Swift glue speed is irrelevant), `-Xlinker -dead_strip`, and a final `strip -rSTx` (removes the nlist symbol table — ~1.1 MB per slice — but not the `__swift5_*` reflection metadata ArgumentParser relies on). Together: ~4.1 MB → ~1.8 MB universal.

## Project structure

```
Sources/MacOcrCore/        # pure core target; no ArgumentParser dependency
├── Engines/               # recognizeText + OCREngine (serialized Vision entry)
├── SearchablePDF/         # vector-preserving writer + per-word invisible text layer
├── Geometry/              # BoundingBox + TL↔BL coordinate conversions
├── Input/                 # image/PDF/stdin/URL loading, rasterization, auto-DPI
├── Output/                # result envelope, formats, output strategy + routing
└── Runtime/               # VisionSession/VisionRuntime/BatchRunner, errors

Sources/MacOcrCLI/         # ArgumentParser target; owns the command-line surface
├── RootCommand.swift      # OCR is the default subcommand; fd-3 error envelopes
├── Commands/              # OCRCommand, SearchablePDFCommand, LanguagesCommand
└── Options/               # OcrCommandOptions, RecognitionOptions (shared flags), validation

Sources/mac-ocr/main.swift # thin executable; delegates to MacOcr.run(arguments:)

Tests/mac-ocrTests/        # Swift Testing suites (TestSupport / VisionGate / Snapshots)
Tests/fixtures/            # see Tests/fixtures/README.md for provenance
docs/                      # CLI.md reference
skills/                    # agent skill
```

### Architecture

- **Pure core.** `MacOcrCore` operates on `VisionSession`/`CGImage` plus typed options; no flag parsing. Commands call core; core never calls commands.
- **Serialized Vision.** All recognition routes through the `VisionRuntime` actor (`OCREngine.run`). Its closure is deliberately synchronous — see the warning on `VisionRuntime` before changing this.
- **One runner.** `BatchRunner` owns source opening, PDF page iteration, serial execution, and fail-soft error aggregation (`ErrorSink`); the per-page operation and the output shape (`OutputStrategy`) are injected. `searchable-pdf` calls `SearchablePDF.write(...)` / `writeMerged(...)` for file output and `render(...)` / `renderMerged(...)` for buffered stdout output. The core shares page rendering and PDF finalization across memory and callback-backed file consumers; the CLI owns sibling temporary files and atomic rename publication.
- **Four commands.** `RootCommand` registers `OCRCommand` (default — `mac-ocr photo.png` just works), `DocumentCommand`, `SearchablePDFCommand`, and `LanguagesCommand`. Shared recognition flags live in the `RecognitionOptions` option group so the OCR commands cannot drift.

## CI/CD

Workflows live in [.github/workflows/](.github/workflows/) — `test.yml` (Swift tests and `swift format lint`).

## Commits

Angular convention (`feat:`, `fix:`, `perf:`, `docs:`, `chore:`, `refactor:`, `test:`, `build:`, `ci:`). Breaking changes use a `BREAKING CHANGE:` footer:

```
feat(ocr): restructure result schema

BREAKING CHANGE: the flat `file` field is replaced by a tagged `source` union.
```

## Pre-commit checklist

1. `swift build` clean
2. `swift test --no-parallel` passes
3. `swift format lint --strict --recursive --parallel Sources Tests` clean
4. `git diff` reviewed
5. Commit message follows the Angular convention
6. `README.md` + `docs/` + `skills/mac-ocr/SKILL.md` updated for user-facing changes
