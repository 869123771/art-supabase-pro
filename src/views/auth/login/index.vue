<!-- 登录页面 -->
<template>
  <div class="flex w-full h-screen">
    <LoginLeftView />

    <div class="relative flex-1">
      <AuthTopBar />

      <div class="auth-right-wrap">
        <div class="form">
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
          <ElForm
            ref="formRef"
            :model="formData"
            :rules="rules"
            :key="formKey"
            @keyup.enter="handleSubmit"
            class="mt-[25px]"
          >
            <ElFormItem prop="email">
              <ElInput
                class="custom-height"
                :placeholder="$t('login.placeholder.email')"
                v-model.trim="formData.email"
              />
            </ElFormItem>
            <ElFormItem prop="password">
              <ElInput
                class="custom-height"
                :placeholder="$t('login.placeholder.password')"
                v-model.trim="formData.password"
                type="password"
                autocomplete="off"
                show-password
              />
            </ElFormItem>

            <ElFormItem v-if="showTurnstile" class="turnstile-form-item mt-6">
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
                {{ $t('login.btnText') }}
              </ElButton>
            </div>

            <div v-if="websiteConfig.registerEnabled" class="mt-5 text-sm text-gray-600">
              <span>{{ $t('login.noAccount') }}</span>
              <RouterLink class="text-theme" :to="{ name: 'Register' }">{{
                $t('login.register')
              }}</RouterLink>
            </div>
          </ElForm>
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
  import { login } from '@/api/auth'
  import { MenuProcessor } from '@/router/core/MenuProcessor'
  import { getFirstMenuPath } from '@/utils'
  import { useWebsiteConfig } from '@/hooks'
  import ArtTurnstileCaptcha from '@/components/core/forms/art-turnstile-captcha/index.vue'

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
    email: '624944977@qq.com',
    password: '123456',
    rememberPassword: true
  })

  const loading = ref(false)
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
    username: [{ required: true, message: t('login.placeholder.username'), trigger: 'blur' }],
    password: [{ required: true, message: t('login.placeholder.password'), trigger: 'blur' }]
  }))

  const isForbiddenRedirect = (redirect?: string): boolean => {
    if (!redirect) {
      return false
    }

    return redirect.split('?')[0] === '/403'
  }

  const resolvePostLoginPath = async (): Promise<string> => {
    const redirect = route.query.redirect as string | undefined

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

  onMounted(() => {
    void loadWebsiteConfig()
  })

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
      const { email, password } = formData

      const params: Api.Auth.RegisterParams = {
        email,
        password,
        captchaToken
      }
      const { data } = await login(params)
      const { refreshToken, accessToken } = data.session
      // 验证token
      if (!accessToken) {
        throw new Error('Login failed - no token received')
      }

      // 存储 token 和登录状态
      userStore.setToken(accessToken, refreshToken)
      userStore.setLoginStatus(true)
      await userStore.fetchUserInfo()
      await userStore.fetchDictList()
      // 登录成功处理
      showLoginSuccessNotice()

      // 获取 redirect 参数，如果存在则跳转到指定页面，否则跳转到首页
      const targetPath = await resolvePostLoginPath()
      await router.push(targetPath)
    } catch (error) {
      // 处理 HttpError
      if (error instanceof HttpError) {
        // console.log(error.code)
      } else {
        // 处理非 HttpError
        // ElMessage.error('登录失败，请稍后重试')
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
  :deep(.el-select__wrapper) {
    height: 40px !important;
  }

  :deep(.turnstile-form-item .el-form-item__content) {
    width: 100%;
  }
</style>
