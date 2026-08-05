<template>
  <ArtDialog ref="dialogRef" size="lg">
    <div class="system-param-dialog">
      <section class="system-param-dialog__form">
        <div class="system-param-dialog__section-head">
          <div>
            <h3>参数信息</h3>
            <p>配置键名、分组和值内容，保存后可刷新缓存使新值生效。</p>
          </div>
          <ElTag round :type="formState.model.builtin ? 'warning' : 'info'" effect="light">
            {{ formState.model.builtin ? '内置参数' : '自定义参数' }}
          </ElTag>
        </div>

        <ElScrollbar class="system-param-dialog__form-body">
          <ArtForm
            ref="formRef"
            v-model="formState.model"
            :items="formState.items.value"
            :rules="formState.rules.value"
            :span="12"
            :gutter="20"
            label-position="top"
            label-width="auto"
            :show-reset="false"
            :show-submit="false"
            :validate-on-rule-change="false"
          >
            <template #basicInfoTitle>
              <div class="system-param-dialog__divider">
                <span>基础信息</span>
              </div>
            </template>

            <template #statusContentTitle>
              <div class="system-param-dialog__divider">
                <span>状态与内容</span>
              </div>
            </template>

            <template #paramValue>
              <ElInput
                v-if="formState.model.paramType === 'single_text'"
                v-model="formState.model.paramValue"
                maxlength="500"
                show-word-limit
                placeholder="请输入参数值"
              />
              <ElInput
                v-else-if="formState.model.paramType === 'multi_text'"
                v-model="formState.model.paramValue"
                type="textarea"
                :rows="5"
                maxlength="5000"
                show-word-limit
                placeholder="请输入多行文本内容"
              />
              <ElInputNumber
                v-else-if="formState.model.paramType === 'number'"
                v-model="numberParamValue"
                placeholder="请输入数字"
                class="!w-full"
              />
              <ElSelect
                v-else-if="formState.model.paramType === 'boolean'"
                v-model="formState.model.paramValue"
                placeholder="请选择布尔值"
                class="system-param-dialog__full-control"
              >
                <ElOption label="true / 开启" value="true" />
                <ElOption label="false / 关闭" value="false" />
              </ElSelect>
              <ElInput
                v-else
                v-model="formState.model.paramValue"
                type="textarea"
                :rows="5"
                maxlength="5000"
                show-word-limit
                placeholder='请输入合法 JSON，例如：{"enabled": true}'
              />
            </template>
          </ArtForm>
        </ElScrollbar>
      </section>

      <ElScrollbar class="system-param-dialog__side">
        <section class="system-param-dialog__preview">
          <h3>配置预览</h3>
          <dl>
            <div>
              <dt>键名</dt>
              <dd>{{ formState.model.paramKey || '-' }}</dd>
            </div>
            <div>
              <dt>分组</dt>
              <dd>{{ formState.model.groupName || '-' }}</dd>
            </div>
            <div class="system-param-dialog__preview-grid">
              <div>
                <dt>类型</dt>
                <dd>{{ typeLabel || '-' }}</dd>
              </div>
              <div>
                <dt>状态</dt>
                <dd>{{ formState.model.enabled ? '启用' : '停用' }}</dd>
              </div>
            </div>
            <div>
              <dt>值预览</dt>
              <dd class="system-param-dialog__value-preview">{{ previewValue }}</dd>
            </div>
          </dl>
        </section>

        <section class="system-param-dialog__tips">
          <h3>维护建议</h3>
          <ul>
            <li>键名建议采用“业务域.模块.字段”的层级命名。</li>
            <li>内置参数用于平台底层策略，建议限制删除和变更范围。</li>
            <li>JSON 类型可承载复杂配置，但需要保持结构稳定。</li>
            <li>修改完成后建议执行一次缓存刷新，确保新值及时生效。</li>
          </ul>
        </section>
      </ElScrollbar>
    </div>
  </ArtDialog>
