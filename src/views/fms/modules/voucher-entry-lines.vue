<template>
  <section class="voucher-entry-lines art-card-xs" aria-label="凭证分录">
    <div class="voucher-entry-lines__header">
      <div>
        <ArtSectionTitle :show-line="false">凭证分录</ArtSectionTitle>
        <p>借贷金额必须平衡；科目启用外币、数量或辅助核算时，请同步填写对应信息。</p>
      </div>
      <ElButton v-if="!readonly" type="primary" plain @click="addLine">
        <ArtSvgIcon icon="ri:add-line" />新增分录
      </ElButton>
    </div>

    <ArtTable
      :data="modelValue"
      :columns="columns"
      :pagination="false"
      table-layout="fixed"
      empty-text="暂无凭证分录"
      empty-description="至少录入两条借贷平衡的会计分录。"
      empty-height="180px"
      border
    />

    <div class="voucher-entry-lines__totals" :class="{ 'is-balanced': isBalanced }">
      <span>分录 {{ modelValue.length }} 条</span>
      <strong>借方 {{ formatMoney(totalDebit) }}</strong>
      <strong>贷方 {{ formatMoney(totalCredit) }}</strong>
      <span>差额 {{ formatMoney(difference) }}</span>
      <ElTag :type="isBalanced ? 'success' : 'danger'" effect="dark">
        {{ isBalanced ? '借贷平衡' : '借贷不平' }}
      </ElTag>
    </div>
  </section>
</template>

