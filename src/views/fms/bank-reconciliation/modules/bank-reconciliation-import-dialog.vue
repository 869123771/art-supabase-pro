<template>
  <ArtDialog ref="dialogRef" size="xl">
    <template #subtitle>
      导入前请核对对账期间和期初、期末余额；对方账号只保存掩码，不保留明文。
    </template>
    <div class="bank-import-dialog">
      <ArtForm
        ref="formRef"
        v-model="form.data"
        :items="formItems"
        :rules="form.rules"
        :span="12"
        :gutter="20"
        label-width="112px"
        :show-reset="false"
        :show-submit="false"
      />

      <section class="bank-import-dialog__lines">
        <div class="bank-import-dialog__lines-header">
          <div>
            <strong>银行流水明细</strong>
            <span>支持一笔银行流水匹配多笔资金流水，也支持一笔资金流水分摊匹配。</span>
          </div>
          <ElButton type="primary" plain @click="addLine">
            <ArtSvgIcon icon="ri:add-line" />
            添加流水
          </ElButton>
        </div>
        <ElTable :data="form.data.lines" border table-layout="fixed" max-height="360">
          <ElTableColumn type="index" label="#" width="48" align="center" />
          <ElTableColumn label="交易日期" width="150">
            <template #default="{ row }">
              <ElDatePicker
                v-model="row.transactionDate"
                type="date"
                value-format="YYYY-MM-DD"
                placeholder="选择日期"
                class="!w-full"
              />
            </template>
          </ElTableColumn>
          <ElTableColumn label="方向" width="116">
            <template #default="{ row }">
              <ElSelect v-model="row.direction" placeholder="方向">
                <ElOption
                  v-for="item in getDictMap.fmsFundLedgerDirection ?? []"
                  :key="String(item.value)"
                  :label="item.label"
                  :value="item.value"
                />
              </ElSelect>
            </template>
          </ElTableColumn>
          <ElTableColumn label="金额" width="150">
            <template #default="{ row }">
              <ElInputNumber
                v-model="row.amount"
                :min="0"
                :precision="2"
                :controls="false"
                class="!w-full"
              />
            </template>
          </ElTableColumn>
          <ElTableColumn label="对方名称" min-width="160">
            <template #default="{ row }">
              <ElInput v-model="row.counterpartyName" maxlength="120" placeholder="对方户名" />
            </template>
          </ElTableColumn>
          <ElTableColumn label="对方账号" min-width="170">
            <template #default="{ row }">
              <ElInput
                v-model="row.counterpartyAccount"
                maxlength="64"
                show-password
                autocomplete="new-password"
                placeholder="保存后仅显示尾号"
              />
            </template>
          </ElTableColumn>
          <ElTableColumn label="银行参考号" min-width="155">
            <template #default="{ row }">
              <ElInput v-model="row.bankReference" maxlength="120" placeholder="用于自动匹配" />
            </template>
          </ElTableColumn>
          <ElTableColumn label="摘要" min-width="180">
            <template #default="{ row }">
              <ElInput v-model="row.bankMemo" maxlength="300" placeholder="银行交易摘要" />
            </template>
          </ElTableColumn>
          <ElTableColumn label="操作" width="64" fixed="right" align="center">
            <template #default="{ $index }">
              <ElButton
                link
                type="danger"
                :disabled="form.data.lines.length <= 1"
                @click="removeLine($index)"
              >
                删除
              </ElButton>
            </template>
          </ElTableColumn>
        </ElTable>
      </section>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { FormRules } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import {
    fetchAccountSetOptions,
    fetchFundAccountOptions,
    importBankReconciliation
  } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'FinanceBankReconciliationImportDialog' })

  type FormData = Api.Fms.ImportBankReconciliationPayload

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const accountSetId = ref('')
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const accountOptions = ref<Api.Fms.FundAccountOption[]>([])

  const createLine = (): Api.Fms.ImportBankStatementLinePayload => ({
    transactionDate: dayjs().format('YYYY-MM-DD'),
    direction: 'outflow',
    amount: 0,
    statementBalance: null,
    counterpartyName: null,
    counterpartyAccount: null,
    bankReference: null,
    bankSerialNo: null,
    bankMemo: null
  })

  const createInitialForm = (): FormData => ({
    fundAccountId: '',
    statementStartDate: dayjs().startOf('month').format('YYYY-MM-DD'),
    statementEndDate: dayjs().format('YYYY-MM-DD'),
    openingBalance: 0,
    closingBalance: 0,
    importedFileName: null,
    remark: null,
    lines: [createLine()]
  })

  const form = reactive<{ data: FormData; rules: FormRules<FormData> }>({
    data: createInitialForm(),
    rules: {
      fundAccountId: [{ required: true, message: '请选择对账账户', trigger: 'change' }],
      statementStartDate: [{ required: true, message: '请选择开始日期', trigger: 'change' }],
      statementEndDate: [{ required: true, message: '请选择结束日期', trigger: 'change' }],
      openingBalance: [{ required: true, message: '请输入期初余额', trigger: 'change' }],
      closingBalance: [{ required: true, message: '请输入期末余额', trigger: 'change' }]
    }
  })

  const formItems = computed<FormItem[]>(() => [
    {
      label: '所属账套',
      key: '__accountSetId',
      type: 'select',
      props: {
        modelValue: accountSetId.value,
        options: accountSetOptions.value,
        filterable: true,
        placeholder: '选择核算账套',
        onChange: (value: string) => void handleAccountSetChange(value)
      }
    },
    {
      label: '对账账户',
      key: 'fundAccountId',
      type: 'select',
      props: {
        options: accountOptions.value,
        filterable: true,
        disabled: !accountSetId.value,
        placeholder: '选择已启用银行对账的账户'
      }
    },
    {
      label: '期间开始',
      key: 'statementStartDate',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
    },
    {
      label: '期间结束',
      key: 'statementEndDate',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
    },
    {
      label: '期初余额',
      key: 'openingBalance',
      type: 'number',
      props: { precision: 2, step: 100, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '期末余额',
      key: 'closingBalance',
      type: 'number',
      props: { precision: 2, step: 100, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '来源文件名',
      key: 'importedFileName',
      type: 'input',
      props: { maxlength: 200, placeholder: '例如 2026-08-银行流水.xlsx' }
    },
    {
      label: '导入说明',
      key: 'remark',
      type: 'input',
      props: { maxlength: 300, placeholder: '选填' }
    }
  ])

  function addLine(): void {
    form.data.lines.push(createLine())
  }

  function removeLine(index: number): void {
    if (form.data.lines.length > 1) form.data.lines.splice(index, 1)
  }

  async function handleAccountSetChange(value: string): Promise<void> {
    accountSetId.value = value
    form.data.fundAccountId = ''
    if (!value) {
      accountOptions.value = []
      return
    }
    const { data } = await fetchFundAccountOptions({ accountSetId: value, status: 'active' })
    accountOptions.value = (data ?? []).filter(
      (item) => item.accountType !== 'cash' && item.reconciliationEnabled
    )
  }

  function validateLines(): boolean {
    if (!form.data.lines.length) {
      ElMessage.warning('请至少添加一笔银行流水')
      return false
    }
    const invalidIndex = form.data.lines.findIndex(
      (line) =>
        !line.transactionDate ||
        !line.direction ||
        Number(line.amount) <= 0 ||
        line.transactionDate < form.data.statementStartDate ||
        line.transactionDate > form.data.statementEndDate
    )
    if (invalidIndex >= 0) {
      ElMessage.warning(`第 ${invalidIndex + 1} 行的日期、方向或金额不正确`)
      return false
    }
    const inflow = form.data.lines
      .filter((line) => line.direction === 'inflow')
      .reduce((sum, line) => sum + Number(line.amount), 0)
    const outflow = form.data.lines
      .filter((line) => line.direction === 'outflow')
      .reduce((sum, line) => sum + Number(line.amount), 0)
    if (
      Number((form.data.openingBalance + inflow - outflow).toFixed(2)) !==
      Number(form.data.closingBalance)
    ) {
      ElMessage.warning('期末余额应等于期初余额加流入减流出，请核对银行流水')
      return false
    }
    return true
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      if (!validateLines()) return false
      await importBankReconciliation({
        ...form.data,
        importedFileName: form.data.importedFileName?.trim() || null,
        remark: form.data.remark?.trim() || null,
        lines: form.data.lines.map((line) => ({
          ...line,
          counterpartyName: line.counterpartyName?.trim() || null,
          counterpartyAccount: line.counterpartyAccount?.trim() || null,
          bankReference: line.bankReference?.trim() || null,
          bankSerialNo: line.bankSerialNo?.trim() || null,
          bankMemo: line.bankMemo?.trim() || null
        }))
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(): Promise<void> {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    accountSetId.value = ''
    accountOptions.value = []
    Object.assign(form.data, createInitialForm())
    await dialogRef.value?.handleOpen(undefined, {
      title: '导入银行对账单',
      confirmText: '导入并开始对账',
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false, destroyOnClose: true }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .bank-import-dialog {
    display: grid;
    gap: 20px;
    min-width: 0;

    &__lines {
      min-width: 0;
      padding-top: 18px;
      border-top: 1px solid var(--el-border-color-lighter);
    }

    &__lines-header {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 12px;

      > div {
        display: grid;
        gap: 4px;
      }

      span {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }
  }
</style>
