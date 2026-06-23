<template>
  <div class="flex w-full h-screen">
    <LoginLeftView />

    <div class="relative flex-1">
      <AuthTopBar />

      <div class="auth-right-wrap">
        <div class="form">
          <h3 class="title">{{ $t('forgetPassword.title') }}</h3>
          <p class="sub-title">{{ '输入您的新密码来完成密码重置' }}</p>
          <div class="mt-5">
            <ElForm ref="formRef" :model="form" :rules="rules">
              <ElFormItem prop="password">
                <ElInput
                  class="custom-height"
                  v-model.trim="form.password"
                  :placeholder="$t('register.placeholder.password')"
                  type="password"
                  autocomplete="off"
                  show-password
                />
              </ElFormItem>

              <ElFormItem prop="confirmPassword">
                <ElInput
                  class="custom-height"
                  v-model.trim="form.confirmPassword"
                  :placeholder="$t('register.placeholder.confirmPassword')"
                  type="password"
                  autocomplete="off"
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
              {{ $t('forgetPassword.submitBtnText') }}
            </ElButton>
          </div>

          <div class="mt-[15px]">
            <ElButton class="w-full custom-height" plain @click="toLogin">
              {{ $t('forgetPassword.backBtnText') }}
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

  defineOptions({ name: 'ForgetPassword' })

  const { t } = useI18n()
  const router = useRouter()
  const { passwordMinLength, loadPasswordMinLength, getPasswordMinLengthMessage } = useSystemParam()

  const loading = ref(false)

  const formRef = ref<FormInstance>()
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
    void loadPasswordMinLength().then(() => {
      if (form.value.password) {
        void formRef.value?.validateField('password')
      }
    })
  })

  /**
   * 验证密码
   * 当密码输入后，如果确认密码已填写，则触发确认密码的验证
   */
  const validatePassword = (_rule: any, value: string, callback: (error?: Error) => void) => {
    if (!value) {
      callback(new Error(t('register.placeholder.password')))
      return
    }

    if (form.value.confirmPassword) {
      formRef.value?.validateField('confirmPassword')
    }

    callback()
  }

  /**
   * 验证确认密码
   * 检查确认密码是否与密码一致
   */
  const validateConfirmPassword = (
    _rule: any,
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
      const { access_token: accessToken, refresh_token: refreshToken = '' } =
        parseSupabaseResetParams() as any
      if (!accessToken) {
        throw new Error('无效或已过期的重置链接')
      }
      const params: Api.Auth.ResetPwdParams = {
        password: form.value.password,
        accessToken,
        refreshToken
      }
      const { error } = await resetPassword(params)
      if (!error) {
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
  const parseSupabaseResetParams = () => {
    // 获取完整 hash，例如 "#/auth/reset-password#access_token=eyJhbGci..."
    const fullHash = window.location.hash

    console.log('完整 hash:', fullHash)

    // 查找最后一个 '#' 的位置
    const lastHashIndex = fullHash.lastIndexOf('#')

    if (lastHashIndex === -1 || lastHashIndex === fullHash.length - 1) {
      console.error('无效的重置链接格式')
      return null
    }

    // 提取真正的查询参数部分
    // 例如: "#access_token=eyJhbGci..." -> "access_token=eyJhbGci..."
    const paramsPart = fullHash.substring(lastHashIndex + 1)

    console.log('参数部分:', paramsPart)

    try {
      // 使用 URLSearchParams 解析
      const params = new URLSearchParams(paramsPart)

      // 提取关键参数
      const accessToken = params.get('access_token')
      const type = params.get('type')
      const expiresAt = params.get('expires_at')
      const refreshToken = params.get('refresh_token')

      console.log('解析结果:', {
        access_token: accessToken,
        type,
        expires_at: expiresAt,
        refresh_token: refreshToken
      })

      // 验证必要参数
      if (!accessToken || !type) {
        console.error('缺少必要的重置参数')
        return null
      }

      // 检查是否为重置密码类型
      if (type !== 'recovery') {
        console.error('不是重置密码链接，类型:', type)
        return null
      }

      // 检查过期时间
      if (expiresAt) {
        const expiresTimestamp = parseInt(expiresAt) * 1000 // 转换为毫秒
        if (Date.now() > expiresTimestamp) {
          console.error('重置链接已过期')
          return null
        }
      }

      return {
        access_token: accessToken,
        type,
        expires_at: expiresAt,
        refresh_token: refreshToken,
        allParams: Object.fromEntries(params.entries())
      }
    } catch (error) {
      console.error('解析参数失败:', error)
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
