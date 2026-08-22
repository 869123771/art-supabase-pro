/**
 * Runtime identity for the independently deployable applications.
 *
 * Authentication, tenants and RBAC stay in the platform Supabase project. Each
 * frontend declares only its own application code and requests the matching
 * menu tree from the platform contract.
 */
export const APPLICATION_CODES = ['platform', 'finance', 'fms', 'hr', 'smis', 'vms'] as const

export type ApplicationCode = (typeof APPLICATION_CODES)[number]

export interface ApplicationProfile {
  code: ApplicationCode
  name: string
  description: string
  defaultPath: string
  developmentPort: number
}

export const APPLICATION_PROFILES: Record<ApplicationCode, ApplicationProfile> = {
  platform: {
    code: 'platform',
    name: 'Art Supabase Platform',
    description: '系统、租户、菜单、权限与数据中心基座',
    defaultPath: '/dashboard',
    developmentPort: 3006
  },
  finance: {
    code: 'finance',
    name: 'Art Supabase Finance',
    description: '独立财务应用预留仓',
    defaultPath: '/finance',
    developmentPort: 3011
  },
  fms: {
    code: 'fms',
    name: 'Art Supabase FMS',
    description: '财务管理系统',
    defaultPath: '/fms',
    developmentPort: 3012
  },
  hr: {
    code: 'hr',
    name: 'Art Supabase HR',
    description: '人力资源管理系统',
    defaultPath: '/hr',
    developmentPort: 3013
  },
  smis: {
    code: 'smis',
    name: 'Art Supabase SMIS',
    description: '安全生产管理系统',
    defaultPath: '/smis',
    developmentPort: 3014
  },
  vms: {
    code: 'vms',
    name: 'Art Supabase VMS',
    description: '车辆管理系统',
    defaultPath: '/vms/vehicle-archive-manage',
    developmentPort: 3015
  }
}

export function resolveApplicationCode(value: string | undefined): ApplicationCode {
  const normalized = value?.trim().toLowerCase()
  return APPLICATION_CODES.includes(normalized as ApplicationCode)
    ? (normalized as ApplicationCode)
    : 'platform'
}

export function resolveHostedApplicationCodes(
  applicationCode: ApplicationCode,
  accessibleApplications: ReadonlyArray<{ code: ApplicationCode }>
): ApplicationCode[] {
  if (applicationCode !== 'platform') return [applicationCode]

  const accessibleCodes = new Set<ApplicationCode>([
    'platform',
    ...accessibleApplications.map((application) => application.code)
  ])
  return APPLICATION_CODES.filter((code) => accessibleCodes.has(code))
}

const runtimeEnv = (import.meta as ImportMeta & { env?: ImportMetaEnv }).env

export const currentApplication = Object.freeze(
  APPLICATION_PROFILES[resolveApplicationCode(runtimeEnv?.VITE_APP_CODE)]
)
