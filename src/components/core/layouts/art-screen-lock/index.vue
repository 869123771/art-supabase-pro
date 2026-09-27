<!-- 锁屏 -->
<template>
  <div class="layout-lock-screen">
    <!-- 开发者工具警告覆盖层 -->
    <div v-if="showDevToolsWarning" class="lock-warning" role="alert">
      <div class="lock-warning__panel">
        <span class="lock-warning__symbol" aria-hidden="true">
          <ElIcon><WarningFilled /></ElIcon>
        </span>
        <h1>{{ $t('lockScreen.warning.title') }}</h1>
        <p>{{ $t('lockScreen.warning.description') }}</p>
      </div>
    </div>

    <!-- 锁屏弹窗 -->
    <ElDialog
      v-if="!isLock"
      v-model="visible"
      width="440px"
      class="lock-dialog"
      align-center
      :aria-label="$t('lockScreen.lock.title')"
      @open="handleDialogOpen"
      @closed="handleDialogClosed"
    >
      <template #header>
        <div class="lock-dialog__header">
          <span class="lock-symbol" aria-hidden="true">
            <ElIcon><Lock /></ElIcon>
          </span>
          <div class="lock-dialog__heading">
            <h2>{{ $t('lockScreen.lock.title') }}</h2>
            <p>{{ $t('lockScreen.lock.description') }}</p>
          </div>
        </div>
      </template>

      <div class="lock-identity">
        <img :src="userInfo.avatar || defaultAvatar" width="44" height="44" alt="" />
        <div class="lock-identity__text">
          <span>{{ $t('lockScreen.currentAccount') }}</span>
          <strong :title="displayName">{{ displayName }}</strong>
        </div>
      </div>

      <ArtForm
        ref="formRef"
        v-model="formData"
        custom-layout
        root-class="lock-screen-form"
        :show-reset="false"
        :show-submit="false"
        :rules="rules"
        @submit="handleLock"
      >
        <ElFormItem
          prop="password"
          for="lock-screen-password"
          :label="$t('lockScreen.lock.passwordLabel')"
          class="lock-field"
        >
          <ElInput
            id="lock-screen-password"
            ref="lockInputRef"
            v-model="formData.password"
            class="lock-input"
            type="password"
            name="lock-screen-password"
            autocomplete="new-password"
            show-password
            :placeholder="$t('lockScreen.lock.inputPlaceholder')"
          />
        </ElFormItem>
        <ElButton type="primary" native-type="submit" class="lock-submit" v-ripple>
          {{ $t('lockScreen.lock.btnText') }}
        </ElButton>
        <ElButton text class="lock-secondary" @click="visible = false">
          {{ $t('lockScreen.lock.cancelBtnText') }}
        </ElButton>
      </ArtForm>
    </ElDialog>

    <!-- 解锁界面 -->
    <main v-else class="unlock-content">
      <div class="unlock-content__brand">
        <ArtLogo :size="32" />
        <span>{{ brandName }}</span>
      </div>

      <section class="unlock-panel" aria-labelledby="unlock-title">
        <span class="lock-symbol lock-symbol--large" aria-hidden="true">
          <ElIcon><Lock /></ElIcon>
        </span>
        <h1 id="unlock-title">{{ $t('lockScreen.unlock.title') }}</h1>
        <p class="unlock-panel__description">{{ $t('lockScreen.unlock.description') }}</p>

        <div class="lock-identity">
          <img :src="userInfo.avatar || defaultAvatar" width="44" height="44" alt="" />
          <div class="lock-identity__text">
            <span>{{ $t('lockScreen.currentAccount') }}</span>
            <strong :title="displayName">{{ displayName }}</strong>
          </div>
        </div>

        <ArtForm
          ref="unlockFormRef"
          v-model="unlockForm"
          custom-layout
          root-class="lock-screen-form"
          :show-reset="false"
          :show-submit="false"
          :rules="rules"
          @submit="handleUnlock"
        >
          <ElFormItem
            prop="password"
            for="unlock-screen-password"
            :label="$t('lockScreen.unlock.passwordLabel')"
            class="lock-field"
          >
            <ElInput
              id="unlock-screen-password"
              ref="unlockInputRef"
              v-model="unlockForm.password"
              class="lock-input"
              type="password"
              name="unlock-screen-password"
              autocomplete="new-password"
              show-password
              :placeholder="$t('lockScreen.unlock.inputPlaceholder')"
              @input="unlockError = ''"
            />
          </ElFormItem>
          <p v-if="unlockError" class="unlock-error" role="alert">{{ unlockError }}</p>
          <ElButton type="primary" native-type="submit" class="lock-submit" v-ripple>
            {{ $t('lockScreen.unlock.btnText') }}
          </ElButton>
          <ElButton text class="lock-secondary" @click="toLogin">
            {{ $t('lockScreen.unlock.backBtnText') }}
          </ElButton>
        </ArtForm>
      </section>
    </main>
  </div>
