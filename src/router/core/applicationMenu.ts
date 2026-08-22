import type { ApplicationCode } from '@/config/application'
import type { AppRouteRecord } from '@/types/router'

/**
 * 独立应用已经通过应用切换器表明自身身份，不再重复显示应用壳目录。
 * 子菜单路径必须先完成规范化，这样提升层级后仍保留 `/vms/...` 等稳定前缀。
 */
export function flattenStandaloneApplicationMenu(
  menuList: AppRouteRecord[],
  applicationCode: ApplicationCode
): AppRouteRecord[] {
  if (applicationCode === 'platform') return menuList

  const applicationRootPath = `/${applicationCode}`
  return menuList.flatMap((item) => {
    const normalizedPath = item.path.replace(/\/$/, '')
    if (normalizedPath !== applicationRootPath || !item.children?.length) {
      return [item]
    }

    return item.children
  })
}
