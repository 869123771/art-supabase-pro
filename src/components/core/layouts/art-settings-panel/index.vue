<!-- 设置面板 -->
<template>
  <div class="layout-settings">
    <SettingDrawer v-model="showDrawer" @open="handleOpen" @close="handleClose">
      <SettingHeader @close="closeDrawer" />
      <SmartLayoutPresets />

      <section class="settings-manual">
        <button
          type="button"
          class="settings-manual__toggle"
          :aria-expanded="showManualSettings"
          aria-controls="manual-settings-content"
          @click="showManualSettings = !showManualSettings"
        >
          <span>
            <ArtSvgIcon icon="ri:equalizer-3-line" />
            <strong>精细配置</strong>
            <small>逐项调整主题、导航与页面体验</small>
          </span>
          <ArtSvgIcon
            icon="ri:arrow-down-s-line"
            class="settings-manual__arrow"
            :class="{ 'is-open': showManualSettings }"
          />
        </button>

        <div v-show="showManualSettings" id="manual-settings-content" class="settings-manual__body">
          <ThemeSettings />
          <MenuLayoutSettings />
          <MenuStyleSettings />
          <ColorSettings />
          <BoxStyleSettings />
          <ContainerSettings />
          <BasicSettings />
          <SettingActions />
        </div>
      </section>
    </SettingDrawer>
  </div>
</template>

<script setup lang="ts">
  import { useSettingsPanel } from './composables/useSettingsPanel'

  import SettingDrawer from './widget/SettingDrawer.vue'
  import SettingHeader from './widget/SettingHeader.vue'
  import SmartLayoutPresets from './widget/SmartLayoutPresets.vue'
  import ThemeSettings from './widget/ThemeSettings.vue'
  import MenuLayoutSettings from './widget/MenuLayoutSettings.vue'
  import MenuStyleSettings from './widget/MenuStyleSettings.vue'
  import ColorSettings from './widget/ColorSettings.vue'
  import BoxStyleSettings from './widget/BoxStyleSettings.vue'
  import ContainerSettings from './widget/ContainerSettings.vue'
  import BasicSettings from './widget/BasicSettings.vue'
  import SettingActions from './widget/SettingActions.vue'

  defineOptions({ name: 'ArtSettingsPanel' })

  interface Props {
    /** 是否打开 */
    open?: boolean
  }

  const props = defineProps<Props>()
  const showManualSettings = ref(false)

  // 使用设置面板逻辑
  const settingsPanel = useSettingsPanel()
  const { showDrawer } = settingsPanel

  // 获取各种处理器
  const { handleOpen, handleClose, closeDrawer } = settingsPanel.useDrawerControl()
  const { initializeSettings, cleanupSettings } = settingsPanel.useSettingsInitializer()

  // 监听 props 变化
  settingsPanel.usePropsWatcher(props)

  onMounted(() => {
    initializeSettings()
  })

  onUnmounted(() => {
    cleanupSettings()
  })
</script>

<style lang="scss">
  @use './style';
</style>
