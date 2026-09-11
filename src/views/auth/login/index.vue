<!-- 登录页面 -->
<template>
  <div class="auth-page auth-login-page">
    <LoginLeftView />

    <div class="auth-page__panel">
      <AuthTopBar />

      <div class="auth-right-wrap">
        <div class="form">
          <div class="form__eyebrow">
            <span><ArtSvgIcon icon="ri:shield-check-line" /></span>
            安全工作区
          </div>
          <h3 class="title">{{ loginTitle }}</h3>
          <p class="sub-title">{{ loginSubtitle || $t('login.subTitle') }}</p>
          <ElAlert
            v-if="websiteConfig.maintenanceEnabled"
            class="mt-4"
            type="warning"
            show-icon
            :closable="false"
            :title="websiteConfig.maintenanceMessage || '系统维护中，请稍后再试'"
          />
          <ElAlert
            v-if="oauthError"
            class="auth-oauth-error"
            type="error"
            show-icon
            :closable="true"
            :title="oauthError"
            @close="oauthError = ''"
          />
          <ElForm
            ref="formRef"
            :model="formData"
            :rules="rules"
            :key="formKey"
            @keyup.enter="handleSubmit"
            class="mt-[25px]"
          >
            <ElFormItem prop="identifier">
              <ElInput
                class="custom-height"
                :placeholder="$t('login.placeholder.identifier')"
                v-model.trim="formData.identifier"
                name="username"
                autocomplete="username"
                autocapitalize="none"
                :spellcheck="false"
                aria-label="邮箱或手机号"
              >
                <template #prefix><ArtSvgIcon icon="ri:user-3-line" /></template>
              </ElInput>
            </ElFormItem>
            <ElFormItem prop="password">
              <ElInput
                class="custom-height"
                :placeholder="$t('login.placeholder.password')"
                v-model.trim="formData.password"
                type="password"
                name="password"
                autocomplete="current-password"
                show-password
                aria-label="登录密码"
              >
                <template #prefix><ArtSvgIcon icon="ri:lock-2-line" /></template>
              </ElInput>
            </ElFormItem>

            <ElFormItem
              v-if="showTurnstile"
              class="turnstile-form-item mt-6"
              :class="{ 'is-interaction-only': turnstileAppearance === 'interaction-only' }"
            >
              <ArtTurnstileCaptcha
                ref="turnstileRef"
                :sitekey="turnstileSiteKey"
                :size="turnstileWidgetSize"
                :theme="websiteConfig.turnstileTheme || 'auto'"
                :appearance="turnstileAppearance"
                :execution="turnstileExecution"
                @verify="handleTurnstileVerify"
                @expired="resetTurnstileToken"
                @timeout="resetTurnstileToken"
                @error="resetTurnstileToken"
              />
            </ElFormItem>

            <div class="flex-cb mt-2 text-sm">
              <ElCheckbox v-model="formData.rememberPassword">{{
                $t('login.rememberPwd')
              }}</ElCheckbox>
              <RouterLink class="text-theme" :to="{ name: 'ForgetPassword' }">{{
                $t('login.forgetPwd')
              }}</RouterLink>
            </div>

            <div style="margin-top: 30px">
              <ElButton
                class="w-full custom-height"
                type="primary"
                @click="handleSubmit"
                :loading="loading"
                v-ripple
              >
                <span>{{ $t('login.btnText') }}</span>
                <ArtSvgIcon icon="ri:arrow-right-line" />
              </ElButton>
            </div>

            <div v-if="websiteConfig.registerEnabled" class="mt-5 text-sm text-gray-600">
              <span>{{ $t('login.noAccount') }}</span>
              <RouterLink class="text-theme" :to="{ name: 'Register' }">{{
                $t('login.register')
              }}</RouterLink>
            </div>
          </ElForm>

          <div v-if="enabledAuthChannels.length" class="auth-channels">
            <div class="auth-channels__divider"><span>其他方式</span></div>
            <div class="auth-channels__icons" role="group" aria-label="第三方登录方式">
              <ArtTooltip
                v-for="channel in enabledAuthChannels"
                :key="channel.key"
                :content="`${channel.label}登录`"
                placement="top"
                effect="dark"
                popper-class="auth-channel-tooltip"
                :show-after="240"
                :hide-after="0"
                :disabled="Boolean(oauthLoadingKey)"
              >
                <ElButton
                  circle
                  class="auth-channels__button"
                  :class="`is-${channel.key}`"
                  :disabled="Boolean(oauthLoadingKey || loading)"
                  :aria-label="`使用${channel.label}登录`"
                  :aria-busy="oauthLoadingKey === channel.key"
                  @click="handleAuthChannelLogin(channel)"
                >
                  <ElIcon v-if="oauthLoadingKey === channel.key" class="auth-channels__spinner">
                    <Loading />
                  </ElIcon>
                  <ArtSvgIcon v-if="oauthLoadingKey !== channel.key" :icon="channel.icon" />
                </ElButton>
              </ArtTooltip>
            </div>
            <p class="auth-channels__hint">首次使用需先在个人中心绑定</p>
          </div>

          <div class="form__trust">
            <span><ArtSvgIcon icon="ri:lock-line" /> TLS 安全连接</span>
            <i />
            <span>企业级权限隔离</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { useUserStore } from '@/store/modules/user'
  import { useI18n } from 'vue-i18n'
  import { HttpError } from '@/utils/http/error'
  import { ElMessage, ElNotification, type FormInstance, type FormRules } from 'element-plus'
  import { Loading } from '@element-plus/icons-vue'
  import {
    checkCurrentUserAccess,
    getCurrentAuthSession,
    login,
    signInWithAuthChannel
  } from '@/api/auth'
  import { MenuProcessor } from '@/router/core/MenuProcessor'
  import { getFirstMenuPath } from '@/utils'
  import { useWebsiteConfig } from '@/hooks'
  import ArtTurnstileCaptcha from '@/components/core/forms/art-turnstile-captcha/index.vue'
  import {
    isAbsoluteApplicationRedirect,
    resolveSafePostLoginRedirect
  } from '@/utils/auth-redirect'
  import { preparePostLoginData } from './modules/post-login-data'
  import { buildAuthCallbackUrl, getFriendlySupabaseErrorMessage } from '@/utils/supabase'

  defineOptions({ name: 'Login' })

  const { t, locale } = useI18n()
  const { websiteConfig, loginTitle, loginSubtitle, loadWebsiteConfig } = useWebsiteConfig()
  const formKey = ref(0)

  // 监听语言切换，重置表单
  watch(locale, () => {
    formKey.value++
  })

  type AccountKey = 'super' | 'admin' | 'user'

  export interface Account {
    key: AccountKey
    label: string
    userName: string
    password: string
    roles: string[]
  }

  const userStore = useUserStore()
  const router = useRouter()
  const route = useRoute()
  const menuProcessor = new MenuProcessor()
  const turnstileToken = ref('')
  const turnstileRef = ref<{
    reset?: () => void
    execute?: () => Promise<string>
  }>()

  const formRef = ref<FormInstance>()

  const formData = reactive({
    account: '',
    username: '',
    identifier: '624944977@qq.com',
    password: '123456',
    rememberPassword: true
  })

  const loading = ref(false)
  const oauthLoadingKey = ref('')
  const oauthError = ref('')
  const enabledAuthChannels = computed(() =>
    websiteConfig.value.authChannels.filter((channel) => channel.enabled)
  )
  const showTurnstile = computed(() => websiteConfig.value.captchaEnabled)
  const turnstileSiteKey = computed(() => websiteConfig.value.turnstileSiteKey)
  const turnstileWidgetSize = computed(() =>
    websiteConfig.value.turnstileSize === 'compact' ? 'compact' : 'flexible'
  )
  const turnstileAppearance = computed(() =>
    websiteConfig.value.turnstileSize === 'hidden' ||
    websiteConfig.value.turnstileSize === 'flexible'
      ? 'interaction-only'
      : 'always'
  )
  const turnstileExecution = computed(() =>
    turnstileAppearance.value === 'interaction-only' ? 'execute' : 'render'
  )
  const requiresVisibleTurnstileToken = computed(
    () => showTurnstile.value && turnstileAppearance.value !== 'interaction-only'
  )

  const rules = computed<FormRules>(() => ({
    identifier: [{ required: true, message: t('login.placeholder.identifier'), trigger: 'blur' }],
    password: [{ required: true, message: t('login.placeholder.password'), trigger: 'blur' }]
  }))

  const isForbiddenRedirect = (redirect?: string): boolean => {
    if (!redirect) {
      return false
    }

    return redirect.split('?')[0] === '/403'
  }

  const resolvePostLoginPath = async (): Promise<string> => {
    const requestedRedirect =
      typeof route.query.redirect === 'string' ? route.query.redirect : undefined
    const redirect = resolveSafePostLoginRedirect(requestedRedirect, window.location.origin)

    if (!redirect) {
      return '/'
    }

    if (!isForbiddenRedirect(redirect)) {
      return redirect
    }

    const menuList = await menuProcessor.getMenuList()
    if (!menuProcessor.validateMenuList(menuList)) {
      return redirect
    }

    return getFirstMenuPath(menuList) || '/'
  }

  onMounted(() => void initializeLoginPage())

  const initializeLoginPage = async (): Promise<void> => {
    await loadWebsiteConfig()
    if (route.query.auth_action === 'login') {
      await handleOAuthCallback()
    }
  }

  const completeAuthenticatedLogin = async (tokens: {
    accessToken: string
    refreshToken?: string
  }): Promise<void> => {
    userStore.setToken(tokens.accessToken, tokens.refreshToken)
    userStore.setLoginStatus(true)
    const { dictionariesReady } = await preparePostLoginData({
      loadDictionaries: userStore.fetchDictList,
      loadUserProfile: userStore.fetchUserInfo,
      onDictionaryError: (error) => {
        console.error('[Login] 基础字典初始化失败:', error)
      }
    })
    showLoginSuccessNotice()

    const targetPath = await resolvePostLoginPath()
    if (isAbsoluteApplicationRedirect(targetPath)) {
      await dictionariesReady
      window.location.replace(targetPath)
      return
    }

    await router.push(targetPath)
    void dictionariesReady
  }

  const handleOAuthCallback = async (): Promise<void> => {
    const channelKey = typeof route.query.channel === 'string' ? route.query.channel : ''
    oauthLoadingKey.value = channelKey || 'oauth'
    oauthError.value = ''
    try {
      const tokens = await getCurrentAuthSession()
      await checkCurrentUserAccess(true)
      await completeAuthenticatedLogin(tokens)
    } catch (error) {
      oauthError.value = getFriendlySupabaseErrorMessage(error, '第三方登录未完成，请重新发起登录')
      await userStore.logOut()
    } finally {
      oauthLoadingKey.value = ''
    }
  }

  const handleAuthChannelLogin = async (channel: Api.Auth.AuthChannel): Promise<void> => {
    oauthLoadingKey.value = channel.key
    oauthError.value = ''
    const requestedRedirect =
      typeof route.query.redirect === 'string' ? route.query.redirect : undefined
    const redirectTo = buildAuthCallbackUrl(
      window.location.href,
      '/auth/login',
      'login',
      channel.key,
      requestedRedirect
    )
    try {
      await signInWithAuthChannel(channel, redirectTo)
    } catch (error) {
      oauthError.value =
        error instanceof Error && error.message
          ? error.message
          : `${channel.label}登录暂时不可用，请稍后重试`
    } finally {
      oauthLoadingKey.value = ''
    }
  }

  // 登录
  const handleSubmit = async () => {
    if (!formRef.value) return

    try {
      // 表单验证
      const valid = await formRef.value.validate()
      if (!valid) return

      if (requiresVisibleTurnstileToken.value && !turnstileToken.value) {
        ElMessage.warning('请先完成人机验证')
        return
      }

      loading.value = true
      const captchaToken = await resolveCaptchaToken()

      // 登录请求
      const { identifier, password } = formData

      const params: Api.Auth.LoginParams = {
        identifier,
        password,
        captchaToken
      }
      const { data } = await login(params)
      const { refreshToken, accessToken } = data?.session ?? {}
      // 验证token
      if (!accessToken) {
        throw new Error('Login failed - no token received')
      }

      await completeAuthenticatedLogin({ accessToken, refreshToken })
    } catch (error) {
      if (!(error instanceof HttpError)) {
        console.error('[Login] Unexpected error:', error)
      }
    } finally {
      loading.value = false
      if (showTurnstile.value) {
        resetTurnstile()
      }
    }
  }

  const handleTurnstileVerify = (token: string) => {
    turnstileToken.value = token
  }

  const resetTurnstileToken = () => {
    turnstileToken.value = ''
  }

  const resetTurnstile = () => {
    resetTurnstileToken()
    turnstileRef.value?.reset?.()
  }

  const resolveCaptchaToken = async (): Promise<string | undefined> => {
    if (!showTurnstile.value) return undefined
    if (turnstileToken.value) return turnstileToken.value
    if (turnstileAppearance.value !== 'interaction-only') return undefined

    const token = await turnstileRef.value?.execute?.()
    turnstileToken.value = token || ''
    return token || undefined
  }

  // 登录成功提示
  const showLoginSuccessNotice = () => {
    const { userName, nickName, email } = userStore.getUserInfo
    const systemName = nickName || userName || email
    setTimeout(() => {
      ElNotification({
        title: t('login.success.title'),
        type: 'success',
        duration: 2500,
        zIndex: 10000,
        message: `${t('login.success.message')}, ${systemName}`
      })
    }, 1000)
  }
</script>

<style scoped>
  @import './style.css';
</style>

<style lang="scss" scoped>
  :deep(.turnstile-form-item .el-form-item__content) {
    width: 100%;
  }

  :deep(.turnstile-form-item.is-interaction-only) {
    height: 0;
    margin: 0;
    overflow: hidden;
  }
</style>

<style lang="scss">
  .auth-channel-tooltip.el-popper.is-dark {
    padding: 7px 10px;
    font-size: 12px;
    line-height: 16px;
    color: #fff;
    background: rgb(31 33 47 / 96%);
    border: 1px solid rgb(255 255 255 / 8%);
    border-radius: 7px;
    box-shadow: 0 8px 24px rgb(15 18 32 / 18%);
  }
</style>
