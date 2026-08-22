<template>
  <section v-if="cashLines.length" class="cash-flow-allocation-panel art-card-xs">
    <div class="cash-flow-allocation-panel__header">
      <div>
        <ArtSectionTitle :show-line="false">现金流量归集</ArtSectionTitle>
        <p>现金及现金等价物分录需按流入/流出项目全额归集，提交时由数据库再次校验。</p>
      </div>
      <ElTag type="warning" effect="plain">{{ cashLines.length }} 条现金分录</ElTag>
    </div>

    <ElAlert
      v-if="!statementItems.length"
      type="warning"
      :closable="false"
      show-icon
      title="当前账套尚未初始化现金流量表项目，请先到“财务报表 → 取数口径”完成初始化。"
    />

    <div class="cash-flow-allocation-panel__lines">
      <article
        v-for="line in cashLines"
        :key="line.lineNo"
        class="cash-flow-allocation-panel__line"
      >
        <header>
          <div class="cash-flow-allocation-panel__identity">
            <span>分录 {{ line.lineNo }}</span>
            <strong>{{ subjectLabel(line) }}</strong>
            <small>{{ line.summary || '未填写摘要' }}</small>
          </div>
          <div class="cash-flow-allocation-panel__amount">
            <ElTag :type="lineDirection(line) === 'receipt' ? 'success' : 'warning'" effect="plain">
              {{ dictLabel('fmsCashFlowDirection', lineDirection(line)) }}
            </ElTag>
            <strong>{{ formatCurrencyValue(lineAmount(line)) }}</strong>
            <small>待归集 {{ formatCurrencyValue(remainingAmount(line)) }}</small>
          </div>
        </header>

        <ElTable
          :data="allocationsFor(line.lineNo)"
          table-layout="fixed"
          border
          empty-text="尚未添加归集项目"
        >
          <ElTableColumn label="现金流量项目" min-width="280">
            <template #default="{ row }">
              <ElSelect
                v-model="row.statementItemId"
                filterable
                class="!w-full"
                placeholder="请选择现金流量项目"
                :disabled="readonly"
              >
                <ElOption
                  v-for="option in itemOptions(line)"
                  :key="option.value"
                  :label="option.label"
                  :value="option.value"
                />
              </ElSelect>
            </template>
          </ElTableColumn>
          <ElTableColumn label="归集金额" width="180">
            <template #default="{ row }">
              <ElInputNumber
                v-model="row.amount"
                :min="0.01"
                :max="lineAmount(line)"
                :precision="2"
                :step="100"
                controls-position="right"
                class="!w-full"
                :disabled="readonly"
              />
            </template>
          </ElTableColumn>
          <ElTableColumn label="备注" min-width="180">
            <template #default="{ row }">
              <ElInput
                v-model="row.remark"
                maxlength="200"
                placeholder="可选"
                :disabled="readonly"
              />
            </template>
          </ElTableColumn>
          <ElTableColumn v-if="!readonly" label="操作" width="78" fixed="right" align="center">
            <template #default="{ row }">
              <ElButton type="danger" link @click="removeAllocation(row)">删除</ElButton>
            </template>
          </ElTableColumn>
        </ElTable>

        <footer>
          <ElButton
            v-if="!readonly"
            type="primary"
            plain
            :disabled="!statementItems.length || remainingAmount(line) <= 0"
            @click="addAllocation(line)"
          >
            <ArtSvgIcon icon="ri:add-line" />
            {{ allocationsFor(line.lineNo).length ? '拆分归集' : '添加归集' }}
          </ElButton>
        </footer>
      </article>
    </div>
  </section>
</template>

