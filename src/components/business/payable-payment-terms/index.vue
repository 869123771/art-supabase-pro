<template>
  <ArtPermissionGuard :permission="permissions.View" resource-name="付款条件">
    <div class="business-workspace-page art-full-height min-w-0">
      <BusinessWorkspaceHeader
        title="付款条件"
        description="维护供应商应付账期，作为应付单付款计划的到期日依据。停用后不影响历史单据。"
        icon="ri:calendar-line"
        density="compact"
      >
        <template #actions><BusinessTableWorkspaceActions :table="tableRef" /></template>
      </BusinessWorkspaceHeader>
      <ArtTableQuery
        ref="tableRef"
        :api-fn="fetchPaymentTerms"
        :columns-factory="columnsFactory"
        :search-items="[
          {
            key: 'keyword',
            label: '查询条件',
            type: 'input',
            props: { placeholder: '编号、名称', clearable: true }
          }
        ]"
        :header-actions="[{ type: 'add', permission: permissions.Add, onClick: () => open() }]"
        header-actions-placement="workspace"
        focusable
      />
      <ArtDialog ref="dialogRef" size="md" confirm-text="保存付款条件">
        <ArtForm
          ref="formRef"
          v-model="form"
          :items="items"
          :rules="{
            code: [{ required: true, message: '请填写编号' }],
            name: [{ required: true, message: '请填写名称' }]
          }"
          :show-submit="false"
          :show-reset="false"
          :span="12"
          label-position="top"
        />
      </ArtDialog>
    </div>
  </ArtPermissionGuard>
</template>
<script setup lang="tsx">
  import { ElMessage, ElTag } from 'element-plus'
  import {
    fetchPaymentTerms,
    savePaymentTerm,
    type PaymentTerm,
    type PayablePermissions
  } from '@/api/purchase-payable'
  import { notifyFriendlyError } from '@/hooks/core/useArtFeedback'
  import { validateArtFormForSubmit } from '@/utils/form/validate-art-form'
  import ArtTableQuery from '@/components/core/tables/art-table-query/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import BusinessTableRowActions from '@/components/business/business-table-row-actions/index.vue'
  import type { ColumnOption } from '@/types'
  const props = defineProps<{ permissions: Pick<PayablePermissions, 'View' | 'Add' | 'Edit'> }>()
  const tableRef = ref<InstanceType<typeof ArtTableQuery>>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<InstanceType<typeof ArtForm>>()
  const form = ref<Partial<PaymentTerm>>({})
  const items: FormItem[] = [
    { key: 'code', label: '编号', type: 'input', props: { maxlength: 40 } },
    { key: 'name', label: '名称', type: 'input', props: { maxlength: 100 } },
    {
      key: 'days',
      label: '账期天数',
      type: 'number',
      props: { min: 0, max: 3650, precision: 0 }
    },
    { key: 'enabled', label: '启用', type: 'switch' },
    { key: 'remark', label: '描述', type: 'textarea', span: 24, props: { maxlength: 1000 } }
  ]
  const columnsFactory = (): ColumnOption<PaymentTerm>[] => [
    { prop: 'code', label: '编号', minWidth: 150 },
    { prop: 'name', label: '名称', minWidth: 200 },
    { prop: 'days', label: '账期天数', width: 130 },
    { prop: 'remark', label: '描述', minWidth: 240 },
    {
      prop: 'enabled',
      label: '使用状态',
      width: 120,
      formatter: (row) => (
        <ElTag type={row.enabled ? 'success' : 'info'}>{row.enabled ? '可用' : '停用'}</ElTag>
      )
    },
    {
      prop: 'preset',
      label: '系统预置',
      width: 120,
      formatter: (row) => (row.preset ? '是' : '否')
    },
    {
      prop: 'operation',
      label: '操作',
      width: 90,
      fixed: 'right',
      formatter: (row) => (
        <BusinessTableRowActions>
          <ArtButtonTable
            type="edit"
            permission={props.permissions.Edit}
            label="编辑"
            onClick={() => open(row)}
          />
        </BusinessTableRowActions>
      )
    }
  ]
  async function open(row?: PaymentTerm): Promise<void> {
    form.value = row ? { ...row } : { code: '', name: '', days: 0, enabled: true, remark: '' }
    await dialogRef.value?.handleOpen(undefined, {
      title: row ? '编辑付款条件' : '新增付款条件',
      onConfirm: async () => {
        if (!(await validateArtFormForSubmit(formRef.value))) return false
        try {
          await savePaymentTerm(form.value)
          ElMessage.success('付款条件已保存')
          await tableRef.value?.refreshData()
          return true
        } catch (error) {
          notifyFriendlyError(error, '付款条件未保存，请重试')
          return false
        }
      }
    })
  }
</script>
