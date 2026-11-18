import MacOcrCLI

await MacOcr.run(arguments: Array(CommandLine.arguments.dropFirst()))
