import { readdir, stat } from 'node:fs/promises'
import { resolve } from 'node:path'

const KIB = 1024
const MIB = 1024 * KIB
const outputDirectory = resolve(process.env.VITE_OUT_DIR || process.argv[2] || 'docs')

// File viewer, Monaco and media renderers are intentionally lazy-loaded. They have a separate
// ceiling so their vendor size does not weaken the budget for ordinary route/application chunks.
const LAZY_VENDOR_PATTERN =
  /(?:worker|monaco|RTFJS|heic2any|maplibre-gl|rich-editor|data-tools|charts|media|cytoscape|pdf-|element-plus)/i

interface BundleAsset {
  path: string
  size: number
}

const relativePaths = await readdir(outputDirectory, { recursive: true })
const assets: BundleAsset[] = []

for (const relativePath of relativePaths) {
  const assetPath = resolve(outputDirectory, relativePath)
  const metadata = await stat(assetPath)
  if (metadata.isFile())
    assets.push({ path: relativePath.replace(/\\/g, '/'), size: metadata.size })
}

const javascriptAssets = assets.filter((asset) => asset.path.endsWith('.js'))
const cssAssets = assets.filter((asset) => asset.path.endsWith('.css'))
const applicationChunks = javascriptAssets.filter((asset) => !LAZY_VENDOR_PATTERN.test(asset.path))
const violations: string[] = []

checkLargest('单个 JavaScript 文件', javascriptAssets, 7 * MIB)
checkLargest('普通应用/路由 JavaScript 分包', applicationChunks, 900 * KIB)
checkLargest('单个 CSS 文件', cssAssets, 360 * KIB)
checkTotal('JavaScript 总体积', javascriptAssets, 40 * MIB)
checkTotal('CSS 总体积', cssAssets, 1.6 * MIB)

if (violations.length) {
  console.error('[bundle:check] 构建体积预算未通过：')
  violations.forEach((violation) => console.error(`- ${violation}`))
  console.error('请优先检查同步导入、重复依赖和未按路由懒加载的重型能力。')
  process.exitCode = 1
} else {
  const largestApplicationChunk = [...applicationChunks].sort((a, b) => b.size - a.size)[0]
  console.log(
    `[bundle:check] 通过 · JS ${formatBytes(sumSize(javascriptAssets))} · CSS ${formatBytes(
      sumSize(cssAssets)
    )} · 最大普通分包 ${largestApplicationChunk?.path || '-'} ${formatBytes(
      largestApplicationChunk?.size || 0
    )}`
  )
}

function checkLargest(label: string, source: BundleAsset[], limit: number): void {
  const oversizedAssets = source.filter((asset) => asset.size > limit)
  oversizedAssets.forEach((asset) => {
    violations.push(
      `${label} ${asset.path} 为 ${formatBytes(asset.size)}，上限 ${formatBytes(limit)}`
    )
  })
}

function checkTotal(label: string, source: BundleAsset[], limit: number): void {
  const total = sumSize(source)
  if (total > limit) violations.push(`${label}为 ${formatBytes(total)}，上限 ${formatBytes(limit)}`)
}

function sumSize(source: BundleAsset[]): number {
  return source.reduce((total, asset) => total + asset.size, 0)
}

function formatBytes(value: number): string {
  return value >= MIB ? `${(value / MIB).toFixed(2)} MiB` : `${(value / KIB).toFixed(1)} KiB`
}
