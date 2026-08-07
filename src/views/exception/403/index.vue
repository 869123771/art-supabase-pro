<template>
  <ArtException
    :btn-events="userStore.logOut"
    :data="{
      title: '403',
      heading: $t('exceptionPage.403Title'),
      statusLabel: $t('exceptionPage.accessRestricted'),
      desc: $t('exceptionPage.403'),
      hint: $t('exceptionPage.403Hint'),
      btnText: $t('exceptionPage.goLogin'),
      secondaryBtnText: $t('exceptionPage.goBack'),
      supportText: $t('exceptionPage.support'),
      visualLabel: $t('exceptionPage.systemStatus'),
      icon: 'ri:shield-keyhole-line',
      primaryIcon: 'ri:login-box-line',
      secondaryIcon: 'ri:arrow-left-line',
      tone: 'warning',
      imgUrl
    }"
  />
</template>

<script setup lang="ts">
  import imgUrl from '@imgs/svg/403.svg'
  import { useUserStore } from '@/store/modules/user'

  const userStore = useUserStore()

  defineOptions({ name: 'Exception403' })
</script>
