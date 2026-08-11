<template>
  <div class="flex w-full h-screen">
    <LoginLeftView />

    <div class="relative flex-1">
      <AuthTopBar />

      <div class="auth-right-wrap">
        <div class="form">
          <h3 class="title">{{ $t('forgetPassword.title') }}</h3>
          <p class="sub-title">{{ $t('forgetPassword.subTitle') }}</p>
          <div class="mt-5">
            <ElForm ref="formRef" :model="form" :rules="rules">
              <ElFormItem prop="email">
                <ElInput
                  class="custom-height"
                  :placeholder="$t('forgetPassword.placeholder')"
                  v-model.trim="form.email"
                  name="email"
                  type="email"
                  inputmode="email"
                  autocomplete="email"
                  :aria-label="$t('forgetPassword.placeholder')"
                  :spellcheck="false"
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
  import type { FormRules } from 'element-plus'
  import { useI18n } from 'vue-i18n'
  import { forgetPassword } from '@/api/auth'

  defineOptions({ name: 'ForgetPassword' })

  const { t } = useI18n()
  const router = useRouter()

  const formRef = ref<HTMLFormElement | null>(null)
  const form = ref({
    email: ''
  })

  const rules = computed<FormRules<{ email: string }>>(() => ({
    email: [
      { required: true, message: t('register.placeholder.email'), trigger: 'change' },
      {
        type: 'email',
        message: t('register.rule.emailIncorrect'),
        trigger: 'change'
      }
    ]
  }))
  const loading = ref(false)

  const handleSubmit = async () => {
    await formRef.value?.validate()
    try {
      loading.value = true
      const params: Api.Auth.ForgetPwdParams = {
        email: form.value.email,
        redirectTo: location.origin + location.pathname + '#/auth/reset-password'
      }
      const { error } = await forgetPassword(params)
      if (!error) {
        ElMessage.success('邮件已经下发到您的邮箱,请前往重置密码')
      }
    } finally {
      loading.value = false
    }
  }

  const toLogin = () => {
    router.push({ name: 'Login' })
  }
</script>

<style scoped>
  @import '../login/style.css';
</style>
