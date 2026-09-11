const LAZY_CAPABILITY_NAMES = [
  'worker',
  'monaco',
  'RTFJS',
  'heic2any',
  'maplibre-gl',
  'rich-editor',
  'data-tools',
  'charts',
  'media',
  'cytoscape',
  'pdf-',
  'element-plus',
  '3d-runtime',
  'exceljs',
  'file-viewer'
] as const

const LAZY_CAPABILITY_PATTERN = new RegExp(`(?:${LAZY_CAPABILITY_NAMES.join('|')})`, 'i')
const LAZY_STYLE_PATTERN =
  /(?:^|\/)(?:assets\/(?:monaco|rich-editor|art-file-viewer)[.-]|vendor\/pdf\/)/i

export const isLazyCapabilityAsset = (assetPath: string): boolean =>
  LAZY_CAPABILITY_PATTERN.test(assetPath)

export const isLazyCapabilityStyle = (assetPath: string): boolean =>
  LAZY_STYLE_PATTERN.test(assetPath)

export const shouldPreloadHtmlDependency = (dependency: string): boolean =>
  !LAZY_CAPABILITY_PATTERN.test(dependency)
