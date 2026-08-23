import { existsSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

type ModuleAction = 'pull' | 'update' | 'install' | 'check' | 'build' | 'setup'
type ModulePackageAction = 'install' | 'check' | 'build'

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')

function runCommand(command: string, args: string[], cwd = projectRoot): void {
  const result = spawnSync(command, args, {
    cwd,
    env: process.env,
    stdio: 'inherit'
  })

  if (result.error) throw result.error
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} 执行失败，退出码 ${result.status ?? 'unknown'}`)
  }
}

function runPackageManager(args: string[], cwd: string): void {
  const pnpmCliPath = process.env.npm_execpath
  if (pnpmCliPath) {
    runCommand(process.execPath, [pnpmCliPath, ...args], cwd)
    return
  }

  runCommand('pnpm', args, cwd)
}

function readModulePaths(): string[] {
  const result = spawnSync(
    'git',
    ['config', '--file', '.gitmodules', '--get-regexp', '^submodule\\..*\\.path$'],
    {
      cwd: projectRoot,
      encoding: 'utf8'
    }
  )

  if (result.error) throw result.error
  if (result.status !== 0) throw new Error('读取 .gitmodules 失败，请确认当前目录是主工程根目录。')

  return result.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => line.slice(line.indexOf(' ') + 1).trim())
}

function ensureModulesInitialized(modulePaths: string[]): void {
  const missingModules = modulePaths.filter(
    (modulePath) => !existsSync(join(projectRoot, modulePath, '.git'))
  )

  if (missingModules.length > 0) {
    throw new Error(
      `以下子工程尚未初始化：${missingModules.join('、')}。请先执行 pnpm modules:pull。`
    )
  }
}

function pullPinnedModules(): void {
  console.log('\n[module] 同步子模块配置并拉取主仓锁定版本。')
  runCommand('git', ['submodule', 'sync', '--recursive'])
  runCommand('git', ['submodule', 'update', '--init', '--recursive'])
}

function updateRemoteModules(): void {
  console.log('\n[module] 更新到各子工程配置分支的最新提交。')
  console.log('[module] 完成后主仓 gitlink 可能发生变化，请检查并提交。')
  runCommand('git', ['submodule', 'sync', '--recursive'])
  runCommand('git', ['submodule', 'update', '--init', '--recursive', '--remote'])
}

function runForModules(modulePaths: string[], action: ModulePackageAction): void {
  ensureModulesInitialized(modulePaths)

  for (const [index, modulePath] of modulePaths.entries()) {
    console.log(`\n[module ${index + 1}/${modulePaths.length}] ${modulePath} · ${action}`)
    const args = action === 'install' ? ['install', '--frozen-lockfile'] : ['run', action]
    runPackageManager(args, join(projectRoot, modulePath))
  }
}

function printUsage(): void {
  console.log(`
子工程管理命令：
  pnpm modules:pull     初始化并拉取主仓锁定的子工程版本
  pnpm modules:update   更新到各子工程远端配置分支的最新提交
  pnpm modules:install  安装全部子工程依赖
  pnpm modules:check    执行全部子工程的边界、类型、代码规范、UI 与测试门禁
  pnpm modules:build    构建全部子工程
  pnpm modules:setup    拉取锁定版本、安装依赖并构建全部子工程
`)
}

function main(): void {
  const action = process.argv[2] as ModuleAction | undefined
  if (!action || !['pull', 'update', 'install', 'check', 'build', 'setup'].includes(action)) {
    printUsage()
    if (action) process.exitCode = 1
    return
  }

  const modulePaths = readModulePaths()

  switch (action) {
    case 'pull':
      pullPinnedModules()
      break
    case 'update':
      updateRemoteModules()
      break
    case 'install':
      runForModules(modulePaths, 'install')
      break
    case 'check':
      runForModules(modulePaths, 'check')
      break
    case 'build':
      runForModules(modulePaths, 'build')
      break
    case 'setup':
      pullPinnedModules()
      runForModules(modulePaths, 'install')
      runForModules(modulePaths, 'build')
      break
  }

  console.log('\n[module] 全部操作已完成。')
}

main()
