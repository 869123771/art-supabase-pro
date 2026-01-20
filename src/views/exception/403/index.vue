<!-- 403页面 -->
<template>
  <ArtException
    :btn-events="userStore.logOut"
    :data="{
      title: '403',
      desc: $t('exceptionPage.403'),
      btnText: $t('exceptionPage.goLogin'),
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
