const PLATFORM_CONTROL_PLANE_ROUTES = new Set(['/system/tenant'])

interface TenantScopeAccessPolicyInput {
  isAllTenants: boolean
  isPlatformSuper: boolean
  routePath: string
}

/** Resolve the aggregate-scope write guard without conflating it with button permissions. */
export function resolveTenantScopeReadOnly({
  isAllTenants,
  isPlatformSuper,
  routePath
}: TenantScopeAccessPolicyInput): boolean {
  return isAllTenants && !isPlatformSuper && !PLATFORM_CONTROL_PLANE_ROUTES.has(routePath)
}
