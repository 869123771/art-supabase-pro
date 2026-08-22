/**
 * 组件加载器
 *
 * 负责动态加载 Vue 组件
 *
 * @module router/core/ComponentLoader
 * @author Art Design Pro Team
 */

import { h, type Component } from 'vue'

type AsyncRouteComponent = () => Promise<Component>
type RouteComponentModule = { default: Component }
type RouteComponentLoader = () => Promise<RouteComponentModule>

export function mapApplicationViewModules(
  applicationCode: string,
  sourceRoot: string,
  sourceModules: Record<string, RouteComponentLoader>
): Record<string, RouteComponentLoader> {
  const normalizedRoot = sourceRoot.replace(/\/$/, '')

  return Object.fromEntries(
    Object.entries(sourceModules).map(([sourcePath, loader]) => {
      const relativeViewPath = sourcePath.slice(normalizedRoot.length)
      return [`../../views/${applicationCode}${relativeViewPath}`, loader]
    })
  )
}

export class ComponentLoader {
  private modules: Record<string, RouteComponentLoader>

  constructor() {
    // 业务模块与局部组件不作为路由入口，避免它们进入动态路由映射和首屏依赖图。
    const platformModules = import.meta.glob<RouteComponentModule>([
      '../../views/**/*.vue',
      '!../../views/**/modules/**/*.vue',
      '!../../views/**/components/**/*.vue'
    ])
    const vmsSourceRoot = '../../../modules/art-supabase-vms/src/views'
    const vmsModules = import.meta.glob<RouteComponentModule>([
      '../../../modules/art-supabase-vms/src/views/**/*.vue',
      '!../../../modules/art-supabase-vms/src/views/**/modules/**/*.vue',
      '!../../../modules/art-supabase-vms/src/views/**/components/**/*.vue'
    ])

    this.modules = {
      ...platformModules,
      ...mapApplicationViewModules('vms', vmsSourceRoot, vmsModules)
    }
  }

  /**
   * 加载组件
   */
  load(componentPath: string): AsyncRouteComponent {
    if (!componentPath) {
      return this.createEmptyComponent()
    }

    // 构建可能的路径
    const fullPath = `../../views${componentPath}.vue`
    const fullPathWithIndex = `../../views${componentPath}/index.vue`

    // 先尝试直接路径，再尝试添加/index的路径
    const module = this.modules[fullPath] || this.modules[fullPathWithIndex]

    if (!module) {
      console.error(
        `[ComponentLoader] 未找到组件: ${componentPath}，尝试过的路径: ${fullPath} 和 ${fullPathWithIndex}`
      )
      return this.createErrorComponent(componentPath)
    }

    return async () => {
      const componentModule = await module()

      return componentModule.default
    }
  }

  /**
   * 加载布局组件
   */
  loadLayout(): AsyncRouteComponent {
    return async () => {
      const componentModule = await import('@/views/index/index.vue')

      return componentModule.default
    }
  }

  /**
   * 加载 iframe 组件
   */
  loadIframe(): AsyncRouteComponent {
    return async () => {
      const componentModule = await import('@/views/outside/Iframe.vue')

      return componentModule.default
    }
  }

  /**
   * 创建空组件
   */
  private createEmptyComponent(): AsyncRouteComponent {
    return () =>
      Promise.resolve({
        render() {
          return h('div', {})
        }
      })
  }

  /**
   * 创建错误提示组件
   */
  private createErrorComponent(componentPath: string): AsyncRouteComponent {
    return () =>
      Promise.resolve({
        render() {
          return h('div', { class: 'route-error' }, `组件未找到: ${componentPath}`)
        }
      })
  }
}
