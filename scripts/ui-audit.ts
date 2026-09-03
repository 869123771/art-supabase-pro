import { readdir, readFile } from 'node:fs/promises'
import path from 'node:path'
import { parse as parseSfc } from '@vue/compiler-sfc'

interface Finding {
  file: string
  line: number
  rule: string
  excerpt: string
}

const projectRoot = process.cwd()
const sourceRoot = path.join(projectRoot, 'src')
const supportedExtensions = new Set(['.vue', '.scss', '.css', '.ts', '.tsx'])

async function collectFiles(directory: string): Promise<string[]> {
  const entries = await readdir(directory, { withFileTypes: true })
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const resolved = path.join(directory, entry.name)
      if (entry.isDirectory()) return collectFiles(resolved)
      return supportedExtensions.has(path.extname(entry.name)) ? [resolved] : []
    })
  )

  return nested.flat()
}

function lineAt(content: string, offset: number): number {
  return content.slice(0, offset).split('\n').length
}

function excerptAt(content: string, offset: number): string {
  const start = content.lastIndexOf('\n', offset) + 1
  const end = content.indexOf('\n', offset)
  return content.slice(start, end === -1 ? content.length : end).trim()
}

interface TemplateNode {
  type: number
  tag?: string
  props?: Array<{
    type: number
    name?: string
    value?: { content?: string }
  }>
  children?: TemplateNode[]
  loc?: { start: { offset: number } }
}

function hasStaticClass(node: TemplateNode, className: string): boolean {
  const classAttribute = node.props?.find(
    (property) => property.type === 6 && property.name === 'class'
  )
  return Boolean(classAttribute?.value?.content?.split(/\s+/).some((name) => name === className))
}

function containsSectionHeading(node: TemplateNode): boolean {
  if (node.type === 1) {
    if (node.tag === 'ArtSectionTitle' || /^h[1-6]$/.test(node.tag ?? '')) return true
  }
  return node.children?.some(containsSectionHeading) ?? false
}

function countSectionTitles(node: TemplateNode, isRoot = true): number {
  if (!isRoot && node.type === 1 && hasStaticClass(node, 'art-card-xs')) return 0
  const ownCount = node.type === 1 && node.tag === 'ArtSectionTitle' ? 1 : 0
  return (
    ownCount +
    (node.children?.reduce((sum, child) => sum + countSectionTitles(child, false), 0) ?? 0)
  )
}

function findRawTitledCards(file: string, content: string): number[] {
  const { descriptor } = parseSfc(content, { filename: file })
  if (!descriptor.template?.ast) return []

  const offsets: number[] = []
  const visit = (node: TemplateNode): void => {
    if (
      node.type === 1 &&
      node.tag === 'section' &&
      hasStaticClass(node, 'art-card-xs') &&
      (countSectionTitles(node) === 1 ||
        node.children?.some((child) => {
          if (child.type !== 1) return false
          return child.tag === 'header' || /^h[1-6]$/.test(child.tag ?? '')
            ? containsSectionHeading(child)
            : false
        }))
    ) {
      offsets.push(node.loc?.start.offset ?? 0)
    }
    node.children?.forEach(visit)
  }

  visit(descriptor.template.ast as TemplateNode)
  return offsets
}

