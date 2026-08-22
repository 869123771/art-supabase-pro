<template>
  <ElTabPane name="contracts">
    <template #label>
      劳动合同
      <span class="hr-profile-page__tab-count">{{ contracts.length }}</span>
    </template>
    <HistorySection
      title="劳动合同"
      description="维护合同期限、签署状态、工作地点与薪资信息"
      add-label="新增合同"
      icon="ri:file-list-3-line"
      :count="contracts.length"
      :readonly="isReadonly"
      @add="contracts.push(createContract())"
    >
      <HistoryCard
        v-for="(item, index) in contracts"
        :key="item.id || index"
        :title="item.contractNo || `合同 ${index + 1}`"
        :subtitle="displayDict('hrContractStatus', item.contractStatus)"
        :readonly="isReadonly"
        @remove="contracts.splice(index, 1)"
      >
        <ElForm label-position="top" class="hr-profile-page__record-form" :disabled="isReadonly">
          <ElFormItem
            label="合同编号"
            required
            :error="fieldError(index, 'contractNo')"
            :data-validation-key="fieldKey(index, 'contractNo')"
          >
            <ElInput v-model="item.contractNo" maxlength="60" />
          </ElFormItem>
          <ElFormItem
            label="合同类型"
            required
            :error="fieldError(index, 'contractType')"
            :data-validation-key="fieldKey(index, 'contractType')"
          >
            <ElSelect v-model="item.contractType">
              <ElOption
                v-for="option in dict('hrContractType')"
                :key="String(option.value)"
                :label="option.label"
                :value="option.value"
              />
            </ElSelect>
          </ElFormItem>
          <ElFormItem
            label="合同状态"
            required
            :error="fieldError(index, 'contractStatus')"
            :data-validation-key="fieldKey(index, 'contractStatus')"
          >
            <ElSelect v-model="item.contractStatus">
              <ElOption
                v-for="option in dict('hrContractStatus')"
                :key="String(option.value)"
                :label="option.label"
                :value="option.value"
              />
            </ElSelect>
          </ElFormItem>
          <ElFormItem label="签署日期">
            <ElDatePicker v-model="item.signDate" type="date" value-format="YYYY-MM-DD" />
          </ElFormItem>
          <ElFormItem
            label="开始日期"
            required
            :error="fieldError(index, 'startDate')"
            :data-validation-key="fieldKey(index, 'startDate')"
          >
            <ElDatePicker v-model="item.startDate" type="date" value-format="YYYY-MM-DD" />
          </ElFormItem>
          <ElFormItem
            label="结束日期"
            :error="fieldError(index, 'endDate')"
            :data-validation-key="fieldKey(index, 'endDate')"
          >
            <ElDatePicker v-model="item.endDate" type="date" value-format="YYYY-MM-DD" />
          </ElFormItem>
          <ElFormItem label="试用期结束">
            <ElDatePicker v-model="item.probationEndDate" type="date" value-format="YYYY-MM-DD" />
          </ElFormItem>
          <ElFormItem label="工作地点">
            <ElInput v-model="item.workLocation" maxlength="120" />
          </ElFormItem>
          <ElFormItem label="合同备注" class="is-wide">
            <ElInput
              v-model="item.remark"
              type="textarea"
              :rows="2"
              maxlength="300"
              show-word-limit
            />
          </ElFormItem>
        </ElForm>
        <ElForm
          v-if="canViewCompensationDetails"
          label-position="top"
          class="hr-profile-page__compensation-form"
          :disabled="!canEditCompensationDetails"
        >
          <ElFormItem label="月薪">
            <ElInputNumber
              v-if="canEditCompensationDetails"
              :model-value="editableAmount(item.monthlySalary)"
              :min="0"
              :precision="2"
              :controls="false"
              @update:model-value="item.monthlySalary = $event"
            />
            <ElInput v-else :model-value="formatSensitiveNumber(item.monthlySalary)" disabled />
          </ElFormItem>
        </ElForm>
      </HistoryCard>
    </HistorySection>
  </ElTabPane>
</template>

<script setup lang="ts">
  import HistoryCard from './history-card.vue'
  import HistorySection from './history-section.vue'
  import { formatSensitiveNumber } from '@/utils/field-permission'

  interface DictOption {
    label?: string
    value: string
  }

  const props = defineProps<{
    isReadonly: boolean
    canViewCompensationDetails: boolean
    canEditCompensationDetails: boolean
    dict: (code: string) => DictOption[]
    displayDict: (code: string, value?: string | null) => string
    validationErrors: Record<string, string>
  }>()
  const contracts = defineModel<Api.Hr.EmployeeContract[]>({ required: true })

  const fieldKey = (index: number, field: string): string => `contracts.${index}.${field}`
  const fieldError = (index: number, field: string): string =>
    props.validationErrors[fieldKey(index, field)] ?? ''
  const editableAmount = (value: Api.Hr.ProtectedAmount | undefined): number | null => {
    const numericValue = Number(value)
    return value === null || value === undefined || !Number.isFinite(numericValue)
      ? null
      : numericValue
  }
  const createContract = (): Api.Hr.EmployeeContract => ({
    contractNo: '',
    contractType: 'fixed_term',
    contractStatus: 'active',
    signDate: null,
    startDate: '',
    endDate: null,
    probationEndDate: null,
    workLocation: '',
    monthlySalary: null,
    remark: ''
  })
</script>