<script setup lang="ts">
  import { ElMessage } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { useUserStore } from '@/store/modules/user'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'FinanceCashFlowAllocationPanel' })

  type VoucherLine = Api.Fms.VoucherLineRecord
  type Draft = Api.Fms.VoucherCashFlowAllocationDraft

  const props = withDefaults(
    defineProps<{
      lines: VoucherLine[]
      subjects: Api.Fms.SubjectRecord[]
      statementItems: Api.Fms.FinancialStatementItemRecord[]
      readonly?: boolean
    }>(),
    { readonly: false }
  )
  const model = defineModel<Draft[]>({ default: () => [] })
  const { getDictMap } = storeToRefs(useUserStore())

  const cashLines = computed(() => props.lines.filter((line) => subjectFor(line)?.cashFlowRequired))

  watch(
    () => props.lines.map((line) => `${line.lineNo}:${line.subjectId}`).join('|'),
    () => {
      const validLineNos = new Set(cashLines.value.map((line) => line.lineNo))
      model.value = model.value.filter((item) => validLineNos.has(item.voucherLineNo))
    }
  )

  function subjectFor(line: VoucherLine): Api.Fms.SubjectRecord | undefined {
    return props.subjects.find((item) => item.id === line.subjectId)
  }

  function subjectLabel(line: VoucherLine): string {
    const subject = subjectFor(line)
    return subject ? `${subject.subjectCode} ${subject.subjectName}` : '未选择现金科目'
  }

  function lineDirection(line: VoucherLine): Api.Fms.CashFlowDirection {
    return Number(line.debitAmount || 0) > 0 ? 'receipt' : 'payment'
  }

  function lineAmount(line: VoucherLine): number {
    return Math.max(Number(line.debitAmount || 0), Number(line.creditAmount || 0))
  }

  function allocationsFor(lineNo: number): Draft[] {
    return model.value.filter((item) => item.voucherLineNo === lineNo)
  }

  function allocatedAmount(lineNo: number): number {
    return allocationsFor(lineNo).reduce((sum, item) => sum + Number(item.amount || 0), 0)
  }

  function remainingAmount(line: VoucherLine): number {
    return Math.max(lineAmount(line) - allocatedAmount(line.lineNo), 0)
  }

  function itemOptions(line: VoucherLine) {
    const direction = lineDirection(line)
    return props.statementItems
      .filter(
        (item) =>
          item.isEnabled &&
          item.calculationMethod === 'mapping' &&
          item.cashFlowDirection === direction
      )
      .map((item) => ({ label: `${item.itemCode} ${item.itemName}`, value: item.id }))
  }

  function addAllocation(line: VoucherLine): void {
    const remaining = remainingAmount(line)
    if (remaining <= 0) return
    model.value.push({
      voucherLineNo: line.lineNo,
      statementItemId: '',
      amount: remaining,
      remark: null
    })
  }

  function removeAllocation(row: unknown): void {
    const index = model.value.indexOf(row as Draft)
    if (index >= 0) model.value.splice(index, 1)
  }

  function dictLabel(code: string, value: unknown): string {
    return (
      (getDictMap.value[code] ?? []).find((item) => String(item.value) === String(value))?.label ??
      String(value ?? '')
    )
  }

  function validate(requireComplete = true): boolean {
    if (!cashLines.value.length) return true
    if (!props.statementItems.length) {
      if (!requireComplete) return true
      ElMessage.warning('请先初始化现金流量表项目')
      return false
    }
    if (model.value.some((item) => !item.statementItemId || Number(item.amount) <= 0)) {
      ElMessage.warning('请完整填写现金流量项目和归集金额')
      return false
    }
    for (const line of cashLines.value) {
      const allocated = allocatedAmount(line.lineNo)
      const amount = lineAmount(line)
      if (allocated - amount > 0.005) {
        ElMessage.warning(`第 ${line.lineNo} 条现金分录的归集金额超过分录金额`)
        return false
      }
      if (requireComplete && Math.abs(allocated - amount) > 0.005) {
        ElMessage.warning(`第 ${line.lineNo} 条现金分录尚未完成全额归集`)
        return false
      }
    }
    return true
  }

  defineExpose({ validate })
</script>

<style scoped lang="scss">
  .cash-flow-allocation-panel {
    display: grid;
    gap: var(--art-space-4);
    min-width: 0;
    padding: var(--art-space-4);

    &__header,
    &__line > header,
    &__line > footer {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;
      justify-content: space-between;
    }

    &__header p {
      margin: 4px 0 0;
      font-size: 13px;
      line-height: 1.5;
      color: var(--el-text-color-secondary);
    }

    &__lines {
      display: grid;
      gap: var(--art-space-3);
    }

    &__line {
      display: grid;
      gap: var(--art-space-3);
      min-width: 0;
      padding: var(--art-space-3);
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      > footer {
        justify-content: flex-end;
      }
    }

    &__identity,
    &__amount {
      display: flex;
      min-width: 0;
    }

    &__identity {
      flex-direction: column;
      gap: 3px;

      span,
      small {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }

      strong {
        color: var(--art-text-gray-900);
      }
    }

    &__amount {
      gap: var(--art-space-2);
      align-items: center;

      strong {
        font-size: 16px;
        color: var(--art-text-gray-900);
      }

      small {
        color: var(--el-text-color-secondary);
      }
    }
  }

  @media (width <= 720px) {
    .cash-flow-allocation-panel {
      &__header,
      &__line > header {
        flex-direction: column;
        align-items: flex-start;
      }

      &__amount {
        flex-wrap: wrap;
      }
    }
  }
</style>
