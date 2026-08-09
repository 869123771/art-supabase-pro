<template>
  <ElConfigProvider
    size="default"
    :locale="locales[language]"
    :z-index="3000"
    :card="{
      shadow: 'never'
    }"
  >
    <a class="app-skip-link" href="#main-content">跳至主要内容</a>
    <RouterView v-slot="{ Component }">
      <component :is="Component" id="main-content" tabindex="-1" />
    </RouterView>
  </ElConfigProvider>
</template>

<script setup lang="ts">
  import { useUserStore } from './store/modules/user'
  import zh from 'element-plus/es/locale/lang/zh-cn'
  import en from 'element-plus/es/locale/lang/en'
  import { systemUpgrade } from './utils/sys'
  import { toggleTransition } from './utils/ui/animation'
  import { checkStorageCompatibility } from './utils/storage'
  import { initializeTheme } from './hooks/core/useTheme'
  import { useWebsiteConfig } from './hooks'
  import i18n from './locales'
  import { LanguageEnum } from './enums/appEnum'

  const userStore = useUserStore()
  const { language } = storeToRefs(userStore)
  const { loadWebsiteConfig } = useWebsiteConfig()

  const locales = {
    zh: zh,
    en: en
  }

  const resolveAppLanguage = (value?: Api.SystemManage.WebsiteDefaultLanguage): LanguageEnum => {
    return value === LanguageEnum.EN ? LanguageEnum.EN : LanguageEnum.ZH
  }

  onBeforeMount(() => {
    toggleTransition(true)
    initializeTheme()
  })

  onMounted(() => {
    void loadWebsiteConfig().then((config) => {
      if (!userStore.isLogin) {
        const appLanguage = resolveAppLanguage(config.defaultLanguage)
        language.value = appLanguage
        const globalLocale = i18n.global.locale
        if (typeof globalLocale === 'string') {
          i18n.global.locale = appLanguage
        } else {
          globalLocale.value = appLanguage
        }
      }
    })
    checkStorageCompatibility()
    toggleTransition(false)
    systemUpgrade()
  })
</script>

<style>
  .app-skip-link {
    position: fixed;
    top: 10px;
    left: 10px;
    z-index: 10000;
    padding: 9px 14px;
    color: var(--el-color-white);
    text-decoration: none;
    background: var(--el-color-primary);
    border-radius: var(--el-border-radius-base);
    box-shadow: var(--el-box-shadow-light);
    transform: translateY(-160%);
    transition: transform 0.18s ease;
  }

  .app-skip-link:focus {
    transform: translateY(0);
  }
</style>