</template>

<script setup lang="ts">
  import ArtForm from '@/components/core/forms/art-form/index.vue'
  import { Lock, WarningFilled } from '@element-plus/icons-vue'
  import { useScrollLock } from '@vueuse/core'
  import { ElInput, type FormRules } from 'element-plus'
  import { useI18n } from 'vue-i18n'
  import CryptoJS from 'crypto-js'
  import { useWebsiteConfig } from '@/hooks/core/useWebsiteConfig'
  import { useUserStore } from '@/store/modules/user'
  import { mittBus } from '@/utils/sys'
  import defaultAvatar from '@imgs/user/avatar.webp'

  // 国际化
  const { t } = useI18n()

  // 环境变量
  const ENCRYPT_KEY = import.meta.env.VITE_LOCK_ENCRYPT_KEY

  // Store
  const userStore = useUserStore()
  const { info: userInfo, lockPassword, isLock } = storeToRefs(userStore)
  const { brandName } = useWebsiteConfig()
  const displayName = computed(
    () =>
      userInfo.value.nickName ||
      userInfo.value.userName ||
      userInfo.value.email ||
      t('lockScreen.accountFallback')
  )
  const isBodyScrollLocked = useScrollLock(document.body)

  // 响应式数据
  const visible = ref<boolean>(false)
  const lockInputRef = ref<InstanceType<typeof ElInput>>()
  const unlockInputRef = ref<InstanceType<typeof ElInput>>()
  const showDevToolsWarning = ref<boolean>(false)
  const unlockError = ref('')

  // 表单相关
  const formRef = ref<InstanceType<typeof ArtForm>>()
  const unlockFormRef = ref<InstanceType<typeof ArtForm>>()

  const formData = reactive({
    password: ''
  })

  const unlockForm = reactive({
    password: ''
  })

  // 表单验证规则
  const rules = computed<FormRules>(() => ({
    password: [
      {
        required: true,
        message: t('lockScreen.passwordRequired'),
        trigger: 'blur'
      }
    ]
  }))

  // 检测是否为移动设备
  const isMobile = () => {
    return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(
      navigator.userAgent
    )
  }

  // 添加禁用控制台的函数
  const disableDevTools = () => {
    // 禁用右键菜单
    const handleContextMenu = (e: Event) => {
      if (isLock.value) {
        e.preventDefault()
        e.stopPropagation()
        return false
      }
    }
    document.addEventListener('contextmenu', handleContextMenu, true)

    // 禁用开发者工具相关快捷键
    const handleKeyDown = (e: KeyboardEvent) => {
      if (!isLock.value) return

      // 禁用 F12
      if (e.key === 'F12') {
        e.preventDefault()
        e.stopPropagation()
        return false
      }

      // 禁用 Ctrl+Shift+I/J/C/K (开发者工具)
      if (e.ctrlKey && e.shiftKey) {
        const key = e.key.toLowerCase()
        if (['i', 'j', 'c', 'k'].includes(key)) {
          e.preventDefault()
          e.stopPropagation()
          return false
        }
      }

      // 禁用 Ctrl+U (查看源代码)
      if (e.ctrlKey && e.key.toLowerCase() === 'u') {
        e.preventDefault()
        e.stopPropagation()
        return false
      }

      // 禁用 Ctrl+S (保存页面)
      if (e.ctrlKey && e.key.toLowerCase() === 's') {
        e.preventDefault()
        e.stopPropagation()
        return false
      }

      // 禁用 Ctrl+A (全选)
      if (e.ctrlKey && e.key.toLowerCase() === 'a') {
        e.preventDefault()
        e.stopPropagation()
        return false
      }

      // 禁用 Ctrl+P (打印)
      if (e.ctrlKey && e.key.toLowerCase() === 'p') {
        e.preventDefault()
        e.stopPropagation()
        return false
      }

      // 禁用 Ctrl+F (查找)
      if (e.ctrlKey && e.key.toLowerCase() === 'f') {
        e.preventDefault()
        e.stopPropagation()
        return false
      }

      // 禁用 Alt+Tab (切换窗口)
      if (e.altKey && e.key === 'Tab') {
        e.preventDefault()
        e.stopPropagation()
        return false
      }

      // 禁用 Ctrl+Tab (切换标签页)
      if (e.ctrlKey && e.key === 'Tab') {
        e.preventDefault()
        e.stopPropagation()
        return false
      }

      // 禁用 Ctrl+W (关闭标签页)
      if (e.ctrlKey && e.key.toLowerCase() === 'w') {
        e.preventDefault()
        e.stopPropagation()
        return false
      }

      // 禁用 Ctrl+R 和 F5 (刷新页面)
      if ((e.ctrlKey && e.key.toLowerCase() === 'r') || e.key === 'F5') {
        e.preventDefault()
        e.stopPropagation()
        return false
      }

      // 禁用 Ctrl+Shift+R (强制刷新)
      if (e.ctrlKey && e.shiftKey && e.key.toLowerCase() === 'r') {
        e.preventDefault()
        e.stopPropagation()
        return false
      }
    }
    document.addEventListener('keydown', handleKeyDown, true)

    // 禁用选择文本
    const handleSelectStart = (e: Event) => {
      if (isLock.value) {
        e.preventDefault()
        return false
      }
    }
    document.addEventListener('selectstart', handleSelectStart, true)

    // 禁用拖拽
    const handleDragStart = (e: Event) => {
      if (isLock.value) {
        e.preventDefault()
        return false
      }
    }
    document.addEventListener('dragstart', handleDragStart, true)

    // 监听开发者工具打开状态（仅在桌面端启用）
    let devtools = { open: false }
    const threshold = 160
    let devToolsInterval: ReturnType<typeof setInterval> | null = null

    const checkDevTools = () => {
      if (!isLock.value || isMobile()) return

      const isDevToolsOpen =
        window.outerHeight - window.innerHeight > threshold ||
        window.outerWidth - window.innerWidth > threshold

      if (isDevToolsOpen && !devtools.open) {
        devtools.open = true
        showDevToolsWarning.value = true
      } else if (!isDevToolsOpen && devtools.open) {
        devtools.open = false
        showDevToolsWarning.value = false
      }
    }

    // 仅在桌面端启用开发者工具检测
    if (!isMobile()) {
      devToolsInterval = setInterval(checkDevTools, 500)
    }

    // 返回清理函数
    return () => {
      document.removeEventListener('contextmenu', handleContextMenu, true)
      document.removeEventListener('keydown', handleKeyDown, true)
      document.removeEventListener('selectstart', handleSelectStart, true)
      document.removeEventListener('dragstart', handleDragStart, true)
      if (devToolsInterval) {
        clearInterval(devToolsInterval)
      }
    }
  }

  // 工具函数
  const verifyPassword = (inputPassword: string, storedPassword: string): boolean => {
    try {
      const decryptedPassword = CryptoJS.AES.decrypt(storedPassword, ENCRYPT_KEY).toString(
        CryptoJS.enc.Utf8
      )
      return inputPassword === decryptedPassword
    } catch (error) {
      console.error('密码解密失败:', error)
      return false
    }
  }

  // 事件处理函数
  const handleKeydown = (event: KeyboardEvent) => {
    if (event.altKey && event.key.toLowerCase() === '¬') {
      event.preventDefault()
      visible.value = true
    }
  }

  const handleDialogOpen = () => {
    setTimeout(() => {
      lockInputRef.value?.input?.focus()
    }, 100)
  }

  const handleDialogClosed = () => {
    formData.password = ''
    formRef.value?.clearValidate()
  }

  const handleLock = async () => {
    if (!formRef.value) return

    await formRef.value.validate((valid) => {
      if (valid) {
        const encryptedPassword = CryptoJS.AES.encrypt(formData.password, ENCRYPT_KEY).toString()
        userStore.setLockStatus(true)
        userStore.setLockPassword(encryptedPassword)
        visible.value = false
        formData.password = ''
      }
    })
  }

  const handleUnlock = async () => {
    if (!unlockFormRef.value) return

    await unlockFormRef.value.validate((valid) => {
      if (valid) {
        const isValid = verifyPassword(unlockForm.password, lockPassword.value)

        if (isValid) {
          try {
            userStore.setLockStatus(false)
            userStore.setLockPassword('')
            unlockForm.password = ''
            unlockError.value = ''
            visible.value = false
            showDevToolsWarning.value = false
          } catch (error) {
            console.error('更新store失败:', error)
          }
        } else {
          unlockError.value = t('lockScreen.pwdError')
          unlockForm.password = ''
          unlockInputRef.value?.input?.focus()
        }
      }
    })
  }

  const toLogin = () => {
    userStore.logOut()
  }

  const openLockScreen = () => {
    visible.value = true
  }

  // 监听锁屏状态变化
  watch(isLock, (newValue) => {
    if (newValue) {
      isBodyScrollLocked.value = true
      setTimeout(() => {
        unlockInputRef.value?.input?.focus()
      }, 100)
    } else {
      isBodyScrollLocked.value = false
      showDevToolsWarning.value = false
      unlockError.value = ''
    }
  })

  // 存储清理函数
  let cleanupDevTools: (() => void) | null = null

  // 生命周期钩子
  onMounted(() => {
    mittBus.on('openLockScreen', openLockScreen)
    document.addEventListener('keydown', handleKeydown)

    if (isLock.value) {
      isBodyScrollLocked.value = true
      setTimeout(() => {
        unlockInputRef.value?.input?.focus()
      }, 100)
    }

    // 初始化禁用开发者工具功能
    cleanupDevTools = disableDevTools()
  })

  onUnmounted(() => {
    mittBus.off('openLockScreen', openLockScreen)
    document.removeEventListener('keydown', handleKeydown)
    isBodyScrollLocked.value = false
    // 清理禁用开发者工具的事件监听器
    if (cleanupDevTools) {
      cleanupDevTools()
      cleanupDevTools = null
    }
  })
