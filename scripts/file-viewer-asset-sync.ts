import { copyFile, mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'
import type { Plugin, ResolvedConfig } from 'vite'

const ASSET_MANIFEST = 'flyfish-viewer-assets.json'
const RETRYABLE_COPY_ERROR_CODES = new Set(['EACCES', 'EBUSY', 'EPERM'])
const MAX_COPY_ATTEMPTS = 6

interface FileViewerAssetManifest {
  assets?: unknown[]
  [key: string]: unknown
}

export interface FileViewerAssetSyncResult {
  copied: number
  total: number
  unchanged: number
}

interface FileViewerAssetSyncPluginOptions {
  enabled: boolean
  sourceRoot: string
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && 'code' in error
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

async function listFiles(root: string, relativeDirectory = ''): Promise<string[]> {
  const directory = path.join(root, relativeDirectory)
  const entries = await readdir(directory, { withFileTypes: true })
  const files: string[] = []

  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const relativePath = path.join(relativeDirectory, entry.name)
    if (entry.isDirectory()) {
      files.push(...(await listFiles(root, relativePath)))
    } else if (entry.isFile()) {
      files.push(relativePath)
    }
  }

  return files
}

async function filesAreEqual(source: string, target: string): Promise<boolean> {
  try {
    const [sourceInfo, targetInfo] = await Promise.all([stat(source), stat(target)])
    if (sourceInfo.size !== targetInfo.size) return false

    const [sourceContent, targetContent] = await Promise.all([readFile(source), readFile(target)])
    return sourceContent.equals(targetContent)
  } catch (error) {
    if (isNodeError(error) && error.code === 'ENOENT') return false
    throw error
  }
}

async function copyFileWithRetry(source: string, target: string): Promise<void> {
  await mkdir(path.dirname(target), { recursive: true })

  for (let attempt = 1; attempt <= MAX_COPY_ATTEMPTS; attempt += 1) {
    try {
      await copyFile(source, target)
      return
    } catch (error) {
      const shouldRetry =
        isNodeError(error) &&
        Boolean(error.code && RETRYABLE_COPY_ERROR_CODES.has(error.code)) &&
        attempt < MAX_COPY_ATTEMPTS

      if (!shouldRetry) {
        throw new Error(`复制 File Viewer 构建资源失败：${target}`, { cause: error })
      }

      await delay(100 * 2 ** (attempt - 1))
    }
  }
}

async function writeFileIfChanged(target: string, content: Buffer): Promise<boolean> {
  try {
    const currentContent = await readFile(target)
    if (currentContent.equals(content)) return false
  } catch (error) {
    if (!isNodeError(error) || error.code !== 'ENOENT') throw error
  }

  await mkdir(path.dirname(target), { recursive: true })
  await writeFile(target, content)
  return true
}

async function createOutputManifest(sourceRoot: string, targetRoot: string): Promise<Buffer> {
  const sourceManifest = path.join(sourceRoot, ASSET_MANIFEST)
  const parsed: unknown = JSON.parse(await readFile(sourceManifest, 'utf8'))
  if (!isRecord(parsed)) {
    throw new Error('File Viewer 构建资源清单格式无效')
  }

  const manifest = parsed as FileViewerAssetManifest
  const assets = Array.isArray(manifest.assets)
    ? manifest.assets.map((asset) => {
        if (!isRecord(asset) || typeof asset.to !== 'string') return asset

        const relativeTarget = path.relative(sourceRoot, asset.to)
        if (relativeTarget.startsWith('..') || path.isAbsolute(relativeTarget)) return asset

        return {
          ...asset,
          to: path.join(targetRoot, relativeTarget)
        }
      })
    : manifest.assets

  return Buffer.from(`${JSON.stringify({ ...manifest, assets }, null, 2)}\n`)
}

/**
 * Incrementally synchronizes File Viewer assets into the Vite output directory.
 * Existing byte-identical files are never removed or overwritten, which avoids
 * Windows EBUSY failures when antivirus or a preview process temporarily holds
 * a generated font file open.
 */
export async function syncFileViewerAssets(
  sourceRoot: string,
  targetRoot: string
): Promise<FileViewerAssetSyncResult> {
  const sourceInfo = await stat(sourceRoot)
  if (!sourceInfo.isDirectory()) {
    throw new Error(`File Viewer 构建资源目录不存在：${sourceRoot}`)
  }

  const relativeFiles = (await listFiles(sourceRoot)).filter(
    (relativePath) => relativePath !== ASSET_MANIFEST
  )
  let copied = 0
  let unchanged = 0

  for (const relativeFile of relativeFiles) {
    const source = path.join(sourceRoot, relativeFile)
    const target = path.join(targetRoot, relativeFile)

    if (await filesAreEqual(source, target)) {
      unchanged += 1
      continue
    }

    await copyFileWithRetry(source, target)
    copied += 1
  }

  const manifestChanged = await writeFileIfChanged(
    path.join(targetRoot, ASSET_MANIFEST),
    await createOutputManifest(sourceRoot, targetRoot)
  )
  if (manifestChanged) copied += 1
  else unchanged += 1

  return {
    copied,
    unchanged,
    total: relativeFiles.length + 1
  }
}

export function createFileViewerAssetSyncPlugin(options: FileViewerAssetSyncPluginOptions): Plugin {
  let resolvedConfig: ResolvedConfig | undefined

  return {
    name: 'file-viewer-asset-sync',
    apply: 'build',
    // Vite 8 also runs closeBundle for nested Web Worker builds. Syncing from
    // there races the top-level vite:prepare-out-dir cleanup on Windows.
    applyToEnvironment: (environment) => !environment.config.isWorker,
    configResolved(config) {
      resolvedConfig = config
    },
    closeBundle: {
      order: 'post',
      sequential: true,
      async handler() {
        if (!options.enabled) return
        if (!resolvedConfig) throw new Error('Vite 配置尚未完成，无法同步 File Viewer 资源')

        const targetRoot = path.resolve(resolvedConfig.root, resolvedConfig.build.outDir)
        const result = await syncFileViewerAssets(options.sourceRoot, targetRoot)
        console.log(
          `[vite] File Viewer 资源同步完成：复制 ${result.copied}，跳过未变化 ${result.unchanged}`
        )
      }
    }
  }
}