</template>
<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import type { ComputedRef } from 'vue'
  import { cloneDeep, omit } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { addSystemParam, editSystemParam } from '@/api/system-manage'
  import { useUserStore } from '@/store/modules/user'
  import { uniqueValidator } from '@/utils/form/validator'

  type SystemParam = Api.SystemManage.SystemParamItem
  type SystemParamType = Api.SystemManage.SystemParamType

  interface SystemParamForm extends Omit<SystemParam, 'extendConfig'> {
    extendConfigText: string
  }

  interface ArtFormExpose {
    validate: () => Promise<boolean | void>
    clearValidate: () => void
  }

  interface SystemParamFormState {
    model: SystemParamForm
    items: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<SystemParamForm>>
  }

  const emit = defineEmits<{
    success: [type: 'add' | 'edit']
  }>()

  const dialogRef = ref<ArtDialogExpose<SystemParam | undefined>>()
  const formRef = ref<ArtFormExpose>()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)

  const createInitialForm = (): SystemParamForm => ({
    id: undefined,
    paramName: '',
    paramKey: '',
    groupCode: '',
    groupName: '',
    paramType: 'single_text',
    defaultValue: '',
    paramValue: '',
    extendConfigText: '',
    enabled: true,
    builtin: false,
    sort: 1,
    remark: ''
  })

  const groupOptions = computed(() => getDictMap.value.systemParamGroup ?? [])
  const typeOptions = computed(() => getDictMap.value.systemParamType ?? [])

  const formModel = reactive<SystemParamForm>(createInitialForm())

  const formState: SystemParamFormState = {
    model: formModel,
    items: computed<FormItem[]>(() => [
      {
        label: '基础信息',
        key: 'basicInfoTitle',
        type: 'divider',
        span: 24,
        props: {
          showLine: false
        }
      },
      {
        label: '参数名称',
        key: 'paramName',
        type: 'input',
        props: {
          maxlength: 100,
          placeholder: '例如：密码最小长度'
        }
      },
      {
        label: '参数键名',
        key: 'paramKey',
        type: 'input',
        props: {
          maxlength: 150,
          disabled: !!formModel.id,
          placeholder: '例如：security.password.min_length'
        }
      },
      {
        label: '分组',
        key: 'groupCode',
        type: 'select',
        props: {
          options: groupOptions.value,
          placeholder: '请选择分组',
          onChange: handleGroupChange
        }
      },
      {
        label: '排序',
        key: 'sort',
        type: 'number',
        props: {
          min: 0,
          step: 1,
          stepStrictly: true,
          controlsPosition: 'right',
          style: { width: '100%' }
        }
      },
      {
        label: '参数类型',
        key: 'paramType',
        type: 'select',
        props: {
          options: typeOptions.value,
          placeholder: '请选择参数类型',
          onChange: handleTypeChange
        }
      },
      {
        label: '状态与内容',
        key: 'statusContentTitle',
        type: 'divider',
        span: 24,
        props: {
          showLine: false
        }
      },
      {
        label: '状态',
        key: 'enabled',
        type: 'switch',
        span: 6
      },
      {
        label: '内置参数',
        key: 'builtin',
        type: 'switch',
        span: 6,
        props: {
          disabled: formState.model.id && formState.model.builtin
        }
      },
      {
        label: '默认值',
        key: 'defaultValue',
        type: 'input',
        span: 24,
        props: {
          maxlength: 500,
          placeholder: '可选，用于记录兜底值或回滚基线'
        }
      },
      {
        label: '参数值',
        key: 'paramValue',
        type: 'input',
        span: 24
      },
      {
        label: '扩展配置',
        key: 'extendConfigText',
        type: 'input',
        span: 24,
        props: {
          type: 'textarea',
          rows: 4,
          maxlength: 5000,
          showWordLimit: true,
          placeholder: '可选，支持 JSON 对象，如下拉选项、说明元数据等'
        }
      },
      {
        label: '备注',
        key: 'remark',
        type: 'input',
        span: 24,
        props: {
          type: 'textarea',
          rows: 3,
          maxlength: 255,
          showWordLimit: true,
          placeholder: '请输入参数用途、影响范围或维护说明'
        }
      }
    ]),
    rules: computed<FormRules<SystemParamForm>>(() => ({
      paramName: [{ required: true, message: '请输入参数名称', trigger: 'blur' }],
      paramKey: [
        { required: true, message: '请输入参数键名', trigger: 'blur' },
        {
          pattern: /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/,
          message: '键名需使用小写字母、数字、下划线和点号分层，例如 security.password.min_length',
          trigger: 'blur'
        },
        {
          validator: uniqueValidator({
            table: 'sys_param',
            field: 'param_key',
            getExcludeId: (): string | undefined => formModel.id,
            message: '参数键名已存在'
          }),
          trigger: 'blur'
        }
      ],
      groupCode: [{ required: true, message: '请选择分组', trigger: 'change' }],
      paramType: [{ required: true, message: '请选择参数类型', trigger: 'change' }],
      paramValue: [
        { required: true, message: '请输入参数值', trigger: 'blur' },
        { validator: validateParamValue, trigger: 'blur' }
      ],
      extendConfigText: [{ validator: validateExtendConfig, trigger: 'blur' }]
    }))
  }

  const typeLabel = computed(
    () => typeOptions.value.find((item) => item.value === formState.model.paramType)?.label ?? ''
  )
  const previewValue = computed(() => {
    if (formState.model.paramValue === '') return '-'
    return formState.model.paramValue.length > 120
      ? `${formState.model.paramValue.slice(0, 120)}...`
      : formState.model.paramValue
  })
  const numberParamValue = computed<number | undefined>({
    get: () => {
      if (formState.model.paramValue === '') return undefined
      const value = Number(formState.model.paramValue)
      return Number.isNaN(value) ? undefined : value
    },
    set: (value) => {
      formState.model.paramValue = value === undefined ? '' : String(value)
    }
  })

  const handleGroupChange = (value: string): void => {
    const group = groupOptions.value.find((item) => item.value === value)
    formState.model.groupName = group?.label ?? ''
  }

  const handleTypeChange = (value: SystemParamType): void => {
    if (value === 'boolean') {
      formState.model.paramValue = 'true'
      formState.model.defaultValue = formState.model.defaultValue || 'true'
      return
    }

    if (value === 'json') {
      formState.model.paramValue = '{}'
      formState.model.defaultValue = formState.model.defaultValue || '{}'
      return
    }

    formState.model.paramValue = ''
  }

  const validateParamValue = (_rule: unknown, value: string, callback: (error?: Error) => void) => {
    if (formState.model.paramType === 'number' && Number.isNaN(Number(value))) {
      callback(new Error('参数值必须是数字'))
      return
    }

    if (formState.model.paramType === 'boolean' && !['true', 'false'].includes(String(value))) {
      callback(new Error('参数值必须选择 true 或 false'))
      return
    }

    if (formState.model.paramType === 'json') {
      try {
        const parsed = JSON.parse(value)
        if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object') {
          callback(new Error('参数值必须是 JSON 对象'))
          return
        }
      } catch {
        callback(new Error('请输入合法 JSON'))
        return
      }
    }

    callback()
  }

  const validateExtendConfig = (
    _rule: unknown,
    value: string,
    callback: (error?: Error) => void
  ) => {
    if (!value) {
      callback()
      return
    }

    try {
      const parsed = JSON.parse(value)
      if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object') {
        callback(new Error('扩展配置必须是 JSON 对象'))
        return
      }
    } catch {
      callback(new Error('请输入合法 JSON'))
      return
    }

    callback()
  }

  const resetForm = async (): Promise<void> => {
    Object.assign(formState.model, createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const initializeForm = (row: SystemParam): void => {
    Object.assign(formState.model, {
      ...createInitialForm(),
      ...cloneDeep(omit(row, ['extendConfig'])),
      extendConfigText: row.extendConfig ? JSON.stringify(row.extendConfig, null, 2) : ''
    })
  }

  const buildPayload = (): SystemParam => {
    const raw = toRaw(formState.model)
    const group = groupOptions.value.find((item) => item.value === raw.groupCode)
    const payload = omit(raw, [
      'extendConfigText',
      'tenantId',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime'
    ]) as SystemParam

    return {
      ...payload,
      groupName: group?.label ?? raw.groupName,
      defaultValue: raw.defaultValue === '' ? null : raw.defaultValue,
      extendConfig: raw.extendConfigText ? JSON.parse(raw.extendConfigText) : {}
    }
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const payload = buildPayload()
      if (formState.model.id) {
        await editSystemParam(payload)
      } else {
        await addSystemParam(payload)
      }
      emit('success', formState.model.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: SystemParam): Promise<void> => {
    await resetForm()
    if (row?.id) {
      initializeForm(row)
    }
    if (!formState.model.groupName && formState.model.groupCode) {
      handleGroupChange(formState.model.groupCode)
    }

    await dialogRef.value?.handleOpen(row, {
      title: row?.id ? '编辑参数' : '新增参数',
      dialogProps: {
        class: 'system-param-dialog-shell'
      },
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen
  })
</script>

<style scoped lang="scss">
  .system-param-dialog {
    position: relative;
    display: flex;
    gap: 12px;
    height: 72vh;
    max-height: 620px;
    min-height: 0;
    overflow: hidden;

    &__form,
    &__preview,
    &__tips {
      border: 1px solid var(--el-border-color-light);
      border-radius: var(--art-surface-radius);
    }

    &__form {
      display: flex;
      flex-direction: column;
      flex: 1;
      min-width: 0;
      min-height: 0;
      overflow: hidden;
    }

    &__section-head {
      display: flex;
      gap: 12px;
      align-items: flex-start;
      justify-content: space-between;
      padding: 16px 16px 12px;
      border-bottom: 1px solid var(--el-border-color-lighter);

      h3 {
        margin: 0 0 6px;
        font-size: 14px;
        font-weight: 700;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 0;
        font-size: 12px;
        line-height: 1.6;
        color: var(--art-text-gray-500);
      }
    }

    &__form-body {
      flex: 1;
      height: 100%;
      min-height: 0;
      overscroll-behavior: contain;

      :deep(.art-form) {
        padding: 12px 16px 4px !important;
      }

      :deep(.el-scrollbar__view) {
        min-height: 100%;
      }

      :deep(.el-form-item) {
        margin-bottom: 18px;
      }

      :deep(.el-form-item__label) {
        align-items: center;
        height: auto;
        margin-bottom: 6px;
        line-height: 1.4;
      }
    }

    &__divider {
      display: flex;
      flex-direction: column;
      gap: 4px;
      padding-top: 2px;

      span {
        margin: 0;
        font-size: 12px;
        font-weight: 400;
        line-height: 1.6;
        color: var(--art-text-gray-500);
      }
    }

    &__side {
      flex: 0 0 210px;
      width: 210px;
      height: 100%;
      min-height: 0;

      :deep(.el-scrollbar__view) {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
    }

    &__preview,
    &__tips {
      padding: 14px;

      h3 {
        margin: 0 0 14px;
        font-size: 14px;
        font-weight: 700;
        color: var(--art-text-gray-900);
      }
    }

    &__preview {
      dl {
        margin: 0;
      }

      dt {
        margin-bottom: 5px;
        font-size: 12px;
        color: var(--art-text-gray-500);
      }

      dd {
        min-width: 0;
        margin: 0 0 12px;
        overflow-wrap: anywhere;
        font-size: 13px;
        color: var(--art-text-gray-800);
      }
    }

    &__preview-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
    }

    &__value-preview {
      min-height: 34px;
      padding: 9px 10px;
      background: var(--el-fill-color-lighter);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--art-control-radius);
    }

    &__tips {
      ul {
        padding-left: 18px;
        margin: 0;
        list-style: disc;
      }

      li {
        margin-bottom: 10px;
        font-size: 12px;
        line-height: 1.7;
        color: var(--art-text-gray-600);
      }
    }

    &__full-control {
      width: 100%;
    }
  }

  @media (max-width: 900px) {
    .system-param-dialog {
      height: 72vh;
      max-height: 620px;

      &__form {
        min-height: 0;
      }

      &__side {
        display: none;
      }
    }
  }

  :global(.system-param-dialog-shell > .el-dialog__body) {
    overflow: hidden;
  }
</style>
