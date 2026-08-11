<template>
  <div class="flex w-full h-screen">
    <LoginLeftView />

    <div class="relative flex-1">
      <AuthTopBar />

      <div class="auth-right-wrap">
        <div class="form">
          <h3 class="title">{{ $t('resetPassword.title') }}</h3>
          <p class="sub-title">{{ $t('resetPassword.subTitle') }}</p>
          <div class="mt-5">
            <ElForm ref="formRef" :model="form" :rules="rules">
              <ElFormItem prop="password">
                <ElInput
                  class="custom-height"
                  v-model.trim="form.password"
                  name="password"
                  :placeholder="$t('register.placeholder.password')"
                  type="password"
                  autocomplete="new-password"
                  :aria-label="$t('register.placeholder.password')"
                  show-password
                />
              </ElFormItem>

              <ElFormItem prop="confirmPassword">
                <ElInput
                  class="custom-height"
                  v-model.trim="form.confirmPassword"
                  name="confirmPassword"
                  :placeholder="$t('register.placeholder.confirmPassword')"
                  type="password"
                  autocomplete="new-password"
                  :aria-label="$t('register.placeholder.confirmPassword')"
                  @keyup.enter="handleSubmit"
                  show-password
                />
              </ElFormItem>
            </ElForm>
          </div>

          <div class="mt-[15px]">
            <ElButton
              class="w-full custom-height"
              type="primary"
              @click="handleSubmit"
              :loading="loading"
              v-ripple
            >
              {{ $t('resetPassword.submitBtnText') }}
            </ElButton>
          </div>

          <div class="mt-[15px]">
            <ElButton class="w-full custom-height" plain @click="toLogin">
              {{ $t('resetPassword.backBtnText') }}
            </ElButton>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import type { FormInstance, FormRules } from 'element-plus'
  import { useI18n } from 'vue-i18n'
  import { resetPassword } from '@/api/auth'
  import { useSystemParam } from '@/hooks'

  defineOptions({ name: 'ResetPassword' })

  const { t } = useI18n()
  const router = useRouter()
  const {
    passwordMinLength,
    loadPasswordPolicy,
    getPasswordMinLengthMessage,
    getPasswordComplexityMessage,
    validatePasswordComplexity
  } = useSystemParam()

  const loading = ref(false)

  const formRef = ref<FormInstance>()
  interface SupabaseResetParams {
    accessToken: string
    refreshToken: string
  }

  const form = ref({
    password: '',
    confirmPassword: ''
  })

  const rules = computed<FormRules<{ password: string; confirmPassword: string }>>(() => ({
    password: [
      { required: true, validator: validatePassword, trigger: 'change' },
      {
        min: passwordMinLength.value,
        message: getPasswordMinLengthMessage(t),
        trigger: 'change'
      }
    ],
    confirmPassword: [{ required: true, validator: validateConfirmPassword, trigger: 'change' }]
  }))

  onMounted(() => {
    void loadPasswordPolicy().then(() => {
      if (form.value.password) {
        void formRef.value?.validateField('password')
      }
    })
  })

  /**
   * 验证密码
   * 当密码输入后，如果确认密码已填写，则触发确认密码的验证
   */
  const validatePassword = (_rule: unknown, value: string, callback: (error?: Error) => void) => {
    if (!value) {
      callback(new Error(t('register.placeholder.password')))
      return
    }

    if (form.value.confirmPassword) {
      formRef.value?.validateField('confirmPassword')
    }

    if (!validatePasswordComplexity(value)) {
      callback(new Error(getPasswordComplexityMessage(t)))
      return
    }

    callback()
  }

  /**
   * 验证确认密码
   * 检查确认密码是否与密码一致
   */
  const validateConfirmPassword = (
    _rule: unknown,
    value: string,
    callback: (error?: Error) => void
  ) => {
    if (!value) {
      callback(new Error(t('register.rule.confirmPasswordRequired')))
      return
    }

    if (value !== form.value.password) {
      callback(new Error(t('register.rule.passwordMismatch')))
      return
    }

    callback()
  }

  const handleSubmit = async () => {
    await formRef.value?.validate()
    try {
      loading.value = true
      const resetParams = parseSupabaseResetParams()
      if (!resetParams) {
        ElMessage.error('无效或已过期的重置链接')
        return
      }
      const params: Api.Auth.ResetPwdParams = {
        password: form.value.password,
        accessToken: resetParams.accessToken,
        refreshToken: resetParams.refreshToken
      }
      const { error } = await resetPassword(params)
      if (!error) {
        window.history.replaceState(
          {},
          document.title,
          `${window.location.pathname}#/auth/reset-password`
        )
        ElMessage.success('密码重置成功,请前往登录')
        toLogin()
      }
    } finally {
      loading.value = false
    }
  }

  /**
   * 解析 Vue hash 路由 + Supabase token 的复杂 URL
   * @returns {Object} 包含 access_token, expires_at, type 等参数
   */
  const parseSupabaseResetParams = (): SupabaseResetParams | null => {
    // 获取完整 hash，例如 "#/auth/reset-password#access_token=eyJhbGci..."
    const fullHash = window.location.hash

    // 查找最后一个 '#' 的位置
    const lastHashIndex = fullHash.lastIndexOf('#')

    if (lastHashIndex === -1 || lastHashIndex === fullHash.length - 1) {
      return null
    }

    // 提取真正的查询参数部分
    // 例如: "#access_token=eyJhbGci..." -> "access_token=eyJhbGci..."
    const paramsPart = fullHash.substring(lastHashIndex + 1)

    try {
      // 使用 URLSearchParams 解析
      const params = new URLSearchParams(paramsPart)

      // 提取关键参数
      const accessToken = params.get('access_token')
      const type = params.get('type')
      const expiresAt = params.get('expires_at')
      const refreshToken = params.get('refresh_token')

      // 验证必要参数
      if (!accessToken || !type) {
        return null
      }

      // 检查是否为重置密码类型
      if (type !== 'recovery') {
        return null
      }

      // 检查过期时间
      if (expiresAt) {
        const expiresTimestamp = parseInt(expiresAt) * 1000 // 转换为毫秒
        if (Date.now() > expiresTimestamp) {
          return null
        }
      }

      return {
        accessToken,
        refreshToken: refreshToken || ''
      }
    } catch {
      return null
    }
  }

  const toLogin = () => {
    router.push({ name: 'Login' })
  }
</script>

<style scoped>
  @import '../login/style.css';
</style>