function scanFile(file: string, content: string): Finding[] {
  const findings: Finding[] = []
  const relativeFile = path.relative(projectRoot, file).replaceAll('\\', '/')

  const addFinding = (offset: number, rule: string): void => {
    findings.push({
      file: relativeFile,
      line: lineAt(content, offset),
      rule,
      excerpt: excerptAt(content, offset)
    })
  }

  const rules = [
    {
      name: 'motion/no-transition-all',
      pattern: /(?:-webkit-)?transition\s*:\s*all\b|\btransition-all\b/g
    },
    {
      name: 'a11y/no-static-element-click',
      pattern: /<(?:div|span|li|p|i)\b[^>]*@click(?:\.[\w-]+)*\s*=/gs
    }
  ]

  rules.forEach(({ name, pattern }) => {
    for (const match of content.matchAll(pattern)) {
      if (match.index == null || match[0].includes('data-ui-audit-allow')) continue
      addFinding(match.index, name)
    }
  })

  if (path.extname(file) === '.vue') {
    for (const match of content.matchAll(/<(?:ElEmpty|el-empty)\b/g)) {
      if (match.index == null || excerptAt(content, match.index).includes('data-ui-audit-allow')) {
        continue
      }
      addFinding(match.index, 'consistency/use-art-empty-state')
    }

    if (
      ![
        'src/components/business/business-workspace-header/index.vue',
        'src/components/core/surfaces/art-section-card/index.vue'
      ].includes(relativeFile)
    ) {
      findRawTitledCards(file, content).forEach((offset) => {
        if (!excerptAt(content, offset).includes('data-ui-audit-allow')) {
          addFinding(offset, 'consistency/use-art-section-card')
        }
      })
    }

    for (const match of content.matchAll(/<img\b[^>]*>/gs)) {
      if (match.index == null || match[0].includes('data-ui-audit-allow')) continue
      if (!/\s(?:alt|:alt)\s*=/.test(match[0])) addFinding(match.index, 'images/require-alt')
      const hasWidth = /\s:?width\s*=/.test(match[0])
      const hasHeight = /\s:?height\s*=/.test(match[0])
      if (!hasWidth || !hasHeight) addFinding(match.index, 'images/require-intrinsic-size')
    }

    for (const match of content.matchAll(/<ElButton\b[^>]*\bcircle\b[^>]*>/gs)) {
      if (match.index == null || match[0].includes('data-ui-audit-allow')) continue
      if (!/(?:aria-label|title)\s*=/.test(match[0])) {
        addFinding(match.index, 'a11y/icon-button-requires-name')
      }
    }

    for (const match of content.matchAll(
      /<ElDropdownItem\b[^>]*\bv-(?:auth|loading|ripple)\b[^>]*>/gs
    )) {
      if (match.index == null || match[0].includes('data-ui-audit-allow')) continue
      addFinding(match.index, 'runtime/no-directive-on-dropdown-item')
    }

    for (const match of content.matchAll(
      /<BusinessWorkspaceHeader\b[\s\S]*?<\/BusinessWorkspaceHeader>/g
    )) {
      if (match.index == null || match[0].includes('data-ui-audit-allow')) continue
      const manualRefreshOffset = match[0].search(/ri:refresh-line|>\s*刷新\s*</)
      if (manualRefreshOffset >= 0) {
        addFinding(match.index + manualRefreshOffset, 'consistency/use-workspace-refresh-prop')
      }
    }

    for (const match of content.matchAll(/<ArtStickyActionBar\b[\s\S]*?<\/ArtStickyActionBar>/g)) {
      if (match.index == null || match[0].includes('data-ui-audit-allow')) continue
      const hasSummary = /<template\s+#summary\b/.test(match[0])
      const hasHint = /\s:?hint\s*=/.test(match[0])
      if (!hasSummary && !hasHint) {
        addFinding(match.index, 'consistency/sticky-action-bar-requires-summary')
      }
    }

    for (const match of content.matchAll(/<a\b[^>]*target\s*=\s*["']_blank["'][^>]*>/gs)) {
      if (match.index == null || match[0].includes('data-ui-audit-allow')) continue
      if (!/rel\s*=\s*["'][^"']*noopener[^"']*["']/.test(match[0])) {
        addFinding(match.index, 'security/external-link-noopener')
      }
    }

    const uploadButtonPatterns = [
      /<ElUpload\b[\s\S]*?<ElButton\b[\s\S]*?<\/ElUpload>/g,
      /h\(\s*ElUpload[\s\S]{0,2000}?h\(\s*ElButton/g
    ]
    uploadButtonPatterns.forEach((pattern) => {
      for (const match of content.matchAll(pattern)) {
        if (match.index != null) addFinding(match.index, 'a11y/no-nested-upload-button')
      }
    })

    if (relativeFile.startsWith('src/views/')) {
      for (const match of content.matchAll(/<(?:ElDialog|el-dialog|ElDrawer|el-drawer)\b/g)) {
        if (match.index != null) addFinding(match.index, 'architecture/use-art-overlay')
      }

      for (const match of content.matchAll(/console\.(?:log|debug)\s*\(/g)) {
        if (match.index != null) addFinding(match.index, 'quality/no-view-debug-log')
      }

      const rawErrorPatterns = [
        /\bString\(\s*(?:error|err)\s*\)/g,
        /\bJSON\.stringify\(\s*(?:error|err)\b[^)]*\)/g
      ]
      rawErrorPatterns.forEach((pattern) => {
        for (const match of content.matchAll(pattern)) {
          if (match.index != null) addFinding(match.index, 'quality/no-raw-error-render')
        }
      })
    }
  }

  if (relativeFile.startsWith('src/views/')) {
    for (const match of content.matchAll(/\bElMessageBox\.(?:confirm|prompt)\s*\(/g)) {
      if (match.index != null) addFinding(match.index, 'architecture/use-art-feedback')
    }
  }

  return findings
}

const files = await collectFiles(sourceRoot)
const findings = (
  await Promise.all(
    files.map(async (file) => {
      const content = await readFile(file, 'utf8')
      return scanFile(file, content)
    })
  )
).flat()

if (findings.length > 0) {
  console.error(`UI audit failed with ${findings.length} finding(s):`)
  findings.forEach((finding) => {
    console.error(
      `- ${finding.file}:${finding.line} [${finding.rule}] ${finding.excerpt || '(multiline tag)'}`
    )
  })
  process.exitCode = 1
} else {
  console.log(`UI audit passed (${files.length} files checked).`)
}
