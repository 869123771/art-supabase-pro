<template>
  <ArtException
    :secondary-btn-events="reloadPage"
    :data="{
      title: '500',
      heading: $t('exceptionPage.500Title'),
      statusLabel: $t('exceptionPage.serviceUnavailable'),
      desc: $t('exceptionPage.500'),
      hint: $t('exceptionPage.500Hint'),
      btnText: $t('exceptionPage.gohome'),
      secondaryBtnText: $t('exceptionPage.reload'),
      supportText: $t('exceptionPage.support'),
      visualLabel: $t('exceptionPage.systemStatus'),
      icon: 'ri:server-line',
      primaryIcon: 'ri:home-5-line',
      secondaryIcon: 'ri:refresh-line',
      tone: 'danger',
      imgUrl
    }"
  />
</template>

<script setup lang="ts">
  import imgUrl from '@imgs/svg/500.svg'

  defineOptions({ name: 'Exception500' })

  const reloadPage = (): void => {
    window.location.reload()
  }
</script>
