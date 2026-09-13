import { readdir, readFile } from 'node:fs/promises'
import path from 'node:path'
import ts from 'typescript'
import { parse as parseSfc } from '@vue/compiler-sfc'

interface HelperOccurrence {
  body: string
  file: string
  name: string
  owner: string
}

interface Finding {
  detail: string
  file: string
  rule: string
}

const projectRoot = process.cwd()
const helperName =
  /^(normalize|format|parse|build|to|is|has|map|optional|required|resolve|sanitize|coerce|ensure)[A-Z_]/
const supportedExtensions = new Set(['.ts', '.tsx', '.vue'])
const canonicalDeclarations = new Map<string, string>([
  ['normalizeNonNullableText', 'src/utils/form/normalize.ts'],
  ['normalizeNullableText', 'src/utils/form/normalize.ts'],
  ['normalizeNullableNumber', 'src/utils/form/normalize.ts'],
  ['normalizeStringList', 'src/utils/form/normalize.ts'],
  ['formatTenantLabel', 'src/utils/tenant-display.ts'],
  ['formatCnyCurrencyValue', 'src/utils/ui/format.ts'],
  ['formatDateTimeValue', 'src/utils/ui/format.ts'],
  ['formatPercentValue', 'src/utils/ui/format.ts'],
  ['createDateTimeFormatter', 'src/utils/ui/format.ts']
])

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

async function collectFrontendFiles(): Promise<string[]> {
  const files = await collectFiles(path.join(projectRoot, 'src'))
  const moduleEntries = await readdir(path.join(projectRoot, 'modules'), { withFileTypes: true })
  for (const entry of moduleEntries.filter((item) => item.isDirectory())) {
    const sourceRoot = path.join(projectRoot, 'modules', entry.name, 'src')
    try {
      files.push(...(await collectFiles(sourceRoot)))
    } catch {
      // Some optional repositories intentionally have no frontend source directory.
    }
  }
  return files
}

function relativeFile(file: string): string {
  return path.relative(projectRoot, file).replaceAll('\\', '/')
}

function ownerOf(file: string): string {
  const segments = relativeFile(file).split('/')
  return segments[0] === 'modules' ? segments[1] : 'root'
}

function normalizeBody(body: ts.Node, source: ts.SourceFile): string {
  return body
    .getText(source)
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\/\/[^\r\n]*/g, '')
    .replace(/\s+/g, '')
}

function collectScriptHelpers(
  content: string,
  file: string,
  occurrences: HelperOccurrence[],
  findings: Finding[]
): void {
  const relative = relativeFile(file)
  const source = ts.createSourceFile(file, content, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX)

  const add = (name: string, body: ts.Node): void => {
    const canonicalFile = canonicalDeclarations.get(name)
    if (canonicalFile === relative) foundCanonicalDeclarations.add(name)
    if (canonicalFile && canonicalFile !== relative) {
      findings.push({
        file: relative,
        rule: 'canonical-helper-redeclared',
        detail: `${name} 必须从主仓 ${canonicalFile} 导入，不能在子仓或页面重复声明。`
      })
    }

    const normalized = normalizeBody(body, source)
    if (helperName.test(name) && normalized.length >= 18) {
      occurrences.push({ body: normalized, file: relative, name, owner: ownerOf(file) })
    }
  }

  for (const statement of source.statements) {
    if (ts.isFunctionDeclaration(statement) && statement.name && statement.body) {
      add(statement.name.text, statement.body)
      continue
    }
    if (!ts.isVariableStatement(statement)) continue
    for (const declaration of statement.declarationList.declarations) {
      if (
        ts.isIdentifier(declaration.name) &&
        declaration.initializer &&
        (ts.isArrowFunction(declaration.initializer) ||
          ts.isFunctionExpression(declaration.initializer))
      ) {
        add(declaration.name.text, declaration.initializer.body)
      }
    }
  }
}

const files = await collectFrontendFiles()
const findings: Finding[] = []
const helpers: HelperOccurrence[] = []
const foundCanonicalDeclarations = new Set<string>()
const moduleEntries = await readdir(path.join(projectRoot, 'modules'), { withFileTypes: true })

for (const entry of moduleEntries.filter((item) => item.isDirectory())) {
  const configFile = path.join(projectRoot, 'modules', entry.name, 'tsconfig.json')
  try {
    const config = JSON.parse(await readFile(configFile, 'utf8')) as {
      compilerOptions?: { paths?: Record<string, string[]> }
    }
    for (const [alias, candidates] of Object.entries(config.compilerOptions?.paths ?? {})) {
      const workspaceIndex = candidates.findIndex((candidate) => candidate.startsWith('../../src'))
      const packageIndex = candidates.findIndex((candidate) =>
        candidate.startsWith('node_modules/art-supabase-pro/src')
      )
      if (workspaceIndex !== -1 && packageIndex !== -1 && workspaceIndex > packageIndex) {
        findings.push({
          file: relativeFile(configFile),
          rule: 'main-repository-resolution-order',
          detail: `${alias} 必须先解析当前工作区主仓，再回退到 node_modules 发布包。`
        })
      }
    }
  } catch {
    // Optional repositories without a TypeScript config are outside this frontend audit.
  }
}

for (const file of files) {
  const content = await readFile(file, 'utf8')
  const relative = relativeFile(file)
  if (/\.trim\(\)\s*\|\|\s*null/.test(content)) {
    findings.push({
      file: relative,
      rule: 'raw-nullable-text-normalization',
      detail: '请按数据库列语义使用 normalizeNullableText 或 normalizeNonNullableText。'
    })
  }

  if (file.endsWith('.vue')) {
    const { descriptor } = parseSfc(content, { filename: file })
    for (const block of [descriptor.script, descriptor.scriptSetup]) {
      if (block) collectScriptHelpers(block.content, file, helpers, findings)
    }
  } else {
    collectScriptHelpers(content, file, helpers, findings)
  }
}

for (const [name, canonicalFile] of canonicalDeclarations) {
  if (!foundCanonicalDeclarations.has(name)) {
    findings.push({
      file: canonicalFile,
      rule: 'canonical-helper-missing',
      detail: `${name} 的主仓实现缺失；不能只保留调用方或自引用导入。`
    })
  }
}

const duplicateGroups = new Map<string, HelperOccurrence[]>()
for (const helper of helpers) {
  const key = `${helper.name}\0${helper.body}`
  duplicateGroups.set(key, [...(duplicateGroups.get(key) ?? []), helper])
}

for (const group of duplicateGroups.values()) {
  if (new Set(group.map((item) => item.owner)).size < 2) continue
  findings.push({
    file: group[0].file,
    rule: 'cross-repository-helper-duplication',
    detail: `${group[0].name} 在 ${group.map((item) => item.file).join('、')} 重复实现；请上收主仓共享模块后迁移全部调用。`
  })
}

if (findings.length) {
  console.error(`Shared reuse audit failed with ${findings.length} finding(s):`)
  findings.forEach((finding) =>
    console.error(`- [${finding.rule}] ${finding.file}: ${finding.detail}`)
  )
  process.exitCode = 1
} else {
  console.log(`Shared reuse audit passed (${files.length} frontend source files checked).`)
}