<script setup lang="tsx">
  import { round } from 'lodash-es'
  import { ElInput, ElInputNumber, ElOption, ElSelect, ElTag } from 'element-plus'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'FmsVoucherEntryLines' })

  type Line = Api.Fms.VoucherLineRecord
  type Subject = Api.Fms.SubjectRecord

  interface Props {
    modelValue: Line[]
    subjects: Subject[]
    currencies: Api.Fms.CurrencyRecord[]
    auxiliaryItems: Api.Fms.AuxiliaryItemRecord[]
    readonly?: boolean
    allowZeroAmount?: boolean
    mode?: 'voucher' | 'template'
    directionOptions?: Array<{ label: string; value: Api.Fms.BalanceDirection }>
  }

  const props = withDefaults(defineProps<Props>(), {
    readonly: false,
    allowZeroAmount: false,
    mode: 'voucher',
    directionOptions: () => []
  })
  const emit = defineEmits<{ 'update:modelValue': [value: Line[]] }>()

  const subjectOptions = computed(() =>
    props.subjects
      .filter(
        (subject) =>
          subject.isEnabled &&
          !props.subjects.some((candidate) => candidate.parentId === subject.id)
      )
      .map((subject) => ({
        label: `${subject.subjectCode} ${subject.subjectName}`,
        value: subject.id
      }))
  )
  const foreignCurrencies = computed(() =>
    props.currencies.filter((item) => !item.isBase && item.isEnabled)
  )
  const totalDebit = computed(() =>
    round(
      props.modelValue.reduce((sum, row) => sum + Number(row.debitAmount || 0), 0),
      2
    )
  )
  const totalCredit = computed(() =>
    round(
      props.modelValue.reduce((sum, row) => sum + Number(row.creditAmount || 0), 0),
      2
    )
  )
  const difference = computed(() => round(totalDebit.value - totalCredit.value, 2))
  const isTemplateMode = computed(() => props.mode === 'template')
  const isBalanced = computed(
    () => totalDebit.value === totalCredit.value && (props.allowZeroAmount || totalDebit.value > 0)
  )

  function createLine(): Line {
    return {
      lineNo: props.modelValue.length + 1,
      summary: '',
      subjectId: '',
      auxiliaryValues: {},
      currencyId: null,
      exchangeRate: 1,
      originalAmount: 0,
      quantity: 0,
      debitAmount: 0,
      creditAmount: 0,
      entryDirection: isTemplateMode.value ? 'debit' : undefined
    }
  }

  function subjectFor(row: Line): Subject | undefined {
    return props.subjects.find((subject) => subject.id === row.subjectId)
  }

  function updateLine(row: Line, patch: Partial<Line>): void {
    emit(
      'update:modelValue',
      props.modelValue.map((item) => (item === row ? { ...item, ...patch } : item))
    )
  }

  function handleSubjectChange(row: Line, subjectId: string): void {
    updateLine(row, {
      subjectId,
      auxiliaryValues: {},
      currencyId: null,
      exchangeRate: 1,
      originalAmount: 0,
      quantity: 0
    })
  }

  function handleOriginalAmountChange(row: Line, value: number): void {
    const amount = round(Number(value || 0) * Number(row.exchangeRate || 1), 2)
    const patch: Partial<Line> = { originalAmount: Number(value || 0) }
    if (
      row.entryDirection === 'debit' ||
      (row.entryDirection == null &&
        (row.debitAmount > 0 || (row.creditAmount === 0 && row.debitAmount === 0)))
    ) {
      patch.debitAmount = amount
      patch.creditAmount = 0
    } else {
      patch.creditAmount = amount
      patch.debitAmount = 0
    }
    updateLine(row, patch)
  }

  function handleRateChange(row: Line, value: number): void {
    const rate = Number(value || 1)
    const amount = round(Number(row.originalAmount || 0) * rate, 2)
    updateLine(row, {
      exchangeRate: rate,
      debitAmount: row.debitAmount > 0 ? amount : 0,
      creditAmount: row.creditAmount > 0 ? amount : 0
    })
  }

  function handleDirectionChange(row: Line, direction: Api.Fms.BalanceDirection): void {
    const amount = Math.max(Number(row.debitAmount || 0), Number(row.creditAmount || 0))
    updateLine(row, {
      entryDirection: direction,
      debitAmount: direction === 'debit' ? amount : 0,
      creditAmount: direction === 'credit' ? amount : 0
    })
  }

  function handleTemplateAmountChange(row: Line, value: number): void {
    const amount = Number(value ?? 0)
    const direction = row.entryDirection ?? 'debit'
    updateLine(row, {
      entryDirection: direction,
      debitAmount: direction === 'debit' ? amount : 0,
      creditAmount: direction === 'credit' ? amount : 0
    })
  }

  function addLine(): void {
    emit('update:modelValue', [...props.modelValue, createLine()])
  }

  function removeLine(row: Line): void {
    emit(
      'update:modelValue',
      props.modelValue
        .filter((item) => item !== row)
        .map((item, index) => ({ ...item, lineNo: index + 1 }))
    )
  }

  const columns = computed<ColumnOption<Line>[]>(() => [
    { prop: 'lineNo', label: '行号', width: 64, fixed: 'left', align: 'center' },
    {
      prop: 'summary',
      label: '摘要',
      minWidth: 170,
      formatter: (row) =>
        props.readonly ? (
          row.summary || '—'
        ) : (
          <ElInput
            modelValue={row.summary}
            maxlength={120}
            placeholder="分录摘要"
            onUpdate:modelValue={(value: string) => updateLine(row, { summary: value })}
          />
        )
    },
    {
      prop: 'subjectId',
      label: '会计科目',
      minWidth: 220,
      formatter: (row) => {
        const subject = subjectFor(row)
        if (props.readonly)
          return subject
            ? `${subject.subjectCode} ${subject.subjectName}`
            : row.subjectNameSnapshot || '—'
        return (
          <ElSelect
            modelValue={row.subjectId}
            filterable
            placeholder="选择末级科目"
            class="w-full!"
            onUpdate:modelValue={(value: string) => handleSubjectChange(row, value)}
          >
            {subjectOptions.value.map((item) => (
              <ElOption key={item.value} label={item.label} value={item.value} />
            ))}
          </ElSelect>
        )
      }
    },
    ...(isTemplateMode.value
      ? [
          {
            prop: 'entryDirection',
            label: '借贷方向',
            width: 128,
            formatter: (row: Line) =>
              props.readonly ? (
                (props.directionOptions.find((item) => item.value === row.entryDirection)?.label ??
                '—')
              ) : (
                <ElSelect
                  modelValue={row.entryDirection ?? 'debit'}
                  class="w-full!"
                  onUpdate:modelValue={(value: Api.Fms.BalanceDirection) =>
                    handleDirectionChange(row, value)
                  }
                >
                  {props.directionOptions.map((item) => (
                    <ElOption key={item.value} label={item.label} value={item.value} />
                  ))}
                </ElSelect>
              )
          }
        ]
      : []),
    {
      prop: 'auxiliaryValues',
      label: '辅助核算',
      minWidth: 210,
      formatter: (row) => {
        const configs = subjectFor(row)?.auxiliaryConfigs ?? []
        if (!configs.length) return '—'
        if (props.readonly) {
          return (
            configs
              .map((config) => {
                const item = props.auxiliaryItems.find(
                  (candidate) => candidate.id === row.auxiliaryValues[config.auxiliaryTypeId]
                )
                return item ? `${config.auxiliaryType?.typeName}：${item.itemName}` : ''
              })
              .filter(Boolean)
              .join('；') || '—'
          )
        }
        return (
          <div class="voucher-entry-lines__auxiliary">
            {configs.map((config) => (
              <ElSelect
                key={config.auxiliaryTypeId}
                modelValue={row.auxiliaryValues[config.auxiliaryTypeId]}
                filterable
                clearable={!config.isRequired}
                placeholder={`${config.auxiliaryType?.typeName ?? '核算维度'}${config.isRequired ? '*' : ''}`}
                onUpdate:modelValue={(value?: string) =>
                  updateLine(row, {
                    auxiliaryValues: {
                      ...row.auxiliaryValues,
                      [config.auxiliaryTypeId]: value || ''
                    }
                  })
                }
              >
                {props.auxiliaryItems
                  .filter(
                    (item) => item.auxiliaryTypeId === config.auxiliaryTypeId && item.isEnabled
                  )
                  .map((item) => (
                    <ElOption
                      key={item.id}
                      label={`${item.itemCode} ${item.itemName}`}
                      value={item.id}
                    />
                  ))}
              </ElSelect>
            ))}
          </div>
        )
      }
    },
    {
      prop: 'currencyId',
      label: '外币 / 原币',
      minWidth: 180,
      formatter: (row) => {
        const subject = subjectFor(row)
        if (!subject?.allowForeignCurrency) return '—'
        if (props.readonly) {
          return row.currencyCodeSnapshot
            ? `${row.currencyCodeSnapshot} ${Number(row.originalAmount).toLocaleString('zh-CN')}`
            : '—'
        }
        return (
          <div class="voucher-entry-lines__currency">
            <ElSelect
              modelValue={row.currencyId}
              clearable
              placeholder="币种"
              onUpdate:modelValue={(value?: string) =>
                updateLine(row, {
                  currencyId: value || null,
                  originalAmount: value ? row.originalAmount : 0,
                  exchangeRate: value ? row.exchangeRate : 1
                })
              }
            >
              {foreignCurrencies.value.map((item) => (
                <ElOption key={item.id} label={item.currencyCode} value={item.id} />
              ))}
            </ElSelect>
            <ElInputNumber
              modelValue={row.originalAmount}
              min={0}
              precision={2}
              controls={false}
              disabled={!row.currencyId}
              placeholder="原币金额"
              onUpdate:modelValue={(value?: number) =>
                handleOriginalAmountChange(row, Number(value ?? 0))
              }
            />
          </div>
        )
      }
    },
    {
      prop: 'exchangeRate',
      label: '汇率',
      width: 120,
      formatter: (row) =>
        props.readonly ? (
          row.currencyId ? (
            Number(row.exchangeRate).toFixed(6)
          ) : (
            '—'
          )
        ) : (
          <ElInputNumber
            modelValue={row.exchangeRate}
            min={0.0000000001}
            precision={6}
            controls={false}
            disabled={!row.currencyId}
            class="w-full!"
            onUpdate:modelValue={(value?: number) => handleRateChange(row, Number(value ?? 1))}
          />
        )
    },
    {
      prop: 'quantity',
      label: '数量',
      width: 120,
      formatter: (row) => {
        const subject = subjectFor(row)
        if (!subject?.allowQuantity) return '—'
        return props.readonly ? (
          `${Number(row.quantity).toLocaleString('zh-CN')} ${subject.unitName ?? ''}`
        ) : (
          <ElInputNumber
            modelValue={row.quantity}
            min={0}
            precision={4}
            controls={false}
            class="w-full!"
            onUpdate:modelValue={(value?: number) =>
              updateLine(row, { quantity: Number(value ?? 0) })
            }
          />
        )
      }
    },
    ...(isTemplateMode.value
      ? [
          {
            prop: 'defaultAmount',
            label: '默认金额',
            width: 150,
            align: 'right' as const,
            formatter: (row: Line) =>
              props.readonly ? (
                formatMoney(Math.max(Number(row.debitAmount || 0), Number(row.creditAmount || 0)))
              ) : (
                <ElInputNumber
                  modelValue={Math.max(Number(row.debitAmount || 0), Number(row.creditAmount || 0))}
                  min={0}
                  precision={2}
                  controls={false}
                  class="w-full!"
                  onUpdate:modelValue={(value?: number) =>
                    handleTemplateAmountChange(row, Number(value ?? 0))
                  }
                />
              )
          }
        ]
      : [
          {
            prop: 'debitAmount',
            label: '借方金额',
            width: 145,
            align: 'right' as const,
            formatter: (row: Line) =>
              props.readonly ? (
                formatMoney(row.debitAmount)
              ) : (
                <ElInputNumber
                  modelValue={row.debitAmount}
                  min={0}
                  precision={2}
                  controls={false}
                  class="w-full!"
                  onUpdate:modelValue={(value?: number) =>
                    updateLine(row, {
                      debitAmount: Number(value ?? 0),
                      creditAmount: Number(value ?? 0) > 0 ? 0 : row.creditAmount
                    })
                  }
                />
              )
          },
          {
            prop: 'creditAmount',
            label: '贷方金额',
            width: 145,
            align: 'right' as const,
            formatter: (row: Line) =>
              props.readonly ? (
                formatMoney(row.creditAmount)
              ) : (
                <ElInputNumber
                  modelValue={row.creditAmount}
                  min={0}
                  precision={2}
                  controls={false}
                  class="w-full!"
                  onUpdate:modelValue={(value?: number) =>
                    updateLine(row, {
                      creditAmount: Number(value ?? 0),
                      debitAmount: Number(value ?? 0) > 0 ? 0 : row.debitAmount
                    })
                  }
                />
              )
          }
        ]),
    ...(props.readonly
      ? []
      : [
          {
            prop: 'operation',
            label: '操作',
            width: 72,
            fixed: 'right' as const,
            formatter: (row: Line) => (
              <ArtButtonTable type="delete" onClick={() => removeLine(row)} />
            )
          }
        ])
  ])

  function formatMoney(value: number): string {
    return formatCurrencyValue(Number(value || 0))
  }

  defineExpose({ addLine, isBalanced, totalDebit, totalCredit })
</script>

<style scoped lang="scss">
  .voucher-entry-lines {
    min-width: 0;
    padding: var(--art-space-4);

    &__header,
    &__totals {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;
      justify-content: space-between;
    }

    &__header {
      margin-bottom: var(--art-space-3);

      p {
        margin: 4px 0 0;
        font-size: 13px;
        color: var(--el-text-color-secondary);
      }
    }

    &__auxiliary,
    &__currency {
      display: grid;
      gap: 6px;
    }

    &__currency {
      grid-template-columns: 72px minmax(100px, 1fr);
    }

    &__totals {
      justify-content: flex-end;
      padding-top: var(--art-space-3);
      color: var(--el-color-danger);

      &.is-balanced {
        color: var(--el-color-success);
      }
    }

    @media (width <= 680px) {
      &__header,
      &__totals {
        flex-wrap: wrap;
      }

      &__header {
        align-items: flex-start;
      }
    }
  }
</style>
