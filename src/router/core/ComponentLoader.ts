/**
 * 组件加载器
 *
 * 负责动态加载 Vue 组件
 *
 * @module router/core/ComponentLoader
 * @author Art Design Pro Team
 */

import { defineComponent, h, type Component } from 'vue'
import { APPLICATION_CODES, type ApplicationCode } from '@/config/application'

type AsyncRouteComponent = () => Promise<Component>
type RouteComponentModule = { default: Component }
type RouteComponentLoader = () => Promise<RouteComponentModule>

const registeredApplicationModules: Record<string, RouteComponentLoader> = {}
const warnedMissingHostedApplications = new Set<HostedApplicationCode>()

type HostedApplicationCode = Exclude<ApplicationCode, 'platform'>

/**
 * 复用同一路由组件正在进行或已经完成的加载任务，避免连续导航重复请求同一模块。
 * 加载失败后清除缓存，让路由恢复流程可以重新请求。
 */
export function createCachedRouteLoader(moduleLoader: RouteComponentLoader): AsyncRouteComponent {
  let loadingTask: Promise<Component> | undefined

  return () => {
    if (!loadingTask) {
      loadingTask = moduleLoader()
        .then((componentModule) => componentModule.default)
        .catch((error: unknown) => {
          loadingTask = undefined
          throw error
        })
    }

    return loadingTask
  }
}

export function resolveHostedApplicationCode(componentPath: string): HostedApplicationCode | null {
  const applicationCode = componentPath.split('/').filter(Boolean)[0]
  if (
    !applicationCode ||
    applicationCode === 'platform' ||
    !APPLICATION_CODES.includes(applicationCode as ApplicationCode)
  ) {
    return null
  }

  return applicationCode as HostedApplicationCode
}

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

export function registerApplicationViewModules(
  applicationCode: string,
  sourceRoot: string,
  sourceModules: Record<string, RouteComponentLoader>
): Record<string, RouteComponentLoader> {
  const mappedModules = mapApplicationViewModules(applicationCode, sourceRoot, sourceModules)
  Object.assign(registeredApplicationModules, mappedModules)
  return mappedModules
}

export class ComponentLoader {
  private modules: Record<string, RouteComponentLoader>

  constructor() {
    // 业务模块与局部组件不作为路由入口，避免它们进入动态路由映射和首屏依赖图。
    const isPlatformHost = import.meta.env.VITE_APP_CODE === 'platform'
    const platformHostModules = isPlatformHost
      ? import.meta.glob<RouteComponentModule>([
          '../../views/**/*.vue',
          '!../../views/**/modules/**/*.vue',
          '!../../views/**/components/**/*.vue'
        ])
      : {}
    const platformShellModules = import.meta.glob<RouteComponentModule>([
      '../../views/auth/**/*.vue',
      '../../views/exception/**/*.vue',
      '../../views/index/**/*.vue',
      '../../views/outside/**/*.vue'
    ])
    const platformModules = isPlatformHost ? platformHostModules : platformShellModules
    this.modules = {
      ...platformModules,
      ...registeredApplicationModules
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
      const hostedApplicationCode = resolveHostedApplicationCode(componentPath)
      if (hostedApplicationCode) {
        if (!warnedMissingHostedApplications.has(hostedApplicationCode)) {
          warnedMissingHostedApplications.add(hostedApplicationCode)
          console.warn(
            `[ComponentLoader] ${hostedApplicationCode.toUpperCase()} 子模块未装载，相关授权菜单将使用缺失模块提示页`
          )
        }
        return this.createErrorComponent(componentPath)
      }

      console.error(
        `[ComponentLoader] 未找到组件: ${componentPath}，尝试过的路径: ${fullPath} 和 ${fullPathWithIndex}`
      )
      return this.createErrorComponent(componentPath)
    }

    return createCachedRouteLoader(module)
  }

  /**
   * 加载布局组件
   */
  loadLayout(): AsyncRouteComponent {
    return createCachedRouteLoader(() => import('@/views/index/index.vue'))
  }

  /**
   * 加载 iframe 组件
   */
  loadIframe(): AsyncRouteComponent {
    return createCachedRouteLoader(() => import('@/views/outside/Iframe.vue'))
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
    const applicationCode = resolveHostedApplicationCode(componentPath)
    if (applicationCode) {
      return async () => {
        const { default: ModuleUnavailable } =
          await import('@/views/exception/module-unavailable/index.vue')

        return defineComponent({
          name: 'HostedModuleUnavailableRoute',
          render: () => h(ModuleUnavailable, { applicationCode, componentPath })
        })
      }
    }

    return () =>
      Promise.resolve({
        render() {
          return h('div', { class: 'route-error' }, `组件未找到: ${componentPath}`)
        }
      })
  }
}
