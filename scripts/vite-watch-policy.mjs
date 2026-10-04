/** Keep generated reports and build output outside the development file watcher. */
export function createViteWatchPolicy(outDir) {
  return {
    ignored: [
      '**/.artifacts/**',
      '**/.codex/**',
      '**/.idea/**',
      '**/playwright-report/**',
      '**/test-results/**',
      `**/${outDir}/**`,
      '**/dist/**',
      '**/dist-ssr/**'
    ]
  }
}
