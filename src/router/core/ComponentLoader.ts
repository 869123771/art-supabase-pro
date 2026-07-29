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

export class ComponentLoader {
  private modules: Record<string, RouteComponentLoader>

  constructor() {
    // 动态导入 views 目录下所有 .vue 组件
    this.modules = import.meta.glob<RouteComponentModule>('../../views/**/*.vue')
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
