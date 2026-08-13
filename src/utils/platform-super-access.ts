const PLATFORM_TENANT_BUILTIN_TYPE = 'platform'
const PLATFORM_SUPER_ROLE_CODE = 'R_SUPER'

export interface PlatformSuperProfile {
  platformSuper?: boolean
  status?: string
  userRoles?: string[]
  tenant?: {
    builtinType?: Api.SystemManage.TenantBuiltinType | null
  } | null
}

/**
 * Resolve the UI capability from the authoritative RPC result first.
 * Older persisted sessions may not contain `platformSuper`, so the already-loaded
 * protected tenant/role profile is used only while the explicit capability is absent.
 * Supabase RLS remains the write authorization boundary.
 */
export function hasPlatformSuperAccess(profile: PlatformSuperProfile): boolean {
  if (typeof profile.platformSuper === 'boolean') return profile.platformSuper

  return (
    profile.status === '1' &&
    profile.tenant?.builtinType === PLATFORM_TENANT_BUILTIN_TYPE &&
    profile.userRoles?.includes(PLATFORM_SUPER_ROLE_CODE) === true
  )
}
