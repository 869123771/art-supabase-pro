import fs from 'node:fs/promises'
import path from 'node:path'

const projectRoot = process.cwd()
const viewsRoot = path.join(projectRoot, 'src', 'views')
const excludedBusinessSegments = new Set(['auth', 'examples', 'widgets'])
const rawBusinessComponentPattern =
  /<(?:el-(dialog|drawer|table|form)|El(Dialog|Drawer|Table|Form))\b/g
const fixedOverlaySizePattern =
  /(?:<Art(?:Dialog|Drawer)\b[^>]*(?:width|size)="\d+px"|dialog-width="\d+px"|^\s*(?:width|size):\s*['"](?:min\()?\d+px)/gm
const rawDescriptionsPattern = /<(?:el-descriptions|ElDescriptions)\b/g
const rawMessageBoxPromptPattern = /ElMessageBox\s*\.\s*prompt\s*\(/g
const rawMessageBoxConfirmPattern = /ElMessageBox\s*\.\s*confirm\s*\(/g
const nativeScrollPattern = /overflow(?:-y)?:\s*(?:auto|scroll)\s*;/g
const hardcodedRadiusPattern = /border-radius:\s*(?!0\b|50%|999px|var\()[1-9]\d*px/g

interface Violation {
  component: string
  file: string
  line: number
}

interface PolicyFinding {
  policy: string
  file: string
  line: number
}

async function collectVueFiles(directory: string): Promise<string[]> {
  const entries = await fs.readdir(directory, { withFileTypes: true })
  const files = await Promise.all(
    entries.map(async (entry) => {
      const target = path.join(directory, entry.name)
      if (entry.isDirectory()) return collectVueFiles(target)
      return entry.isFile() && entry.name.endsWith('.vue') ? [target] : []
    })
  )
  return files.flat()
}

function isBusinessView(file: string): boolean {
  const relativeSegments = path.relative(viewsRoot, file).split(path.sep)
  return !relativeSegments.some((segment) => excludedBusinessSegments.has(segment))
}

function getLineNumber(source: string, index: number): number {
  return source.slice(0, index).split('\n').length
}

const files = (await collectVueFiles(viewsRoot)).filter(isBusinessView)
const violations: Violation[] = []
const strictPolicyViolations: PolicyFinding[] = []
const modernizationWarnings: PolicyFinding[] = []

function collectFindings(
  source: string,
  file: string,
  pattern: RegExp,
  policy: string,
  target: PolicyFinding[]
): void {
  for (const match of source.matchAll(pattern)) {
    target.push({
      policy,
      file: path.relative(projectRoot, file).replaceAll(path.sep, '/'),
      line: getLineNumber(source, match.index)
    })
  }
}

for (const file of files) {
  const source = (await fs.readFile(file, 'utf8')).replace(/<!--[\s\S]*?-->/g, (comment) =>
    comment.replace(/[^\n]/g, ' ')
  )
  for (const match of source.matchAll(rawBusinessComponentPattern)) {
    const component = match[1] ?? match[2]
    violations.push({
      component: `El${component[0].toUpperCase()}${component.slice(1)}`,
      file: path.relative(projectRoot, file).replaceAll(path.sep, '/'),
      line: getLineNumber(source, match.index)
    })
  }

  collectFindings(
    source,
    file,
    fixedOverlaySizePattern,
    '弹层使用固定像素尺寸',
    strictPolicyViolations
  )
  collectFindings(
    source,
    file,
    rawDescriptionsPattern,
    '详情信息直接使用 ElDescriptions',
    strictPolicyViolations
  )
  collectFindings(
    source,
    file,
    rawMessageBoxPromptPattern,
    '原因或文本输入直接使用 ElMessageBox.prompt',
    strictPolicyViolations
  )
  collectFindings(
    source,
    file,
    rawMessageBoxConfirmPattern,
    '操作确认直接使用 ElMessageBox.confirm',
    strictPolicyViolations
  )
  collectFindings(
    source,
    file,
    nativeScrollPattern,
    '页面仍使用原生滚动容器',
    modernizationWarnings
  )
  collectFindings(
    source,
    file,
    hardcodedRadiusPattern,
    '页面仍使用硬编码圆角',
    modernizationWarnings
  )
}

if (violations.length || strictPolicyViolations.length) {
  console.error(
    'UI 审计失败：业务页面必须使用 Art 容器、ArtDescriptions、useArtFeedback，并使用弹层尺寸预设。'
  )
  for (const violation of violations) {
    console.error(`- ${violation.file}:${violation.line} 直接使用 ${violation.component}`)
  }
  for (const finding of strictPolicyViolations) {
    console.error(`- ${finding.file}:${finding.line} ${finding.policy}`)
  }
  process.exitCode = 1
} else {
  console.log(
    `UI 审计通过：已检查 ${files.length} 个业务 Vue 文件，业务容器、详情展示、文本反馈与弹层尺寸均符合 Art 规范。`
  )
}

if (modernizationWarnings.length) {
  const warningCounts = modernizationWarnings.reduce<Record<string, number>>((counts, finding) => {
    counts[finding.policy] = (counts[finding.policy] ?? 0) + 1
    return counts
  }, {})
  console.warn(
    `UI 渐进优化项：${Object.entries(warningCounts)
      .map(([policy, count]) => `${policy} ${count} 处`)
      .join('；')}。`
  )

  if (process.argv.includes('--verbose')) {
    for (const finding of modernizationWarnings) {
      console.warn(`- ${finding.file}:${finding.line} ${finding.policy}`)
    }
  }
}