</script>

<style lang="scss" scoped>
  .lock-warning {
    position: fixed;
    inset: 0;
    z-index: 999999;
    display: grid;
    place-items: center;
    padding: 20px;
    background: var(--el-bg-color-page);
  }

  .lock-warning__panel {
    width: min(100%, 440px);
    padding: 36px;
    text-align: center;
    background: var(--default-box-color);
    border: 1px solid var(--art-modal-surface-border);
    border-radius: var(--art-feature-radius, 18px);
    box-shadow: var(--art-modal-surface-shadow);

    h1 {
      margin: 18px 0 8px;
      font-size: 22px;
      font-weight: 650;
      line-height: 30px;
      color: var(--el-text-color-primary);
    }

    p {
      margin: 0;
      font-size: 14px;
      line-height: 22px;
      color: var(--el-text-color-secondary);
    }
  }

  .lock-warning__symbol {
    display: inline-grid;
    place-items: center;
    width: 56px;
    height: 56px;
    font-size: 26px;
    color: var(--el-color-danger);
    background: color-mix(in srgb, var(--el-color-danger) 10%, var(--default-box-color));
    border-radius: 16px;
  }

  :global(.el-dialog.lock-dialog) {
    max-width: calc(100vw - 32px);
    border: 1px solid var(--art-modal-surface-border);
    border-radius: var(--art-feature-radius, 18px) !important;
    box-shadow: var(--art-modal-surface-shadow);
  }

  :global(.lock-dialog .el-dialog__header) {
    padding: 30px 30px 0;
    margin: 0;
  }

  :global(.lock-dialog .el-dialog__headerbtn) {
    top: 18px;
    right: 18px;
    width: 36px;
    height: 36px;
  }

  :global(.lock-dialog .el-dialog__body) {
    padding: 24px 30px 28px;
  }

  :global(.lock-screen-form.art-form) {
    padding: 0;
  }

  .lock-dialog__header {
    display: flex;
    gap: 14px;
    align-items: flex-start;
    padding-right: 28px;
  }

  .lock-dialog__heading {
    min-width: 0;

    h2 {
      margin: 0;
      font-size: 20px;
      font-weight: 650;
      line-height: 28px;
      color: var(--el-text-color-primary);
    }

    p {
      margin: 5px 0 0;
      font-size: 13px;
      line-height: 20px;
      color: var(--el-text-color-secondary);
    }
  }

  .lock-symbol {
    display: inline-grid;
    flex: none;
    place-items: center;
    width: 44px;
    height: 44px;
    font-size: 22px;
    color: var(--theme-color);
    background: color-mix(in srgb, var(--theme-color) 10%, var(--default-box-color));
    border-radius: var(--art-control-radius, 10px);

    &--large {
      width: 56px;
      height: 56px;
      margin: 0 auto;
      font-size: 26px;
      border-radius: 16px;
    }
  }

  .lock-identity {
    display: flex;
    gap: 12px;
    align-items: center;
    min-width: 0;
    padding: 12px 14px;
    background: var(--art-gray-100);
    border: 1px solid var(--art-card-border);
    border-radius: var(--art-control-radius, 10px);

    img {
      flex: none;
      width: 44px;
      height: 44px;
      object-fit: cover;
      border-radius: 50%;
    }
  }

  .lock-identity__text {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
    text-align: left;

    span {
      font-size: 12px;
      line-height: 18px;
      color: var(--el-text-color-secondary);
    }

    strong {
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 14px;
      font-weight: 600;
      line-height: 20px;
      color: var(--el-text-color-primary);
      white-space: nowrap;
    }
  }

  .lock-field {
    margin: 24px 0 20px;
  }

  .lock-field :deep(.el-form-item__label) {
    height: auto;
    padding: 0 0 8px;
    font-size: 13px;
    font-weight: 600;
    line-height: 20px;
    color: var(--el-text-color-primary);
  }

  .lock-input {
    width: 100%;
  }

  .lock-input :deep(.el-input__wrapper) {
    min-height: 46px;
    padding: 0 12px;
    border-radius: var(--art-control-radius, 10px);
  }

  .lock-submit {
    width: 100%;
    height: 46px;
    font-weight: 600;
    border-radius: var(--art-control-radius, 10px);
  }

  .lock-secondary {
    display: flex;
    width: 100%;
    height: 40px;
    margin: 10px 0 0 !important;
    color: var(--el-text-color-secondary);
  }

  .lock-secondary:focus-visible {
    outline: 2px solid var(--theme-color);
    outline-offset: 2px;
  }

  .unlock-content {
    position: fixed;
    inset: 0;
    z-index: 2500;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 80px 20px 32px;
    overflow-y: auto;
    background: color-mix(in srgb, var(--theme-color) 3%, var(--el-bg-color-page));
  }

  .unlock-content__brand {
    position: absolute;
    top: 28px;
    left: 32px;
    display: inline-flex;
    gap: 10px;
    align-items: center;
    max-width: calc(100% - 64px);
    font-size: 16px;
    font-weight: 700;
    color: var(--el-text-color-primary);

    span {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }

  .unlock-panel {
    width: min(100%, 440px);
    padding: 36px;
    margin: auto;
    text-align: center;
    background: var(--default-box-color);
    border: 1px solid var(--art-modal-surface-border);
    border-radius: var(--art-feature-radius, 18px);
    box-shadow: var(--art-modal-surface-shadow);

    h1 {
      margin: 20px 0 0;
      font-size: 24px;
      font-weight: 650;
      line-height: 32px;
      color: var(--el-text-color-primary);
    }

    .lock-identity {
      margin-top: 28px;
    }
  }

  .unlock-panel__description {
    margin: 8px 0 0;
    font-size: 13px;
    line-height: 20px;
    color: var(--el-text-color-secondary);
  }

  .unlock-error {
    margin: -8px 0 14px;
    font-size: 12px;
    line-height: 18px;
    color: var(--el-color-danger);
    text-align: left;
  }

  @media (width <= 480px) {
    :global(.lock-dialog .el-dialog__header) {
      padding: 24px 22px 0;
    }

    :global(.lock-dialog .el-dialog__body) {
      padding: 22px 22px 24px;
    }

    .unlock-content__brand {
      top: 20px;
      left: 20px;
      max-width: calc(100% - 40px);
    }

    .unlock-panel {
      padding: 30px 24px;
    }
  }
</style>
