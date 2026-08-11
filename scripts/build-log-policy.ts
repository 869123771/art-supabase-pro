const BROWSER_EXTERNALIZATION_PATTERN =
  /Module "([^"]+)" has been externalized for browser compatibility, imported by "([^"]+)"/

const KNOWN_FILE_VIEWER_TRANSITIVE_PACKAGES = [
  '/node_modules/.pnpm/avsc@',
  '/node_modules/.pnpm/@ljheee+xmind-parser@',
  '/node_modules/.pnpm/ag-psd@',
  '/node_modules/.pnpm/jszip@'
] as const

interface BuildLogLike {
  message?: string
}

export function getKnownFileViewerExternalization(log: BuildLogLike): string | null {
  const message = log.message || ''
  const match = message.match(BROWSER_EXTERNALIZATION_PATTERN)
  if (!match) return null

  const [, builtinModule, importer] = match
  const normalizedImporter = importer.replace(/\\/g, '/')
  const knownPackage = KNOWN_FILE_VIEWER_TRANSITIVE_PACKAGES.find((packagePath) =>
    normalizedImporter.includes(packagePath)
  )

  return knownPackage
    ? `${builtinModule}:${knownPackage.slice('/node_modules/.pnpm/'.length, -1)}`
    : null
}
