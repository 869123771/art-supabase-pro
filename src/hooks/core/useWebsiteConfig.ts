import { computed, readonly, ref } from 'vue'
import AppConfig from '@/config'
import { fetchWebsiteConfig } from '@/api/system-manage'
import { createWebsiteConfigDefaults } from '@/config/website-config-defaults'

type UseWebsiteConfig = Api.SystemManage.WebsiteConfigItem

const websiteConfig = ref<UseWebsiteConfig>(createWebsiteConfigDefaults())
const loading = ref(false)
const loaded = ref(false)
let pendingLoad: Promise<UseWebsiteConfig> | null = null

const mergeWebsiteConfig = (config?: Partial<UseWebsiteConfig> | null): UseWebsiteConfig => ({
  ...createWebsiteConfigDefaults(),
  ...(config ?? {})
})

const getDocumentHead = (): HTMLHeadElement | null => {
  if (typeof document === 'undefined') return null
  return document.head
}

const applyFavicon = (href?: string | null): void => {
  if (typeof document === 'undefined') return

  const head = getDocumentHead()
  if (!head) return

  const faviconHref = href?.trim()
  if (!faviconHref) return

  const iconLinks = Array.from(head.querySelectorAll<HTMLLinkElement>('link[rel~="icon"]'))
  let link = iconLinks[0]

  iconLinks.slice(1).forEach((item) => item.remove())

  if (!link) {
    link = document.createElement('link')
    head.appendChild(link)
  }

  link.rel = 'icon'
  link.removeAttribute('type')
  link.href = faviconHref
}

const applySeoMeta = (name: string, content?: string | null): void => {
  if (typeof document === 'undefined') return

  const head = getDocumentHead()
  if (!head) return

  let meta = head.querySelector<HTMLMetaElement>(`meta[name="${name}"]`)
  if (!meta) {
    meta = document.createElement('meta')
    meta.name = name
    head.appendChild(meta)
  }
  meta.content = content?.trim() || ''
}

const applyWebsiteDocument = (config = websiteConfig.value): void => {
  if (typeof document === 'undefined') return

  document.title = config.seoTitle || config.siteName || AppConfig.systemInfo.name
  applyFavicon(config.faviconUrl)
  applySeoMeta('keywords', config.seoKeywords)
  applySeoMeta('description', config.seoDescription || config.siteDescription)
}

const loadWebsiteConfig = async (force = false): Promise<UseWebsiteConfig> => {
  if (loaded.value && !force) {
    return websiteConfig.value
  }

  if (pendingLoad && !force) {
    return pendingLoad
  }

  loading.value = true
  pendingLoad = fetchWebsiteConfig()
    .then(({ data }) => {
      websiteConfig.value = mergeWebsiteConfig(data)
      loaded.value = true
      applyWebsiteDocument()
      return websiteConfig.value
    })
    .catch(() => {
      websiteConfig.value = mergeWebsiteConfig()
      loaded.value = true
      applyWebsiteDocument()
      return websiteConfig.value
    })
    .finally(() => {
      loading.value = false
      pendingLoad = null
    })

  return pendingLoad
}

const setWebsiteConfig = (config: UseWebsiteConfig): void => {
  websiteConfig.value = mergeWebsiteConfig(config)
  loaded.value = true
  applyWebsiteDocument()
}

export function useWebsiteConfig() {
  const siteName = computed(() => websiteConfig.value.siteName || AppConfig.systemInfo.name)
  const loginTitle = computed(() => websiteConfig.value.loginTitle || `欢迎使用 ${siteName.value}`)
  const loginSubtitle = computed(
    () => websiteConfig.value.loginSubtitle || websiteConfig.value.loginDescription || ''
  )

  const resolveWatermarkContent = (userInfo: Partial<Api.Auth.UserInfo> = {}): string => {
    const config = websiteConfig.value
    const displayName = userInfo.nickName || userInfo.userName || userInfo.email || '用户'

    if (config.watermarkContentType === 'username_time') {
      return `${displayName} ${new Date().toLocaleString()}`
    }

    if (config.watermarkContentType === 'site_name') {
      return siteName.value
    }

    if (config.watermarkContentType === 'custom') {
      return config.watermarkCustomText?.trim() || siteName.value
    }

    return displayName
  }

  return {
    websiteConfig: readonly(websiteConfig),
    websiteConfigLoading: readonly(loading),
    websiteConfigLoaded: readonly(loaded),
    siteName,
    loginTitle,
    loginSubtitle,
    loadWebsiteConfig,
    setWebsiteConfig,
    applyWebsiteDocument,
    resolveWatermarkContent
  }
}
