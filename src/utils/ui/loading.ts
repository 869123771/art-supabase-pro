/**
 * 全局 Loading 加载管理模块
 *
 * 提供统一的全屏加载动画管理
 *
 * ## 主要功能
 *
 * - 全屏 Loading 显示和隐藏
 * - 自动适配明暗主题背景色
 * - 品牌化 SVG 加载动画
 * - 单例模式防止重复创建
 * - 锁定页面交互
 *
 * ## 使用场景
 *
 * - 页面初始化加载
 * - 大量数据请求
 * - 路由切换过渡
 * - 异步操作等待
 *
 * ## 特性
 *
 * - 自动检测当前主题并应用对应背景色
 * - 使用品牌轨迹 SVG 与完整状态文案
 * - 单例模式确保同时只有一个 Loading
 * - 提供便捷的显示/隐藏方法
 *
 * @module utils/ui/loading
 * @author Art Design Pro Team
 */
import { brandLoaderSvg } from '@/assets/svg/loading'

/**
 * 获取当前主题对应的loading背景色
 * @returns 背景色字符串
 */
const getLoadingBackground = (): string => {
  const isDark = document.documentElement.classList.contains('dark')
  return isDark ? 'rgba(7, 8, 18, 0.97)' : 'rgba(247, 249, 255, 0.98)'
}

const getLoadingTitle = (): string => document.title.trim() || 'Art Supabase Pro'

const DEFAULT_LOADING_CONFIG = {
  lock: true,
  get background() {
    return getLoadingBackground()
  },
  svg: brandLoaderSvg,
  svgViewBox: '0 0 96 96',
  customClass: 'art-loading-fix art-global-loading'
} as const

interface LoadingInstance {
  close: () => void
  $el?: HTMLElement
}

let loadingInstance: LoadingInstance | null = null

export const loadingService = {
  /**
   * 显示 loading
   * @returns 关闭 loading 的函数
   */
  showLoading(): () => void {
    if (!loadingInstance) {
      // 每次显示时获取最新的配置，确保背景色与当前主题同步
      const config = {
        ...DEFAULT_LOADING_CONFIG,
        background: getLoadingBackground(),
        text: getLoadingTitle()
      }
      loadingInstance = ElLoading.service(config)
      loadingInstance.$el?.setAttribute('role', 'status')
      loadingInstance.$el?.setAttribute('aria-live', 'polite')
      loadingInstance.$el?.setAttribute('aria-label', '系统正在加载，请稍候')
    }
    return () => this.hideLoading()
  },

  /**
   * 隐藏 loading
   */
  hideLoading(): void {
    if (loadingInstance) {
      loadingInstance.close()
      loadingInstance = null
    }
  }
}
