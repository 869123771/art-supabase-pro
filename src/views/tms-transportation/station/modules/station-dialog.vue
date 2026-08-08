<template>
  <ArtDialog ref="dialogRef" size="lg">
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="8"
      :gutter="20"
      label-width="100px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { FormRules } from 'element-plus'
  import { omit, toNumber, trim, uniq } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { addStation, editStation } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'TmsStationDialog' })

  type Station = Api.Tms.Station.StationRecord
  type StationForm = Api.Tms.Station.StationSavePayload

  interface DialogExposeForm {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: StationForm
    stationTypeOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    items: ComputedRef<FormItem[]>
    rules: FormRules<StationForm>
  }

  const emit = defineEmits<{
    (event: 'success', type: 'add' | 'edit'): void
  }>()

  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Station | undefined>>()
  const formRef = ref<DialogExposeForm>()

  const createInitialForm = (): StationForm => ({
    id: undefined,
    stationCode: '',
    stationName: '',
    stationTypes: ['shipping'],
    regionCode: '',
    managerName: '',
    contactPhone: '',
    enabled: true,
    sort: 0,
    remark: ''
  })

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    stationTypeOptions: computed(() => getDictMap.value.tmsStationType ?? []),
    rules: {
      stationTypes: [{ required: true, message: '请至少选择一个站点类型', trigger: 'change' }],
      stationName: [
        { required: true, message: '请输入站点名称', trigger: 'blur' },
        { min: 2, max: 80, message: '长度应为 2 到 80 个字符', trigger: 'blur' }
      ],
      stationCode: [{ max: 30, message: '站点编码不能超过 30 个字符', trigger: 'blur' }],
      regionCode: [{ max: 30, message: '地区编码不能超过 30 个字符', trigger: 'blur' }],
      managerName: [{ max: 50, message: '负责人不能超过 50 个字符', trigger: 'blur' }],
      contactPhone: [{ max: 20, message: '联系电话不能超过 20 个字符', trigger: 'blur' }],
      remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
    },
    items: computed<FormItem[]>(() => [
      { label: '基础信息', key: 'baseSection', type: 'divider', span: 24 },
      {
        label: '站点编码',
        key: 'stationCode',
        type: 'input',
        props: {
          maxlength: 30,
          placeholder: '不填则自动生成'
        }
      },
      {
        label: '站点名称',
        key: 'stationName',
        type: 'input',
        props: {
          maxlength: 80,
          placeholder: '请输入站点名称'
        }
      },
      {
        label: '站点类型',
        key: 'stationTypes',
        type: 'select',
        props: {
          options: form.stationTypeOptions,
          multiple: true,
          collapseTags: true,
          collapseTagsTooltip: true,
          placeholder: '可选择多个站点类型'
        }
      },
      {
        label: '地区编码',
        key: 'regionCode',
        type: 'input',
        props: {
          maxlength: 30,
          placeholder: '设置地区编码，用于生成货号'
        }
      },
      {
        label: '排序',
        key: 'sort',
        type: 'number',
        props: {
          min: 0,
          precision: 0,
          controlsPosition: 'right',
          class: '!w-full'
        }
      },
      {
        label: '状态',
        key: 'enabled',
        type: 'switch',
        props: {
          activeText: '启用',
          inactiveText: '停用',
          inlinePrompt: true
        }
      },
      { label: '联系信息', key: 'contactSection', type: 'divider', span: 24 },
      {
        label: '负责人',
        key: 'managerName',
        type: 'input',
        props: {
          maxlength: 50,
          placeholder: '请输入负责人姓名'
        }
      },
      {
        label: '联系电话',
        key: 'contactPhone',
        type: 'input',
        props: {
          maxlength: 20,
          placeholder: '请输入站点联系电话'
        }
      },
      { label: '备注信息', key: 'remarkSection', type: 'divider', span: 24 },
      {
        label: '备注',
        key: 'remark',
        type: 'input',
        span: 24,
        props: {
          type: 'textarea',
          rows: 3,
          maxlength: 500,
          showWordLimit: true,
          placeholder: '请输入备注'
        }
      }
    ])
  })

  const replaceForm = (nextForm: StationForm): void => {
    Object.assign(form.data, createInitialForm(), nextForm)
  }

  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const createStationCode = (): string => `ST${Date.now().toString().slice(-8)}`

  const nullableText = (value?: string | null): string | null => trim(String(value ?? '')) || null

  const normalizePayload = (): StationForm => {
    const payload = omit(structuredClone(toRaw(form.data)), [
      'tenantId',
      'stationType',
      'stationRoles',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime'
    ]) as StationForm

    return {
      ...payload,
      stationCode: trim(String(payload.stationCode || '')) || createStationCode(),
      stationName: trim(String(payload.stationName || '')),
      stationTypes: uniq(payload.stationTypes.map((item) => trim(String(item))).filter(Boolean)),
      regionCode: nullableText(payload.regionCode),
      managerName: nullableText(payload.managerName),
      contactPhone: nullableText(payload.contactPhone),
      sort: toNumber(payload.sort ?? 0),
      remark: nullableText(payload.remark)
    }
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const payload = normalizePayload()
      const type = form.data.id ? 'edit' : 'add'
      if (type === 'edit') await editStation(payload)
      else await addStation(payload)
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: Station): Promise<void> => {
    await resetForm()
    const isEdit = Boolean(row?.id)
    if (row) {
      const stationTypes = row.stationRoles?.length
        ? row.stationRoles.map((item) => item.roleType)
        : [row.stationType]
      replaceForm({
        ...createInitialForm(),
        ...omit(structuredClone(toRaw(row)), ['stationType', 'stationRoles']),
        stationTypes
      })
    }

    await dialogRef.value?.handleOpen(row, {
      title: isEdit ? '编辑站点' : '新增站点',
      subtitle: '维护站点类型、区域位置、联系人和运输网络可用状态',
      contentMaxHeight: '70vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
