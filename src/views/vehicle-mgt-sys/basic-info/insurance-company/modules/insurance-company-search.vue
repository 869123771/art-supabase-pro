<template>
  <ArtSearchBar
    v-model="form"
    :items="items"
    :show-expand="false"
    label-width="96px"
    @search="emit('search', form)"
    @reset="emit('reset')"
  />
</template>

<script setup lang="ts">
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'

  type SearchParams = Api.VehicleMgtSys.BasicInfo.InsuranceCompanySearchParams

  interface Props {
    modelValue: SearchParams
  }

  interface Emits {
    (e: 'update:modelValue', value: SearchParams): void
    (e: 'search', value: SearchParams): void
    (e: 'reset'): void
  }

  const props = defineProps<Props>()
  const emit = defineEmits<Emits>()

  const form = computed({
    get: () => props.modelValue,
    set: (value) => emit('update:modelValue', value)
  })

  const items: SearchFormItem[] = [
    {
      label: '保险公司名称',
      key: 'companyName',
      type: 'input',
      props: {
        clearable: true,
        placeholder: '请输入保险公司名称'
      }
    },
    {
      label: '联系人',
      key: 'contactPerson',
      type: 'input',
      props: {
        clearable: true,
        placeholder: '请输入联系人'
      }
    },
    {
      label: '联系电话',
      key: 'contactPhone',
      type: 'input',
      props: {
        clearable: true,
        placeholder: '请输入联系电话'
      }
    }
  ]
</script>
