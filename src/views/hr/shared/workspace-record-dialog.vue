<template>
  <ArtDialog ref="dialogRef">
    <div class="hr-record-dialog">
      <section class="hr-record-dialog__intro">
        <div class="hr-record-dialog__icon" aria-hidden="true">
          <ArtSvgIcon :icon="currentWorkspace?.icon ?? 'ri:file-edit-line'" />
        </div>
        <div class="hr-record-dialog__intro-copy">
          <span>{{ currentWorkspace?.eyebrow ?? 'HR WORKSPACE' }}</span>
          <strong>{{ currentWorkspace?.title ?? '人力资源工作台' }}</strong>
          <p>{{ currentWorkspace?.description ?? '维护业务资料并保留完整变更记录。' }}</p>
        </div>
        <div class="hr-record-dialog__badges">
          <ElTag type="primary" effect="plain" round>{{ currentTab?.label ?? '业务记录' }}</ElTag>
          <ElTag type="info" effect="light" round>{{ dialogModeLabel }}</ElTag>
        </div>
      </section>

      <section class="hr-record-dialog__form-panel">
        <header class="hr-record-dialog__form-heading">
          <div>
            <ArtSectionTitle :show-line="false">
              {{ currentTab?.label ?? '业务' }}信息
            </ArtSectionTitle>
            <p>带 <span>*</span> 的项目为必填项，请确认信息准确后提交。</p>
          </div>
          <span class="hr-record-dialog__field-count">
            <ArtSvgIcon icon="ri:list-check-3" />
            {{ currentTab?.fields.length ?? 0 }} 个字段
          </span>
        </header>

        <ArtForm
          ref="formRef"
          v-model="form.model"
          :items="form.items"
          :rules="form.rules"
          :show-reset="false"
          :show-submit="false"
          label-position="top"
          :span="12"
        />
      </section>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import { cloneDeep, compact, get } from 'lodash-es'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import TreeUtils from '@/utils/tree'
  import { useUserStore } from '@/store/modules/user'
  import {
    fetchEmployeeOrganizationTree,
    fetchEmployeeSelectorList,
    fetchHrWorkspaceRecords,
    fetchPositionOptions,
    saveHrWorkspaceRecord
  } from '@/api/hr'
  import type { HrWorkspaceDefinition, HrWorkspaceField, HrWorkspaceTab } from './workspace-config'

  interface DialogOpenData {
    workspace: HrWorkspaceDefinition
    tab: HrWorkspaceTab
    record?: Api.Hr.WorkspaceRecord
  }

  interface ArtFormExpose {
    validate: () => Promise<boolean | void>
    clearValidate: () => void
  }

  interface FormState {
    model: Api.Hr.WorkspaceRecord
    items: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<Api.Hr.WorkspaceRecord>>
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<DialogOpenData>>()
  const formRef = ref<ArtFormExpose>()
  const userStore = useUserStore()
  const { getDictMap, getUserInfo } = storeToRefs(userStore)
  const currentTab = shallowRef<HrWorkspaceTab>()
  const currentWorkspace = shallowRef<HrWorkspaceDefinition>()
  const isEditing = ref(false)
  const dialogModeLabel = computed(() => (isEditing.value ? '编辑记录' : '新增记录'))
  const organizationTreeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })

  const form = reactive<FormState>({
    model: {},
    items: computed(() => currentTab.value?.fields.map(createFormItem) ?? []),
    rules: computed(() => {
      const rules: FormRules<Api.Hr.WorkspaceRecord> = {}
      currentTab.value?.fields.forEach((field) => {
        if (field.required)
          rules[field.key] = [
            {
              required: true,
              message: `${field.label}不能为空`,
              trigger: field.type === 'input' ? 'blur' : 'change'
            }
          ]
      })
      return rules
    })
  })

  const getOptionLabel = (
    option: Record<string, unknown>,
    keys: Array<string | number | symbol>
  ): string =>
    compact(keys.map((key) => String(get(option, String(key)) ?? ''))).join(' · ') ||
    String(option.id ?? '未命名记录')

  const fetchFieldOptions = async (field: HrWorkspaceField): Promise<Record<string, unknown>[]> => {
    const key = String(field.key)
    if (key === 'employeeId') {
      const result = await fetchEmployeeSelectorList({
        tenantId: getUserInfo.value.tenantId,
        from: 0,
        to: 499
      })
      return result.data.map((item) => ({ ...item }))
    }
    if (key.toLowerCase().includes('positionid')) {
      const result = await fetchPositionOptions({ tenantId: getUserInfo.value.tenantId })
      return (result.data ?? []).map((item) => ({ ...item }))
    }
    if (key.toLowerCase().includes('organizationid')) {
      const result = await fetchEmployeeOrganizationTree({ tenantId: getUserInfo.value.tenantId })
      return organizationTreeUtils.treeToList(result.data ?? [])
    }
    if (!field.optionEntity) return []
    const result = await fetchHrWorkspaceRecords(field.optionEntity, { from: 0, to: 499 })
    return result.data.map((item) => ({ ...item }))
  }

  const createFormItem = (field: HrWorkspaceField): FormItem => {
    const base: FormItem = {
      key: String(field.key),
      label: field.label,
      type: field.type,
      span: field.span ?? 12,
      props: { style: { width: '100%' }, clearable: true, ...field.props }
    }
    if (field.dictCode) {
      base.props = { ...base.props, options: getDictMap.value[field.dictCode] ?? [] }
    } else if (field.type === 'select') {
      base.api = () => fetchFieldOptions(field)
      base.valueField = 'id'
      base.labelFn = (option) => getOptionLabel(option, field.optionLabelKeys ?? ['id'])
      base.props = { ...base.props, filterable: true }
    }
    if (field.type === 'date') {
      const isDateTime = ['clockInAt', 'clockOutAt', 'startAt', 'endAt'].includes(String(field.key))
      base.props = {
        ...base.props,
        type: isDateTime ? 'datetime' : 'date',
        valueFormat: isDateTime ? 'YYYY-MM-DDTHH:mm:ssZ' : 'YYYY-MM-DD'
      }
    }
    if (field.type === 'number') base.props = { ...base.props, controlsPosition: 'right' }
    if (field.type === 'timeSelect')
      base.props = { ...base.props, start: '00:00', step: '00:15', end: '23:45' }
    return base
  }

  const buildWriteRecord = (): Api.Hr.WorkspaceRecord => {
    const tab = currentTab.value
    if (!tab) return {}
    const payload: Record<string, unknown> = { id: form.model.id }
    tab.fields.forEach((field) => {
      const value = form.model[field.key]
      payload[field.key] = value === '' ? null : value
    })
    return payload as Api.Hr.WorkspaceRecord
  }

  const handleSubmit = async (): Promise<boolean> => {
    const tab = currentTab.value
    if (!tab) return false
    try {
      await formRef.value?.validate()
      await saveHrWorkspaceRecord(tab.entity, buildWriteRecord())
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (data: DialogOpenData): Promise<void> => {
    Object.keys(form.model).forEach((key) => delete form.model[key as keyof Api.Hr.WorkspaceRecord])
    currentWorkspace.value = data.workspace
    currentTab.value = data.tab
    isEditing.value = Boolean(data.record?.id)
    Object.assign(form.model, cloneDeep({ ...data.tab.defaults, ...data.record }))
    await dialogRef.value?.handleOpen(data, {
      title: `${data.record?.id ? '编辑' : '新增'}${data.tab.label}`,
      subtitle: `在${data.workspace.title}中维护${data.tab.label}，提交后将按权限和业务状态处理。`,
      size: 'lg',
      contentMaxHeight: '72vh',
      confirmText: data.record?.id ? '保存更改' : '创建记录',
      onConfirm: handleSubmit,
      onReset: () => {
        Object.keys(form.model).forEach(
          (key) => delete form.model[key as keyof Api.Hr.WorkspaceRecord]
        )
        currentTab.value = undefined
        currentWorkspace.value = undefined
        isEditing.value = false
      }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .hr-record-dialog {
    display: grid;
    gap: 16px;
    min-width: 0;

    &__intro {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) auto;
      gap: 14px;
      align-items: center;
      padding: 16px 18px;
      overflow: hidden;
      background: linear-gradient(
        135deg,
        color-mix(in srgb, var(--el-color-primary) 10%, var(--el-bg-color)) 0%,
        color-mix(in srgb, var(--el-color-primary) 3%, var(--el-bg-color)) 100%
      );
      border: 1px solid color-mix(in srgb, var(--el-color-primary) 18%, var(--el-border-color));
      border-radius: 12px;
    }

    &__icon {
      display: grid;
      place-items: center;
      width: 46px;
      height: 46px;
      font-size: 23px;
      color: var(--el-color-white);
      background: linear-gradient(145deg, var(--el-color-primary-light-3), var(--el-color-primary));
      border-radius: 12px;
      box-shadow: 0 8px 20px color-mix(in srgb, var(--el-color-primary) 24%, transparent);
    }

    &__intro-copy {
      min-width: 0;

      > span {
        display: block;
        margin-bottom: 2px;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 10px;
        font-weight: 700;
        line-height: 16px;
        color: var(--el-color-primary);
        letter-spacing: 1.2px;
        white-space: nowrap;
      }

      strong {
        display: block;
        font-size: 16px;
        line-height: 24px;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 3px 0 0;
        font-size: 12px;
        line-height: 20px;
        color: var(--el-text-color-secondary);
      }
    }

    &__badges {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      justify-content: flex-end;
    }

    &__form-panel {
      padding: 18px 18px 4px;
      background: var(--el-fill-color-blank);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: 12px;
    }

    &__form-heading {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      padding-bottom: 14px;
      margin-bottom: 16px;
      border-bottom: 1px solid var(--el-border-color-extra-light);

      :deep(.art-section-title) {
        margin: 0 0 2px;
      }

      p {
        margin: 0;
        font-size: 12px;
        line-height: 20px;
        color: var(--el-text-color-secondary);

        span {
          color: var(--el-color-danger);
        }
      }
    }

    &__field-count {
      display: inline-flex;
      flex: 0 0 auto;
      gap: 6px;
      align-items: center;
      padding: 5px 9px;
      font-size: 12px;
      line-height: 18px;
      color: var(--el-text-color-secondary);
      background: var(--el-fill-color-light);
      border-radius: 8px;
    }

    :deep(.el-form-item) {
      margin-bottom: 20px;
    }

    :deep(.el-form-item__label) {
      height: auto;
      padding-bottom: 7px;
      font-weight: 500;
      line-height: 20px;
      color: var(--el-text-color-regular);
    }
  }

  @media (width <= 720px) {
    .hr-record-dialog {
      &__intro {
        grid-template-columns: auto minmax(0, 1fr);
        padding: 14px;
      }

      &__badges {
        grid-column: 1 / -1;
        justify-content: flex-start;
      }

      &__form-panel {
        padding: 16px 14px 2px;
      }

      &__form-heading {
        display: block;
      }

      &__field-count {
        margin-top: 10px;
      }

      :deep(.el-col-xs-12) {
        flex: 0 0 100%;
        max-width: 100%;
      }
    }
  }
</style>
