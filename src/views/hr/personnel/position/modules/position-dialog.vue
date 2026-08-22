<template>
  <ArtDialog ref="dialogRef" size="md">
    <ArtForm
      ref="formRef"
      class="position-dialog__form"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="12"
      :gutter="24"
      label-position="top"
      :show-reset="false"
      :show-submit="false"
    >
      <template #positionKind>
        <div
          class="position-dialog__kind-summary"
          :class="{ 'is-driver': positionKindMeta.kind === 'driver' }"
        >
          <span class="position-dialog__kind-icon" aria-hidden="true">
            <ArtSvgIcon :icon="positionKindMeta.icon" />
          </span>
          <div class="position-dialog__kind-copy">
            <strong>{{ positionKindMeta.label }}</strong>
            <span>{{ positionKindMeta.description }}</span>
          </div>
          <ElTag :type="positionKindMeta.tagType" effect="plain" round>
            {{ positionKindMeta.badge }}
          </ElTag>
        </div>
      </template>
    </ArtForm>
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
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { addPosition, editPosition } from '@/api/hr'
  import { fetchGetEnableTenantList } from '@/api/system-manage'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'HrPositionDialog' })

  type Position = Api.Hr.Position

  interface DialogExposeForm {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ (event: 'success', type: 'add' | 'edit'): void }>()
  const { getUserInfo, isPlatformSuper } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Position | undefined>>()
  const formRef = ref<DialogExposeForm>()
  const tenantOptions = ref<FormItemOption[]>([])

  const createInitialForm = (): Position => ({
    tenantId: isPlatformSuper.value ? undefined : getUserInfo.value.tenantId,
    positionCode: '',
    positionName: '',
    positionKind: 'standard',
    systemCode: null,
    enabled: true,
    sort: 0,
    description: ''
  })
  const form = reactive<Position>(createInitialForm())
  const isSystemPosition = computed(() => Boolean(form.systemCode))
  const positionKindMeta = computed(() => {
    const isDriver = form.positionKind === 'driver'
    return {
      kind: isDriver ? ('driver' as const) : ('standard' as const),
      label: isDriver ? '司机岗位' : '普通岗位',
      description: isDriver
        ? '系统唯一司机岗位；员工选择后会同步创建司机运营档案。'
        : '用于员工任职和花名册管理，不触发司机档案联动。',
      icon: isDriver ? 'ri:steering-2-line' : 'ri:briefcase-4-line',
      tagType: isDriver ? ('success' as const) : ('info' as const),
      badge: isSystemPosition.value ? '系统预置' : form.id ? '创建后固定' : '系统默认'
    }
  })

  const formRules: FormRules<Position> = {
    tenantId: isPlatformSuper.value
      ? [{ required: true, message: '请选择所属租户', trigger: 'change' }]
      : [],
    positionCode: [
      { required: true, message: '请输入岗位编码', trigger: 'blur' },
      {
        pattern: /^[A-Za-z][A-Za-z0-9_-]{1,31}$/,
        message: '请输入 2-32 位字母开头的编码',
        trigger: 'blur'
      }
    ],
    positionName: [
      { required: true, message: '请输入岗位名称', trigger: 'blur' },
      { min: 2, max: 50, message: '岗位名称应为 2-50 个字符', trigger: 'blur' }
    ],
    sort: [{ required: true, message: '请输入排序值', trigger: 'change' }],
    description: [{ max: 300, message: '岗位说明不能超过 300 个字符', trigger: 'blur' }]
  }

  const formItems = computed<FormItem[]>(() => [
    { label: '岗位信息', key: 'baseSection', type: 'divider', span: 24 },
    {
      label: '所属租户',
      key: 'tenantId',
      type: 'select',
      span: 24,
      hidden: !isPlatformSuper.value,
      options: tenantOptions.value,
      props: { filterable: true, disabled: Boolean(form.id), placeholder: '请选择所属租户' }
    },
    {
      label: '岗位编码',
      key: 'positionCode',
      type: 'input',
      props: { maxlength: 32, disabled: isSystemPosition.value, placeholder: '如 DRIVER' }
    },
    {
      label: '岗位名称',
      key: 'positionName',
      type: 'input',
      props: { maxlength: 50, placeholder: '请输入岗位名称' }
    },
    {
      label: '业务属性',
      key: 'positionKind',
      type: 'text',
      span: 24,
      help: '业务属性由岗位创建来源确定。司机岗位由系统为每个租户预置，不能手工新增或转换。'
    },
    {
      label: '排序',
      key: 'sort',
      type: 'number',
      props: { min: 0, max: 9999, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '状态',
      key: 'enabled',
      type: 'switch',
      props: {
        disabled: form.systemCode === 'driver',
        activeText: '启用',
        inactiveText: '停用',
        inlinePrompt: true
      }
    },
    {
      label: '岗位说明',
      key: 'description',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 4, maxlength: 300, showWordLimit: true }
    }
  ])

  const replaceForm = (next: Position): void => {
    Object.keys(form).forEach((key) => delete form[key as keyof Position])
    Object.assign(form, next)
  }
  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      const type = form.id ? 'edit' : 'add'
      if (type === 'edit') await editPosition(structuredClone(toRaw(form)))
      else await addPosition(structuredClone(toRaw(form)))
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: Position): Promise<void> => {
    await resetForm()
    if (row) replaceForm({ ...createInitialForm(), ...structuredClone(toRaw(row)) })
    await dialogRef.value?.handleOpen(row, {
      title: row ? '编辑岗位' : '新增岗位',
      subtitle: row
        ? '维护岗位名称、排序与启用状态；业务属性保持不变'
        : '创建普通任职岗位；司机岗位由系统自动预置',
      confirmText: row ? '保存更改' : '创建岗位',
      contentMaxHeight: 'calc(100vh - 184px)',
      loading: isPlatformSuper.value && !tenantOptions.value.length,
      loadingText: '正在加载租户选项…',
      onOpen: async (_openRow, api) => {
        if (!isPlatformSuper.value || tenantOptions.value.length) return
        api.setLoading(true)
        try {
          const response = await fetchGetEnableTenantList()
          tenantOptions.value = (response.data ?? []).map((tenant) => ({
            label: `${tenant.tenantName}（${tenant.tenantCode}）`,
            value: tenant.id!
          }))
        } finally {
          api.setLoading(false)
        }
      },
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({ handleOpen, handleClose: () => dialogRef.value?.handleClose() })
</script>

<style scoped lang="scss">
  .position-dialog {
    &__kind-summary {
      display: flex;
      gap: 12px;
      align-items: center;
      width: 100%;
      min-width: 0;
      padding: 12px 14px;
      background: var(--art-gray-100);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      &.is-driver {
        background: color-mix(in srgb, var(--el-color-success) 8%, var(--default-box-color));

        .position-dialog__kind-icon {
          color: var(--el-color-success);
          background: var(--el-color-success-light-9);
        }
      }

      > .el-tag {
        flex: none;
        margin-left: auto;
      }
    }

    &__kind-icon {
      display: inline-flex;
      flex: 0 0 38px;
      align-items: center;
      justify-content: center;
      width: 38px;
      height: 38px;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 10%, var(--default-box-color));
      border-radius: var(--el-border-radius-base);

      :deep(svg) {
        width: 18px;
        height: 18px;
      }
    }

    &__kind-copy {
      display: grid;
      flex: 1;
      min-width: 0;

      strong {
        line-height: 1.5;
        color: var(--el-text-color-primary);
      }

      span {
        margin-top: 2px;
        font-size: 12px;
        line-height: 1.5;
        color: var(--el-text-color-secondary);
      }
    }

    @media (width <= 600px) {
      &__kind-summary {
        flex-wrap: wrap;

        > .el-tag {
          margin-left: 50px;
        }
      }
    }
  }
</style>
