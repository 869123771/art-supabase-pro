import type { Router } from 'vue-router'

const RECOVERY_QUERY_KEY = '__route_reload'
const RECOVERY_STORAGE_KEY = 'art-route-module-recovery'
const RECOVERY_TTL = 60_000
const MAX_RECOVERY_ATTEMPTS = 2
const MODULE_LOAD_ERROR_PATTERNS = [
  'Failed to fetch dynamically imported module',
  'Importing a module script failed',
  'error loading dynamically imported module',
  'Unable to preload CSS'
]

interface RouteRecoveryState {
  path: string
  timestamp: number
  attempts: number
}

export function setupRouteErrorRecovery(router: Router): void {
  removeRecoveryQuery()

  router.onError((error, to) => {
    if (!isModuleLoadError(error)) return

    const recoveryState = createRecoveryState(to.fullPath)
    if (!recoveryState) return
    sessionStorage.setItem(RECOVERY_STORAGE_KEY, JSON.stringify(recoveryState))

    reloadAtRoute(to.fullPath)
  })

  router.afterEach((_to, _from, failure) => {
    if (failure) return

    sessionStorage.removeItem(RECOVERY_STORAGE_KEY)
    removeRecoveryQuery()
  })
}

function reloadAtRoute(path: string): void {
  const recoveryUrl = new URL(window.location.href)
  recoveryUrl.hash = path
  recoveryUrl.searchParams.delete(RECOVERY_QUERY_KEY)
  window.history.replaceState(window.history.state, '', recoveryUrl)
  window.location.reload()
}

function isModuleLoadError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error)
  return MODULE_LOAD_ERROR_PATTERNS.some((pattern) => message.includes(pattern))
}

function createRecoveryState(path: string): RouteRecoveryState | undefined {
  const recoveryState = readRecoveryState()
  if (
    recoveryState &&
    recoveryState.path === path &&
    Date.now() - recoveryState.timestamp <= RECOVERY_TTL
  ) {
    if (recoveryState.attempts >= MAX_RECOVERY_ATTEMPTS) return undefined
    return { ...recoveryState, timestamp: Date.now(), attempts: recoveryState.attempts + 1 }
  }

  return { path, timestamp: Date.now(), attempts: 1 }
}

function readRecoveryState(): RouteRecoveryState | undefined {
  const storedValue = sessionStorage.getItem(RECOVERY_STORAGE_KEY)
  if (!storedValue) return undefined

  try {
    const parsedValue = JSON.parse(storedValue) as Partial<RouteRecoveryState>
    if (!parsedValue.path || !parsedValue.timestamp) return undefined
    return { ...parsedValue, attempts: parsedValue.attempts ?? 1 } as RouteRecoveryState
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
