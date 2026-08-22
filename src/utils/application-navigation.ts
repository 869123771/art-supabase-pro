import { fetchAccessibleApplications } from '@/api/system-manage'
import type { ApplicationCode } from '@/config/application'

export async function navigateToApplication(
  applicationCode: ApplicationCode,
  routePath: string,
  query?: Record<string, string | undefined>
): Promise<void> {
  const { data, error } = await fetchAccessibleApplications()
  if (error) throw error

  const application = data?.find((item) => item.code === applicationCode)
  if (!application) {
    throw new Error('当前账号没有目标应用的访问权限')
  }

  const routeQuery = new URLSearchParams()
  Object.entries(query ?? {}).forEach(([key, value]) => {
    if (value) routeQuery.set(key, value)
  })

  const target = new URL(application.baseUrl, window.location.origin)
  const normalizedPath = routePath.startsWith('/') ? routePath : `/${routePath}`
  target.hash = `${normalizedPath}${routeQuery.size ? `?${routeQuery.toString()}` : ''}`
  window.location.assign(target.toString())
}
