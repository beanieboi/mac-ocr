import { defineConfig, pvtnbr } from 'lintroll';

export default defineConfig([
	{
		ignores: [
			'.build/**',
			'bin/**',
			'dist/**',
			'docs/**',
			'skills/**',
			'Tests/fixtures/**',
			'Package.resolved',
		],
	},
	...pvtnbr({
		node: true,
	}),
]);
