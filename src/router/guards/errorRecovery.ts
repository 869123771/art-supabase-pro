import type { Router } from 'vue-router'

const RECOVERY_QUERY_KEY = '__route_reload'
const RECOVERY_STORAGE_KEY = 'art-route-module-recovery'
const RECOVERY_TTL = 60_000
const MODULE_LOAD_ERROR_PATTERNS = [
  'Failed to fetch dynamically imported module',
  'Importing a module script failed',
  'error loading dynamically imported module',
  'Unable to preload CSS'
]

interface RouteRecoveryState {
  path: string
  timestamp: number
}

export function setupRouteErrorRecovery(router: Router): void {
  router.onError((error, to) => {
    if (!isModuleLoadError(error) || !canRecoverRoute(to.fullPath)) return

    const recoveryState: RouteRecoveryState = {
      path: to.fullPath,
      timestamp: Date.now()
    }
    sessionStorage.setItem(RECOVERY_STORAGE_KEY, JSON.stringify(recoveryState))

    const recoveryUrl = new URL(window.location.href)
    recoveryUrl.hash = to.fullPath
    recoveryUrl.searchParams.set(RECOVERY_QUERY_KEY, String(recoveryState.timestamp))
    window.location.replace(recoveryUrl)
  })

  router.afterEach((_to, _from, failure) => {
    if (failure) return

    sessionStorage.removeItem(RECOVERY_STORAGE_KEY)
    removeRecoveryQuery()
  })
}

function isModuleLoadError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error)
  return MODULE_LOAD_ERROR_PATTERNS.some((pattern) => message.includes(pattern))
}

function canRecoverRoute(path: string): boolean {
  const recoveryState = readRecoveryState()
  if (!recoveryState) return true

  return recoveryState.path !== path || Date.now() - recoveryState.timestamp > RECOVERY_TTL
}

function readRecoveryState(): RouteRecoveryState | undefined {
  const storedValue = sessionStorage.getItem(RECOVERY_STORAGE_KEY)
  if (!storedValue) return undefined

  try {
    return JSON.parse(storedValue) as RouteRecoveryState
  } catch {
    sessionStorage.removeItem(RECOVERY_STORAGE_KEY)
    return undefined
  }
}

function removeRecoveryQuery(): void {
  const currentUrl = new URL(window.location.href)
  if (!currentUrl.searchParams.has(RECOVERY_QUERY_KEY)) return

  currentUrl.searchParams.delete(RECOVERY_QUERY_KEY)
  window.history.replaceState(window.history.state, '', currentUrl)
}
