/**
 * 导航跳转工具模块
 *
 * 提供统一的页面跳转和导航功能
 *
 * ## 主要功能
 *
 * - 外部链接打开（新窗口）
 * - 菜单项跳转处理（支持内部路由和外部链接）
 * - iframe 页面跳转支持
 * - 递归查找并跳转到第一个可见的子菜单
 * - 智能判断跳转目标类型（外部链接/内部路由）
 *
 * @module utils/navigation/jump
 * @author Art Design Pro Team
 */
import { AppRouteRecord } from '@/types/router'
import { router } from '@/router'
import { isNavigableMenuItem } from './route'

const preloadingRoutes = new Map<string, Promise<void>>()

const findFirstLeafMenu = (items: AppRouteRecord[]): AppRouteRecord | undefined => {
  for (const child of items) {
    if (isNavigableMenuItem(child)) {
      return child.children?.length ? findFirstLeafMenu(child.children) || child : child
    }
  }
  return undefined
}

/**
 * 提前加载菜单对应的异步路由组件，减少首次点击后的空等时间。
 */
export const preloadMenuRoute = (item: AppRouteRecord): Promise<void> => {
  const targetPath = item.path
  if (!targetPath || item.meta.link || item.meta.isIframe) return Promise.resolve()

  const existingTask = preloadingRoutes.get(targetPath)
  if (existingTask) return existingTask

  const resolved = router.resolve(targetPath)
  const loaders = resolved.matched.flatMap((record) =>
    Object.values(record.components ?? {}).filter(
      (component): component is () => Promise<unknown> => typeof component === 'function'
    )
  )

  const task = Promise.all(loaders.map((loader) => loader()))
    .then(() => undefined)
    .catch(() => {
      preloadingRoutes.delete(targetPath)
    })

  preloadingRoutes.set(targetPath, task)
  return task
}

/**
 * 用户准备展开目录时，优先预热其第一个可访问页面。
 * 这让冷缓存下的常见“展开目录后点击第一项”路径在点击前就开始加载。
 */
export const preloadFirstMenuRoute = (item: AppRouteRecord): Promise<void> => {
  const target = item.children?.length ? findFirstLeafMenu(item.children) : item
  return target ? preloadMenuRoute(target) : Promise.resolve()
}

// 打开外部链接
export const openExternalLink = (link: string): void => {
  window.open(link, '_blank', 'noopener,noreferrer')
}

/**
 * 菜单跳转
 * @param item 菜单项
 * @param jumpToFirst 是否跳转到第一个子菜单
 * @returns
 */
export const handleMenuJump = (item: AppRouteRecord, jumpToFirst: boolean = false) => {
  // 处理外部链接
  const { link, isIframe } = item.meta
  if (link && !isIframe) {
    return openExternalLink(link)
  }

  // 如果不需要跳转到第一个子菜单，或者没有子菜单，直接跳转当前路径
  if (!jumpToFirst || !item.children?.length) {
    void preloadMenuRoute(item)
    return router.push(item.path)
  }

  const firstChild = findFirstLeafMenu(item.children)

  // 如果子菜单都不可见，则回退到父级页面自身。
  if (!firstChild) {
    return router.push(item.path)
  }

  // 如果第一个子菜单是外部链接则打开新窗口
  if (firstChild.meta?.link) {
    return openExternalLink(firstChild.meta.link)
  }

  // 跳转到子菜单路径
  void preloadMenuRoute(firstChild)
  return router.push(firstChild.path)
}
