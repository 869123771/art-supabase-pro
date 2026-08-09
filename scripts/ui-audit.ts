import { readdir, readFile } from 'node:fs/promises'
import path from 'node:path'

interface Finding {
  file: string
  line: number
  rule: string
  excerpt: string
}

const projectRoot = process.cwd()
const sourceRoot = path.join(projectRoot, 'src')
const supportedExtensions = new Set(['.vue', '.scss', '.css'])

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

function scanFile(file: string, content: string): Finding[] {
  const findings: Finding[] = []
  const rules = [
    {
      name: 'motion/no-transition-all',
      pattern: /(?:-webkit-)?transition\s*:\s*all\b/g
    },
    {
      name: 'a11y/no-static-element-click',
      pattern: /<(?:div|span)\b[^>]*@click(?:\.[\w-]+)*\s*=/gs
    }
  ]

  rules.forEach(({ name, pattern }) => {
    for (const match of content.matchAll(pattern)) {
      if (match.index == null || match[0].includes('data-ui-audit-allow')) continue
      findings.push({
        file: path.relative(projectRoot, file).replaceAll('\\', '/'),
        line: lineAt(content, match.index),
        rule: name,
        excerpt: excerptAt(content, match.index)
      })
    }
  })

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
