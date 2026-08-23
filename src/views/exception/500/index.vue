<template>
  <ArtException
    :btn-events="retryInitialization"
    :secondary-btn-events="reloadPage"
    :data="{
      title: '500',
      heading: $t('exceptionPage.500Title'),
      statusLabel: $t('exceptionPage.serviceUnavailable'),
      desc: $t('exceptionPage.500'),
      hint: $t('exceptionPage.500Hint'),
      btnText: $t('exceptionPage.retryInitialization'),
      secondaryBtnText: $t('exceptionPage.reload'),
      supportText: $t('exceptionPage.support'),
      visualLabel: $t('exceptionPage.systemStatus'),
      icon: 'ri:server-line',
      primaryIcon: 'ri:restart-line',
      secondaryIcon: 'ri:refresh-line',
      tone: 'danger',
      imgUrl
    }"
  />
</template>

<script setup lang="ts">
  import imgUrl from '@imgs/svg/500.svg'
  import { recoverCurrentAuthSession } from '@/api/auth'
  import { resetRouteInitializationForRetry } from '@/router/guards/beforeEach'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'Exception500' })

  const router = useRouter()
  const userStore = useUserStore()

  const recoverSystem = async (hardReload: boolean): Promise<void> => {
    try {
      const session = await recoverCurrentAuthSession()
      if (session.status === 'expired') {
        await userStore.logOut('/')
        return
      }

      userStore.setToken(session.accessToken, session.refreshToken)
      userStore.setLoginStatus(true)
      resetRouteInitializationForRetry()

      if (!hardReload) {
        await router.replace('/')
        return
      }

      const reloadUrl = new URL(router.resolve('/').href, window.location.href)
      window.history.replaceState(window.history.state, '', reloadUrl)
      window.location.reload()
    } catch (error) {
      console.error('[Exception500] 系统恢复失败:', error)
      ElMessage.error('登录状态检查失败，请稍后重试')
    }
  }

  const retryInitialization = (): Promise<void> => recoverSystem(false)

  const reloadPage = (): Promise<void> => recoverSystem(true)
</script>
