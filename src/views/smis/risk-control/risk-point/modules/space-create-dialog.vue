<template>
  <ArtDialog ref="dialogRef" size="md">
    <template #subtitle>
      {{
        mode === 'site'
          ? '建立生产经营场所，供区域与风险点统一引用。'
          : '区域必须归属一个场所，可继续维护平面图坐标。'
      }}
    </template>
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="12"
      :gutter="20"
      label-width="100px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, {
    type FormItem,
    type FormItemOption
  } from '@/components/core/forms/art-form/index.vue'
  import { addArea, addSite, fetchSiteOptions } from '@/api/smis'

  defineOptions({ name: 'SmisSpaceCreateDialog' })

  type SpaceMode = 'site' | 'area'
  interface SpaceForm {
    siteId: string
    code: string
    name: string
    address: string
    sort: number
    remark: string
  }

  const emit = defineEmits<{ (event: 'success', mode: SpaceMode): void }>()
  const dialogRef = ref<ArtDialogExpose<SpaceMode>>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const mode = ref<SpaceMode>('site')
  const siteOptions = ref<FormItemOption[]>([])
  const form = reactive<SpaceForm>({
    siteId: '',
    code: '',
    name: '',
    address: '',
    sort: 0,
    remark: ''
  })

  const formRules = computed<FormRules<SpaceForm>>(() => ({
    siteId:
      mode.value === 'area'
        ? [{ required: true, message: '请选择所属场所', trigger: 'change' }]
        : [],
    code: [
      {
        required: true,
        message: `请输入${mode.value === 'site' ? '场所' : '区域'}编码`,
        trigger: 'blur'
      },
      {
        pattern: /^[A-Za-z0-9][A-Za-z0-9_-]{1,31}$/,
        message: '请输入 2-32 位规范编码',
        trigger: 'blur'
      }
    ],
    name: [
      {
        required: true,
        message: `请输入${mode.value === 'site' ? '场所' : '区域'}名称`,
        trigger: 'blur'
      },
      { min: 2, max: 100, message: '名称应为 2-100 个字符', trigger: 'blur' }
    ],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }))

  const formItems = computed<FormItem[]>(() => [
    {
      label: '所属场所',
      key: 'siteId',
      type: 'select',
      span: 24,
      hidden: mode.value !== 'area',
      options: siteOptions.value,
      props: { filterable: true, placeholder: '请选择所属场所' }
    },
    {
      label: `${mode.value === 'site' ? '场所' : '区域'}编码`,
      key: 'code',
      type: 'input',
      props: {
        maxlength: 32,
        placeholder: mode.value === 'site' ? '如 SITE-SH-01' : '如 AREA-WH-01'
      }
    },
    {
      label: `${mode.value === 'site' ? '场所' : '区域'}名称`,
      key: 'name',
      type: 'input',
      props: { maxlength: 100 }
    },
    {
      label: '详细地址',
      key: 'address',
      type: 'input',
      span: 24,
      hidden: mode.value !== 'site',
      props: { maxlength: 200 }
    },
    {
      label: '排序',
      key: 'sort',
      type: 'number',
      props: { min: 0, max: 9999, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
    }
  ])

  const resetForm = async (): Promise<void> => {
    Object.assign(form, { siteId: '', code: '', name: '', address: '', sort: 0, remark: '' })
    await nextTick()
    formRef.value?.clearValidate()
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      if (mode.value === 'site') {
        await addSite({
          siteCode: form.code,
          siteName: form.name,
          address: form.address || null,
          enabled: true,
          sort: form.sort,
          remark: form.remark || null
        })
      } else {
        await addArea({
          siteId: form.siteId,
          areaCode: form.code,
          areaName: form.name,
          enabled: true,
          sort: form.sort,
          remark: form.remark || null
        })
      }
      emit('success', mode.value)
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (nextMode: SpaceMode): Promise<void> => {
    mode.value = nextMode
    await resetForm()
    if (nextMode === 'area') {
      const response = await fetchSiteOptions()
      siteOptions.value = (response.data ?? []).map((site) => ({
        label: `${site.siteName}（${site.siteCode}）`,
        value: site.id!
      }))
    }
    await dialogRef.value?.handleOpen(nextMode, {
      title: nextMode === 'site' ? '新增场所' : '新增区域',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({ handleOpen, handleClose: () => dialogRef.value?.handleClose() })
</script>
