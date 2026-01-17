<template>
  <ArtSearchBar
    ref="searchBarRef"
    :span="8"
    :label-width="100"
    v-model="formData"
    :items="formItems"
    :rules="rules"
    @reset="handleReset"
    @search="handleSearch"
  >
  </ArtSearchBar>
</template>

<script setup lang="ts">
  import { useUserStore } from '@/store/modules/user'

  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore) as Record<string, any>

  interface Props {
    modelValue: Record<string, any>
  }
  interface Emits {
    (e: 'update:modelValue', value: Record<string, any>): void
    (e: 'search', params: Record<string, any>): void
    (e: 'reset'): void
  }
  const props = defineProps<Props>()
  const emit = defineEmits<Emits>()

  // 表单数据双向绑定
  const searchBarRef = ref()
  const formData = computed({
    get: () => props.modelValue,
    set: (val) => emit('update:modelValue', val)
  })

  // 校验规则
  const rules = {
    // userName: [{ required: true, message: '请输入用户名', trigger: 'blur' }]
  }

  // 表单配置
  const formItems = computed(() => [
    {
      label: '字典标签',
      key: 'label',
      type: 'input',
      placeholder: '请输入字典标签',
      clearable: true
    },
    {
      label: '字典编码',
      key: 'code',
      type: 'input',
      props: { placeholder: '请输入字典编码', clearable: true }
    },
    {
      label: '国际化范围',
      key: 'i18nScope',
      type: 'select',
      props: {
        placeholder: '请选择国际化范围',
        clearable: true,
        options: getDictMap.value?.i18nScope
      }
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: { placeholder: '请选择状态', clearable: true, options: getDictMap.value?.status }
    }
  ])

  // 事件
  function handleReset() {
    emit('reset')
  }

  function handleSearch() {
    emit('search', formData.value)
  }
</script>
