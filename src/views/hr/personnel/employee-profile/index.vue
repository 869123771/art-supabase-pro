<template>
  <ArtPageShell
    class="hr-profile-page"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    full-height
    @retry="initializePage"
  >
    <ArtPageHeader
      :title="isEdit ? '编辑员工档案' : '新增员工档案'"
      :subtitle="pageSubtitle"
      show-back
      @back="goBack"
    >
      <template #actions>
        <ElTag v-if="form.employeeNo" type="primary" effect="plain" round>
          {{ form.employeeNo }}
        </ElTag>
        <ArtDictDisplay
          v-if="isEdit"
          dict-code="hrEmploymentStatus"
          :value="form.employmentStatus"
          display="tag"
        />
      </template>
    </ArtPageHeader>

    <section class="hr-profile-page__summary art-card-xs">
      <div class="hr-profile-page__avatar">
        <ArtUploadImage v-model="form.avatarUrl" title="上传头像" :size="104" :limit="1" />
      </div>
      <div class="hr-profile-page__summary-copy">
        <span>EMPLOYEE PROFILE</span>
        <strong>{{ form.employeeName || '待录入员工姓名' }}</strong>
        <p>{{ form.jobTitle || '维护员工身份、任职、合同与成长履历' }}</p>
      </div>
      <div class="hr-profile-page__completion">
        <small>档案完整度</small>
        <strong>{{ profileCompletion }}%</strong>
        <ElProgress :percentage="profileCompletion" :show-text="false" />
      </div>
    </section>

    <ElAlert
      v-if="accessNotice"
      class="hr-profile-page__access-notice"
      type="info"
      :closable="false"
      show-icon
      :title="accessNotice"
    />

    <ElTabs v-model="page.activeTab" class="hr-profile-page__tabs art-card-xs">
      <ElTabPane label="基础信息" name="basic">
        <ArtForm
          ref="basicFormRef"
          v-model="form"
          :items="basicItems"
          :rules="basicRules"
          :span="formSpan"
          :gutter="20"
          label-width="112px"
          :show-reset="false"
          :show-submit="false"
          :validate-on-rule-change="false"
        />
      </ElTabPane>

      <EmployeeContractsTab
        v-if="canViewCareerRecords && !form.historiesMasked"
        v-model="form.contracts"
        :is-readonly="!canEditCareerRecords"
        :can-view-compensation-details="canViewCompensationDetails"
        :can-edit-compensation-details="canEditCompensationDetails"
        :dict="dict"
        :display-dict="displayDict"
        :validation-errors="historyValidationErrors"
      />

      <ElTabPane v-if="canViewCareerRecords && !form.historiesMasked" name="educations">
        <template #label
          >教育背景
          <span class="hr-profile-page__tab-count">{{ form.educations.length }}</span></template
        >
        <HistorySection
          title="教育背景"
          description="维护学历、学位、学校与证书信息"
          add-label="新增教育经历"
          icon="ri:graduation-cap-line"
          :count="form.educations.length"
          :readonly="!canEditCareerRecords"
          @add="form.educations.push(createEducation())"
        >
          <HistoryCard
            v-for="(item, index) in form.educations"
            :key="item.id || index"
            :title="item.schoolName || `教育经历 ${index + 1}`"
            :subtitle="displayDict('hrEducationLevel', item.educationLevel)"
            :readonly="!canEditCareerRecords"
            @remove="form.educations.splice(index, 1)"
          >
            <ElForm
              label-position="top"
              class="hr-profile-page__record-form"
              :disabled="!canEditCareerRecords"
            >
              <ElFormItem
                label="学校名称"
                required
                :error="historyFieldError('educations', index, 'schoolName')"
                :data-validation-key="historyFieldKey('educations', index, 'schoolName')"
                ><ElInput v-model="item.schoolName" maxlength="120"
              /></ElFormItem>
              <ElFormItem label="专业"
                ><ElInput v-model="item.majorName" maxlength="100"
              /></ElFormItem>
              <ElFormItem
                label="学历"
                required
                :error="historyFieldError('educations', index, 'educationLevel')"
                :data-validation-key="historyFieldKey('educations', index, 'educationLevel')"
                ><ElSelect v-model="item.educationLevel"
                  ><ElOption
                    v-for="option in dict('hrEducationLevel')"
                    :key="option.value"
                    :label="option.label"
                    :value="option.value" /></ElSelect
              ></ElFormItem>
              <ElFormItem label="学位"
                ><ElSelect v-model="item.degree" clearable
                  ><ElOption
                    v-for="option in dict('hrDegree')"
                    :key="option.value"
                    :label="option.label"
                    :value="option.value" /></ElSelect
              ></ElFormItem>
              <ElFormItem label="开始日期"
                ><ElDatePicker v-model="item.startDate" type="date" value-format="YYYY-MM-DD"
              /></ElFormItem>
              <ElFormItem
                label="结束日期"
                :error="historyFieldError('educations', index, 'endDate')"
                :data-validation-key="historyFieldKey('educations', index, 'endDate')"
                ><ElDatePicker v-model="item.endDate" type="date" value-format="YYYY-MM-DD"
              /></ElFormItem>
              <ElFormItem label="学习形式"
                ><ElRadioGroup v-model="item.fullTime"
                  ><ElRadioButton :value="true">全日制</ElRadioButton
                  ><ElRadioButton :value="false">非全日制</ElRadioButton></ElRadioGroup
                ></ElFormItem
              >
              <ElFormItem label="证书编号"
                ><ElInput v-model="item.certificateNo" maxlength="80"
              /></ElFormItem>
              <ElFormItem label="备注" class="is-wide"
                ><ElInput
                  v-model="item.remark"
                  type="textarea"
                  :rows="2"
                  maxlength="300"
                  show-word-limit
              /></ElFormItem>
            </ElForm>
          </HistoryCard>
        </HistorySection>
      </ElTabPane>

      <ElTabPane v-if="canViewCareerRecords && !form.historiesMasked" name="workExperiences">
        <template #label
          >工作经历
          <span class="hr-profile-page__tab-count">{{
            form.workExperiences.length
          }}</span></template
        >
        <HistorySection
          title="工作经历"
          description="记录入职前任职公司、岗位职责和证明人"
          add-label="新增工作经历"
          icon="ri:briefcase-4-line"
          :count="form.workExperiences.length"
          :readonly="!canEditCareerRecords"
          @add="form.workExperiences.push(createWorkExperience())"
        >
          <HistoryCard
            v-for="(item, index) in form.workExperiences"
            :key="item.id || index"
            :title="item.companyName || `工作经历 ${index + 1}`"
            :subtitle="item.jobTitle"
            :readonly="!canEditCareerRecords"
            @remove="form.workExperiences.splice(index, 1)"
          >
            <ElForm
              label-position="top"
              class="hr-profile-page__record-form"
              :disabled="!canEditCareerRecords"
            >
              <ElFormItem
                label="公司名称"
                required
                :error="historyFieldError('workExperiences', index, 'companyName')"
                :data-validation-key="historyFieldKey('workExperiences', index, 'companyName')"
                ><ElInput v-model="item.companyName" maxlength="120"
              /></ElFormItem>
              <ElFormItem label="所在部门"
                ><ElInput v-model="item.departmentName" maxlength="80"
              /></ElFormItem>
              <ElFormItem
                label="工作岗位"
                required
                :error="historyFieldError('workExperiences', index, 'jobTitle')"
                :data-validation-key="historyFieldKey('workExperiences', index, 'jobTitle')"
                ><ElInput v-model="item.jobTitle" maxlength="80"
              /></ElFormItem>
              <ElFormItem
                label="开始日期"
                required
                :error="historyFieldError('workExperiences', index, 'startDate')"
                :data-validation-key="historyFieldKey('workExperiences', index, 'startDate')"
                ><ElDatePicker v-model="item.startDate" type="date" value-format="YYYY-MM-DD"
              /></ElFormItem>
              <ElFormItem
                label="结束日期"
                :error="historyFieldError('workExperiences', index, 'endDate')"
                :data-validation-key="historyFieldKey('workExperiences', index, 'endDate')"
                ><ElDatePicker v-model="item.endDate" type="date" value-format="YYYY-MM-DD"
              /></ElFormItem>
              <ElFormItem v-if="canViewContactDetails" label="证明人"
                ><ElInput
                  v-model="item.referenceName"
                  maxlength="50"
                  :disabled="!canEditContactDetails"
              /></ElFormItem>
              <ElFormItem v-if="canViewContactDetails" label="证明人电话"
                ><ElInput
                  v-model="item.referencePhone"
                  maxlength="20"
                  :disabled="!canEditContactDetails"
              /></ElFormItem>
              <ElFormItem label="离职原因"
                ><ElInput v-model="item.leavingReason" maxlength="150"
              /></ElFormItem>
              <ElFormItem label="主要职责" class="is-wide"
                ><ElInput
                  v-model="item.responsibilities"
                  type="textarea"
                  :rows="3"
                  maxlength="500"
                  show-word-limit
              /></ElFormItem>
            </ElForm>
          </HistoryCard>
        </HistorySection>
      </ElTabPane>

      <ElTabPane v-if="canViewCareerRecords && !form.historiesMasked" name="trainings">
        <template #label
          >培训经历
          <span class="hr-profile-page__tab-count">{{ form.trainings.length }}</span></template
        >
        <HistorySection
          title="培训经历"
          description="维护培训项目、结果、证书与费用"
          add-label="新增培训经历"
          icon="ri:presentation-line"
          :count="form.trainings.length"
          :readonly="!canEditCareerRecords"
          @add="form.trainings.push(createTraining())"
        >
          <HistoryCard
            v-for="(item, index) in form.trainings"
            :key="item.id || index"
            :title="item.trainingName || `培训经历 ${index + 1}`"
            :subtitle="displayDict('hrTrainingResult', item.trainingResult)"
            :readonly="!canEditCareerRecords"
            @remove="form.trainings.splice(index, 1)"
          >
            <ElForm
              label-position="top"
              class="hr-profile-page__record-form"
              :disabled="!canEditCareerRecords"
            >
              <ElFormItem
                label="培训名称"
                required
                :error="historyFieldError('trainings', index, 'trainingName')"
                :data-validation-key="historyFieldKey('trainings', index, 'trainingName')"
                ><ElInput v-model="item.trainingName" maxlength="120"
              /></ElFormItem>
              <ElFormItem
                label="培训类型"
                required
                :error="historyFieldError('trainings', index, 'trainingType')"
                :data-validation-key="historyFieldKey('trainings', index, 'trainingType')"
                ><ElSelect v-model="item.trainingType"
                  ><ElOption
                    v-for="option in dict('hrTrainingType')"
                    :key="option.value"
                    :label="option.label"
                    :value="option.value" /></ElSelect
              ></ElFormItem>
              <ElFormItem label="培训机构"
                ><ElInput v-model="item.providerName" maxlength="120"
              /></ElFormItem>
              <ElFormItem
                label="开始日期"
                required
                :error="historyFieldError('trainings', index, 'startDate')"
                :data-validation-key="historyFieldKey('trainings', index, 'startDate')"
                ><ElDatePicker v-model="item.startDate" type="date" value-format="YYYY-MM-DD"
              /></ElFormItem>
              <ElFormItem
                label="结束日期"
                :error="historyFieldError('trainings', index, 'endDate')"
                :data-validation-key="historyFieldKey('trainings', index, 'endDate')"
                ><ElDatePicker v-model="item.endDate" type="date" value-format="YYYY-MM-DD"
              /></ElFormItem>
              <ElFormItem label="培训结果"
                ><ElSelect v-model="item.trainingResult" clearable
                  ><ElOption
                    v-for="option in dict('hrTrainingResult')"
                    :key="option.value"
                    :label="option.label"
                    :value="option.value" /></ElSelect
              ></ElFormItem>
              <ElFormItem label="证书名称"
                ><ElInput v-model="item.certificateName" maxlength="100"
              /></ElFormItem>
              <ElFormItem label="证书编号"
                ><ElInput v-model="item.certificateNo" maxlength="80"
              /></ElFormItem>
              <ElFormItem label="备注" class="is-wide"
                ><ElInput
                  v-model="item.remark"
                  type="textarea"
                  :rows="2"
                  maxlength="300"
                  show-word-limit
              /></ElFormItem>
            </ElForm>
            <ElForm
              v-if="canViewCompensationDetails"
              label-position="top"
              class="hr-profile-page__compensation-form"
              :disabled="!canEditCompensationDetails"
            >
              <ElFormItem label="培训费用">
                <ElInputNumber
                  v-if="canEditCompensationDetails"
                  :model-value="editableAmount(item.cost)"
                  :min="0"
                  :precision="2"
                  :controls="false"
                  @update:model-value="item.cost = $event"
                />
                <ElInput v-else :model-value="formatSensitiveNumber(item.cost)" disabled />
              </ElFormItem>
            </ElForm>
          </HistoryCard>
        </HistorySection>
      </ElTabPane>

      <ElTabPane v-if="canViewCareerRecords && !form.historiesMasked" name="rewards">
        <template #label
          >奖惩经历
          <span class="hr-profile-page__tab-count">{{ form.rewards.length }}</span></template
        >
        <HistorySection
          title="奖惩经历"
          description="统一记录奖励、处分及其认定级别"
          add-label="新增奖惩记录"
          icon="ri:award-line"
          :count="form.rewards.length"
          :readonly="!canEditCareerRecords"
          @add="form.rewards.push(createReward())"
        >
          <HistoryCard
            v-for="(item, index) in form.rewards"
            :key="item.id || index"
            :title="item.title || `奖惩记录 ${index + 1}`"
            :subtitle="displayDict('hrRewardType', item.recordType)"
            :readonly="!canEditCareerRecords"
            @remove="form.rewards.splice(index, 1)"
          >
            <ElForm
              label-position="top"
              class="hr-profile-page__record-form"
              :disabled="!canEditCareerRecords"
            >
              <ElFormItem
                label="奖惩类型"
                required
                :error="historyFieldError('rewards', index, 'recordType')"
                :data-validation-key="historyFieldKey('rewards', index, 'recordType')"
                ><ElSelect v-model="item.recordType"
                  ><ElOption
                    v-for="option in dict('hrRewardType')"
                    :key="option.value"
                    :label="option.label"
                    :value="option.value" /></ElSelect
              ></ElFormItem>
              <ElFormItem label="奖惩级别"
                ><ElSelect v-model="item.recordLevel" clearable
                  ><ElOption
                    v-for="option in dict('hrRewardLevel')"
                    :key="option.value"
                    :label="option.label"
                    :value="option.value" /></ElSelect
              ></ElFormItem>
              <ElFormItem
                label="奖惩标题"
                required
                :error="historyFieldError('rewards', index, 'title')"
                :data-validation-key="historyFieldKey('rewards', index, 'title')"
                ><ElInput v-model="item.title" maxlength="120"
              /></ElFormItem>
              <ElFormItem
                label="发生日期"
                required
                :error="historyFieldError('rewards', index, 'recordDate')"
                :data-validation-key="historyFieldKey('rewards', index, 'recordDate')"
                ><ElDatePicker v-model="item.recordDate" type="date" value-format="YYYY-MM-DD"
              /></ElFormItem>
              <ElFormItem label="颁发/认定机构"
                ><ElInput v-model="item.issuingOrganization" maxlength="120"
              /></ElFormItem>
              <ElFormItem label="详细说明" class="is-wide"
                ><ElInput
                  v-model="item.description"
                  type="textarea"
                  :rows="3"
                  maxlength="500"
                  show-word-limit
              /></ElFormItem>
            </ElForm>
            <ElForm
              v-if="canViewCompensationDetails"
              label-position="top"
              class="hr-profile-page__compensation-form"
              :disabled="!canEditCompensationDetails"
            >
              <ElFormItem label="金额">
                <ElInputNumber
                  v-if="canEditCompensationDetails"
                  :model-value="editableAmount(item.amount)"
                  :min="0"
                  :precision="2"
                  :controls="false"
                  @update:model-value="item.amount = $event"
                />
                <ElInput v-else :model-value="formatSensitiveNumber(item.amount)" disabled />
              </ElFormItem>
            </ElForm>
          </HistoryCard>
        </HistorySection>
      </ElTabPane>
      <ElTabPane v-if="form.historiesMasked" label="履历概览" name="historyOverview">
        <div class="hr-profile-page__history-mask">
          <ElAlert
            title="履历内容已按字段权限脱敏，仅展示记录数量，当前页面不会提交履历变更。"
            type="warning"
            :closable="false"
            show-icon
          />
          <div class="hr-profile-page__history-counts">
            <div v-for="item in historyCountItems" :key="item.key">
              <strong>{{ item.value }}</strong
              ><span>{{ item.label }}</span>
            </div>
          </div>
        </div>
      </ElTabPane>
    </ElTabs>

    <ArtStickyActionBar class="hr-profile-page__footer">
      <template #summary>
        <span class="hr-profile-page__save-hint">
          带 <b>*</b> 的信息为必填项；司机岗位保存时将同时创建司机档案。
        </span>
      </template>
      <ElButton :disabled="page.saving" @click="goBack">取消</ElButton>
      <ElButton v-auth="savePermission" type="primary" :loading="page.saving" @click="handleSave">
        保存员工档案
      </ElButton>
    </ArtStickyActionBar>
  </ArtPageShell>
</template>

<script setup lang="ts">
  import { omit } from 'lodash-es'
  import { useMediaQuery } from '@vueuse/core'
  import type { FormRules } from 'element-plus'
  import { ElMessage } from 'element-plus'
  import ArtForm, {
    type FormItem,
    type FormItemOption
  } from '@/components/core/forms/art-form/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import EmployeeContractsTab from './modules/employee-contracts-tab.vue'
  import HistorySection from './modules/history-section.vue'
  import HistoryCard from './modules/history-card.vue'
  import {
    fetchEmployeeDriverCarrierOptions,
    fetchEmployeeProfile,
    fetchPositionOptions,
    saveEmployeeProfile
  } from '@/api/hr'
  import { fetchGetEnableOrganizationTree, fetchGetEnableTenantList } from '@/api/system-manage'
  import { useUserStore } from '@/store/modules/user'
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'
  import {
    canEditField,
    canViewField,
    formatSensitiveNumber,
    getFieldAccess
  } from '@/utils/field-permission'

  defineOptions({ name: 'HrEmployeeProfile' })

  type Employee = Api.Hr.Employee
  type EmployeeProfile = Api.Hr.EmployeeProfile
  interface EmployeeProfileForm extends EmployeeProfile {
    driverCarrierId: string
    driverType: Api.Tms.BasicData.Driver['driverType']
    driverLicenseType: string
    driverLicenseExpireDate: string
  }
  type HistoryTabName = 'contracts' | 'educations' | 'workExperiences' | 'trainings' | 'rewards'
  type TabName = 'basic' | 'historyOverview' | HistoryTabName

  interface ValidationTarget {
    tab: TabName
    message: string
    basicField?: string
    historyKey?: string
  }

  interface FormExpose {
    validate: () => Promise<boolean | void>
    clearValidate: () => void
    scrollToField: (field: string) => void
    reloadOptions: (key?: string) => Promise<void>
  }

  const route = useRoute()
  const router = useRouter()
  const userStore = useUserStore()
  const { getDictMap, getUserInfo, isPlatformSuper } = storeToRefs(userStore)
  const savePermission = computed(() => (route.params.id ? 'Hr:Employee:Edit' : 'Hr:Employee:Add'))
  const basicFormRef = ref<FormExpose>()
  const tenantFormOptions = ref<FormItemOption[]>([])
  const organizationFormOptions = ref<FormItemOption[]>([])
  const positionOptions = ref<Api.Hr.PositionOption[]>([])
  const driverCarrierOptions = ref<FormItemOption[]>([])
  const employeeNumber = useDocumentNumberRule('hr.employee')
  const historyValidationErrors = reactive<Record<string, string>>({})
  const isDesktop = useMediaQuery('(min-width: 1200px)')
  const isTablet = useMediaQuery('(min-width: 720px)')
  const formSpan = computed(() => (isDesktop.value ? 8 : isTablet.value ? 12 : 24))
  const isEdit = computed(() => typeof route.params.id === 'string' && Boolean(route.params.id))
  const pageSubtitle = computed(() =>
    isEdit.value
      ? '分模块维护基础身份、劳动合同、教育、工作、培训及奖惩记录'
      : '创建完整员工档案，保存后即可在用户新增时选取并开通账号'
  )
  const page = reactive<{
    loading: boolean
    saving: boolean
    activeTab: TabName
    error: Error | null
  }>({
    loading: false,
    saving: false,
    activeTab: 'basic',
    error: null
  })

  const createEmployee = (): Employee => ({
    tenantId: isPlatformSuper.value ? undefined : getUserInfo.value.tenantId,
    organizationId: null,
    positionId: null,
    employeeNo: '',
    employeeName: '',
    avatarUrl: null,
    jobTitle: '',
    employmentStatus: 'active',
    employmentType: 'full_time',
    gender: null,
    birthDate: null,
    phone: '',
    email: '',
    idCardNo: '',
    ethnicity: null,
    educationLevel: null,
    schoolName: '',
    majorName: '',
    maritalStatus: null,
    politicalStatus: null,
    nativePlace: '',
    homeAddress: '',
    hireDate: null,
    probationEndDate: null,
    leaveDate: null,
    contractStartDate: null,
    contractEndDate: null,
    emergencyContactName: '',
    emergencyContactRelation: null,
    emergencyContactPhone: '',
    remark: ''
  })
  const createEducation = (): Api.Hr.EmployeeEducation => ({
    schoolName: '',
    majorName: '',
    educationLevel: 'bachelor',
    degree: null,
    startDate: null,
    endDate: null,
    fullTime: true,
    certificateNo: '',
    remark: ''
  })
  const createWorkExperience = (): Api.Hr.EmployeeWorkExperience => ({
    companyName: '',
    departmentName: '',
    jobTitle: '',
    startDate: '',
    endDate: null,
    responsibilities: '',
    leavingReason: '',
    referenceName: '',
    referencePhone: ''
  })
  const createTraining = (): Api.Hr.EmployeeTraining => ({
    trainingName: '',
    trainingType: 'internal',
    providerName: '',
    startDate: '',
    endDate: null,
    trainingResult: null,
    certificateName: '',
    certificateNo: '',
    cost: null,
    remark: ''
  })
  const createReward = (): Api.Hr.EmployeeReward => ({
    recordType: 'reward',
    recordLevel: null,
    title: '',
    recordDate: '',
    issuingOrganization: '',
    amount: null,
    description: ''
  })
  const createProfile = (): EmployeeProfileForm => ({
    ...createEmployee(),
    driverCarrierId: '',
    driverType: 'primary',
    driverLicenseType: '',
    driverLicenseExpireDate: '',
    contracts: [],
    educations: [],
    workExperiences: [],
    trainings: [],
    rewards: []
  })
  const form = reactive<EmployeeProfileForm>(createProfile())
  const fieldAccessFallback = computed<Api.Common.FieldAccessLevel>(() =>
    isEdit.value ? 'hidden' : 'edit'
  )
  const fieldLevel = (field: Api.Hr.EmployeeFieldKey): Api.Common.FieldAccessLevel =>
    getFieldAccess(form.fieldAccess, field, fieldAccessFallback.value)
  const canViewContactDetails = computed(() =>
    canViewField(form.fieldAccess, 'contactDetails', fieldAccessFallback.value)
  )
  const canEditContactDetails = computed(() =>
    canEditField(form.fieldAccess, 'contactDetails', fieldAccessFallback.value)
  )
  const canEditIdentityDetails = computed(() =>
    canEditField(form.fieldAccess, 'identityDetails', fieldAccessFallback.value)
  )
  const canViewIdentityDetails = computed(() =>
    canViewField(form.fieldAccess, 'identityDetails', fieldAccessFallback.value)
  )
  const canViewCompensationDetails = computed(() =>
    canViewField(form.fieldAccess, 'compensationDetails', fieldAccessFallback.value)
  )
  const canEditCompensationDetails = computed(() =>
    canEditField(form.fieldAccess, 'compensationDetails', fieldAccessFallback.value)
  )
  const canViewCareerRecords = computed(() =>
    canViewField(form.fieldAccess, 'careerRecords', fieldAccessFallback.value)
  )
  const canEditCareerRecords = computed(() =>
    canEditField(form.fieldAccess, 'careerRecords', fieldAccessFallback.value)
  )
  const accessNotice = computed(() => {
    if (!isEdit.value || form.isRecordOwner) return ''
    const readonlyGroups = (
      ['contactDetails', 'identityDetails', 'compensationDetails', 'careerRecords'] as const
    ).filter((field) => fieldLevel(field) !== 'edit').length
    return readonlyGroups
      ? `${readonlyGroups} 组敏感信息受字段权限限制；隐藏字段不会提交，只读字段不会被修改。`
      : ''
  })
  const editableAmount = (value: Api.Hr.ProtectedAmount | undefined): number | null => {
    const numericValue = Number(value)
    return value === null || value === undefined || !Number.isFinite(numericValue)
      ? null
      : numericValue
  }
  const historyCountItems = computed(() => [
    { key: 'contracts', label: '劳动合同', value: form.historyCounts?.contracts ?? 0 },
    { key: 'educations', label: '教育背景', value: form.historyCounts?.educations ?? 0 },
    {
      key: 'workExperiences',
      label: '工作经历',
      value: form.historyCounts?.workExperiences ?? 0
    },
    { key: 'trainings', label: '培训经历', value: form.historyCounts?.trainings ?? 0 },
    { key: 'rewards', label: '奖惩经历', value: form.historyCounts?.rewards ?? 0 }
  ])

  const dict = (code: string) => getDictMap.value[code] ?? []
  const displayDict = (code: string, value?: string | null): string =>
    dict(code).find((item) => item.value === value)?.label ?? value ?? '待完善'
  const selectedPosition = computed(() =>
    positionOptions.value.find((item) => item.id === form.positionId)
  )
  const isDriverEmployeeCreate = computed(
    () => !isEdit.value && selectedPosition.value?.positionKind === 'driver'
  )
  const positionFormOptions = computed<FormItemOption[]>(() =>
    positionOptions.value.map((position) => ({
      label: `${position.positionName}（${position.positionCode}）`,
      value: position.id,
      disabled:
        isEdit.value && position.positionKind === 'driver' && position.id !== form.positionId
    }))
  )

  const requiredBaseFields = computed(() => [
    form.employeeNo,
    form.employeeName,
    form.organizationId,
    form.positionId,
    form.employmentStatus,
    form.employmentType
  ])
  const optionalBaseFields = computed(() => [
    form.hireDate,
    ...(canViewIdentityDetails.value
      ? [
          form.gender,
          form.birthDate,
          form.idCardNo,
          form.ethnicity,
          form.educationLevel,
          form.schoolName,
          form.majorName,
          form.maritalStatus,
          form.politicalStatus,
          form.nativePlace
        ]
      : []),
    ...(canViewContactDetails.value
      ? [
          form.phone,
          form.email,
          form.homeAddress,
          form.emergencyContactName,
          form.emergencyContactPhone
        ]
      : [])
  ])
  const profileCompletion = computed(() => {
    const all = [...requiredBaseFields.value, ...optionalBaseFields.value]
    const filled = all.filter(
      (value) => value !== null && value !== undefined && String(value).trim()
    ).length
    const historyBonus =
      canViewCareerRecords.value && !form.historiesMasked
        ? [
            form.contracts,
            form.educations,
            form.workExperiences,
            form.trainings,
            form.rewards
          ].filter((items) => items.length).length
        : 0
    const historyWeight = canViewCareerRecords.value && !form.historiesMasked ? 10 : 0
    return Math.min(
      100,
      Math.round(((filled + historyBonus * 2) / Math.max(all.length + historyWeight, 1)) * 100)
    )
  })

  const dateProps = {
    type: 'date',
    valueFormat: 'YYYY-MM-DD',
    class: '!w-full',
    placeholder: '请选择日期'
  }
  const mapOrganizationOptions = (nodes: object[]): FormItemOption[] =>
    nodes.map((node) => {
      const id = String(Reflect.get(node, 'id') ?? '')
      const name = String(Reflect.get(node, 'organizationName') ?? '')
      const code = String(Reflect.get(node, 'organizationCode') ?? '')
      const children = Reflect.get(node, 'children')
      return {
        ...node,
        label: code ? `${name}（${code}）` : name,
        value: id,
        children: Array.isArray(children) ? mapOrganizationOptions(children) : undefined
      }
    })

  const loadOrganizationOptions = async (): Promise<void> => {
    if (!form.tenantId) {
      organizationFormOptions.value = []
      return
    }
    const response = await fetchGetEnableOrganizationTree({ tenantId: form.tenantId })
    organizationFormOptions.value = mapOrganizationOptions(response.data ?? [])
  }

  const loadPositionOptions = async (): Promise<void> => {
    if (!form.tenantId) {
      positionOptions.value = []
      return
    }
    const response = await fetchPositionOptions({ tenantId: form.tenantId })
    positionOptions.value = response.data ?? []
  }

  const loadDriverCarrierOptions = async (): Promise<void> => {
    if (!form.tenantId || !isDriverEmployeeCreate.value) {
      driverCarrierOptions.value = []
      return
    }
    const response = await fetchEmployeeDriverCarrierOptions(form.tenantId)
    driverCarrierOptions.value = (response.data ?? []).map((carrier) => ({
      label: carrier.carrierCode
        ? `${carrier.companyName}（${carrier.carrierCode}）`
        : carrier.companyName,
      value: carrier.id
    }))
  }

  const handleTenantChange = (): void => {
    form.organizationId = null
    form.positionId = null
    form.driverCarrierId = ''
    void loadOrganizationOptions()
    void loadPositionOptions()
  }

  const basicRules = computed<FormRules<EmployeeProfileForm>>(() => ({
    tenantId: isPlatformSuper.value
      ? [{ required: true, message: '请选择所属租户', trigger: 'change' }]
      : [],
    organizationId: [{ required: true, message: '请选择所属组织', trigger: 'change' }],
    positionId: [{ required: true, message: '请选择工作岗位', trigger: 'change' }],
    employeeNo: [
      ...(isEdit.value || employeeNumber.manualRequired(false)
        ? [{ required: true, message: '请输入员工工号', trigger: 'blur' as const }]
        : []),
      {
        pattern: /^$|^[A-Za-z0-9][A-Za-z0-9_-]{1,31}$/,
        message: '工号应为 2-32 位字母、数字、下划线或短横线',
        trigger: 'blur'
      }
    ],
    employeeName: [
      { required: true, message: '请输入员工姓名', trigger: 'blur' },
      { min: 2, max: 50, message: '姓名长度应为 2-50 个字符', trigger: 'blur' }
    ],
    employmentStatus: [{ required: true, message: '请选择任职状态', trigger: 'change' }],
    employmentType: [{ required: true, message: '请选择用工类型', trigger: 'change' }],
    phone: canEditContactDetails.value
      ? [
          ...(isDriverEmployeeCreate.value
            ? [{ required: true, message: '司机岗位必须填写手机号码', trigger: 'blur' as const }]
            : []),
          { pattern: /^$|^1[3-9]\d{9}$/, message: '请输入正确的手机号码', trigger: 'blur' }
        ]
      : [],
    gender:
      isDriverEmployeeCreate.value && canEditIdentityDetails.value
        ? [{ required: true, message: '司机岗位必须选择性别', trigger: 'change' }]
        : [],
    idCardNo:
      isDriverEmployeeCreate.value && canEditIdentityDetails.value
        ? [
            { required: true, message: '司机岗位必须填写身份证号', trigger: 'blur' },
            {
              pattern: /(^\d{15}$)|(^\d{17}[\dXx]$)/,
              message: '请输入正确的身份证号',
              trigger: 'blur'
            }
          ]
        : [],
    driverCarrierId: isDriverEmployeeCreate.value
      ? [{ required: true, message: '请选择所属承运商', trigger: 'change' }]
      : [],
    driverType: isDriverEmployeeCreate.value
      ? [{ required: true, message: '请选择司机类型', trigger: 'change' }]
      : [],
    driverLicenseType: isDriverEmployeeCreate.value
      ? [{ required: true, message: '请选择驾照类型', trigger: 'change' }]
      : [],
    driverLicenseExpireDate: isDriverEmployeeCreate.value
      ? [{ required: true, message: '请选择驾照有效期', trigger: 'change' }]
      : [],
    email: canEditContactDetails.value
      ? [
          {
            pattern: /^$|^[^\s@]+@[^\s@]+\.[^\s@]+$/,
            message: '请输入正确的邮箱地址',
            trigger: 'blur'
          }
        ]
      : [],
    emergencyContactPhone: canEditContactDetails.value
      ? [{ pattern: /^$|^1[3-9]\d{9}$/, message: '请输入正确的联系电话', trigger: 'blur' }]
      : []
  }))

  const identityBasicKeys = new Set([
    'identitySection',
    'gender',
    'birthDate',
    'idCardNo',
    'ethnicity',
    'maritalStatus',
    'politicalStatus',
    'nativePlace',
    'educationLevel',
    'schoolName',
    'majorName'
  ])
  const contactBasicKeys = new Set([
    'contactSection',
    'phone',
    'email',
    'homeAddress',
    'emergencyContactName',
    'emergencyContactRelation',
    'emergencyContactPhone'
  ])
  const basicItems = computed<FormItem[]>(() => {
    const items: FormItem[] = [
      { label: '组织与任职', key: 'organizationSection', type: 'divider', span: 24 },
      {
        label: '所属租户',
        key: 'tenantId',
        type: 'select',
        span: 24,
        hidden: !isPlatformSuper.value,
        options: tenantFormOptions.value,
        props: {
          filterable: true,
          disabled: isEdit.value,
          placeholder: '请选择所属租户',
          onChange: handleTenantChange
        }
      },
      {
        label: '所属组织',
        key: 'organizationId',
        type: 'treeSelect',
        span: isDesktop.value ? 16 : 24,
        options: organizationFormOptions.value,
        props: {
          disabled: !form.tenantId,
          clearable: true,
          checkStrictly: true,
          defaultExpandAll: true,
          filterable: true,
          placeholder: form.tenantId ? '请选择所属组织' : '请先选择租户'
        }
      },
      {
        label: '员工工号',
        key: 'employeeNo',
        type: 'input',
        props: {
          maxlength: 32,
          ...employeeNumber.inputProps(isEdit.value, '请输入员工工号', true)
        },
        description: employeeNumber.description.value
      },
      {
        label: '员工姓名',
        key: 'employeeName',
        type: 'input',
        props: { maxlength: 50, placeholder: '请输入姓名' }
      },
      {
        label: '工作岗位',
        key: 'positionId',
        type: 'select',
        options: positionFormOptions.value,
        props: {
          filterable: true,
          clearable: true,
          placeholder: form.tenantId ? '请选择工作岗位' : '请先选择租户'
        },
        description: '岗位由 HR「岗位管理」统一维护；司机岗位会触发司机档案联动。'
      },
      {
        label: '任职状态',
        key: 'employmentStatus',
        type: 'select',
        props: { options: dict('hrEmploymentStatus') }
      },
      {
        label: '用工类型',
        key: 'employmentType',
        type: 'select',
        props: { options: dict('hrEmploymentType') }
      },
      {
        label: '司机任职资料',
        key: 'driverSection',
        type: 'divider',
        span: 24,
        hidden: !isDriverEmployeeCreate.value
      },
      {
        label: '所属承运商',
        key: 'driverCarrierId',
        type: 'select',
        span: isDesktop.value ? 16 : 24,
        hidden: !isDriverEmployeeCreate.value,
        options: driverCarrierOptions.value,
        props: { filterable: true, clearable: true, placeholder: '请选择同租户承运商' }
      },
      {
        label: '司机类型',
        key: 'driverType',
        type: 'radioGroup',
        hidden: !isDriverEmployeeCreate.value,
        props: { options: dict('tmsDriverType') }
      },
      {
        label: '驾照类型',
        key: 'driverLicenseType',
        type: 'select',
        hidden: !isDriverEmployeeCreate.value,
        props: { options: dict('tmsDriverLicenseType'), clearable: true }
      },
      {
        label: '驾照有效期',
        key: 'driverLicenseExpireDate',
        type: 'date',
        hidden: !isDriverEmployeeCreate.value,
        props: dateProps
      },
      { label: '个人身份', key: 'identitySection', type: 'divider', span: 24 },
      {
        label: '性别',
        key: 'gender',
        type: 'select',
        props: { options: dict('sex'), clearable: true }
      },
      { label: '出生日期', key: 'birthDate', type: 'date', props: dateProps },
      { label: '身份证号', key: 'idCardNo', type: 'input', props: { maxlength: 18 } },
      {
        label: '民族',
        key: 'ethnicity',
        type: 'select',
        props: { options: dict('hrEthnicity'), clearable: true }
      },
      {
        label: '婚姻状况',
        key: 'maritalStatus',
        type: 'select',
        props: { options: dict('hrMaritalStatus'), clearable: true }
      },
      {
        label: '政治面貌',
        key: 'politicalStatus',
        type: 'select',
        props: { options: dict('hrPoliticalStatus'), clearable: true }
      },
      { label: '籍贯', key: 'nativePlace', type: 'input', props: { maxlength: 100 } },
      {
        label: '最高学历',
        key: 'educationLevel',
        type: 'select',
        props: { options: dict('hrEducationLevel'), clearable: true }
      },
      { label: '毕业院校', key: 'schoolName', type: 'input', props: { maxlength: 120 } },
      { label: '专业', key: 'majorName', type: 'input', props: { maxlength: 100 } },
      { label: '任职时间', key: 'employmentSection', type: 'divider', span: 24 },
      { label: '入职日期', key: 'hireDate', type: 'date', props: dateProps },
      { label: '转正日期', key: 'probationEndDate', type: 'date', props: dateProps },
      { label: '离职日期', key: 'leaveDate', type: 'date', props: dateProps },
      { label: '合同开始', key: 'contractStartDate', type: 'date', props: dateProps },
      { label: '合同结束', key: 'contractEndDate', type: 'date', props: dateProps },
      { label: '联系信息', key: 'contactSection', type: 'divider', span: 24 },
      { label: '手机号码', key: 'phone', type: 'input', props: { maxlength: 11 } },
      { label: '电子邮箱', key: 'email', type: 'input', props: { maxlength: 120 } },
      {
        label: '家庭住址',
        key: 'homeAddress',
        type: 'input',
        span: isDesktop.value ? 16 : 24,
        props: { maxlength: 200 }
      },
      { label: '紧急联系人', key: 'emergencyContactName', type: 'input', props: { maxlength: 50 } },
      {
        label: '联系人关系',
        key: 'emergencyContactRelation',
        type: 'select',
        props: { options: dict('hrEmergencyRelation'), clearable: true }
      },
      { label: '联系电话', key: 'emergencyContactPhone', type: 'input', props: { maxlength: 11 } },
      {
        label: '备注',
        key: 'remark',
        type: 'input',
        span: 24,
        props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
      }
    ]

    return items.map((item) => {
      const key = String(item.key)
      const permissionField: Api.Hr.EmployeeFieldKey | undefined = identityBasicKeys.has(key)
        ? 'identityDetails'
        : contactBasicKeys.has(key)
          ? 'contactDetails'
          : key === 'remark'
            ? 'careerRecords'
            : undefined
      if (!permissionField) return item

      const access = fieldLevel(permissionField)
      if (access === 'hidden') return { ...item, hidden: true }

      const isMasked = access === 'masked'
      return {
        ...item,
        type: isMasked && item.type !== 'divider' ? 'input' : item.type,
        options: isMasked ? undefined : item.options,
        props: {
          ...(item.props ?? {}),
          disabled: access !== 'edit'
        },
        description:
          access === 'masked'
            ? '该字段已按权限脱敏，无法编辑。'
            : access === 'read'
              ? '当前字段为只读。'
              : item.description
      }
    })
  })

  const ensureDictionaries = async (): Promise<void> => {
    const codes = [
      'sex',
      'hrEmploymentStatus',
      'hrEmploymentType',
      'hrEducationLevel',
      'hrMaritalStatus',
      'hrPoliticalStatus',
      'hrEthnicity',
      'hrEmergencyRelation',
      'hrContractType',
      'hrContractStatus',
      'hrDegree',
      'hrTrainingType',
      'hrTrainingResult',
      'hrRewardType',
      'hrRewardLevel',
      'tmsDriverType',
      'tmsDriverLicenseType'
    ]
    await Promise.all(codes.map((code) => userStore.ensureDictLoaded(code)))
  }

  const replaceProfile = (profile: EmployeeProfile): void => {
    Object.assign(form, createProfile(), structuredClone(profile))
  }

  const initializePage = async (): Promise<void> => {
    page.loading = true
    page.error = null
    try {
      await Promise.all([ensureDictionaries(), employeeNumber.loadRule()])
      if (isPlatformSuper.value) {
        const response = await fetchGetEnableTenantList()
        tenantFormOptions.value = (response.data ?? []).map((tenant) => ({
          label: `${tenant.tenantName}（${tenant.tenantCode}）`,
          value: tenant.id
        }))
      }
      if (isEdit.value) {
        const profile = await fetchEmployeeProfile(String(route.params.id))
        if (!profile) throw new Error('员工档案不存在，或当前账号无权查看')
        replaceProfile(profile)
      }
      await Promise.all([loadOrganizationOptions(), loadPositionOptions()])
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('员工档案加载失败')
    } finally {
      page.loading = false
    }
  }

  const validateDates = (start?: string | null, end?: string | null): boolean =>
    !start || !end || end >= start
  const historyFieldKey = (tab: HistoryTabName, index: number, field: string): string =>
    `${tab}.${index}.${field}`
  const historyFieldError = (tab: HistoryTabName, index: number, field: string): string =>
    historyValidationErrors[historyFieldKey(tab, index, field)] ?? ''
  const clearHistoryValidation = (tab?: HistoryTabName): void => {
    Object.keys(historyValidationErrors).forEach((key) => {
      if (!tab || key.startsWith(`${tab}.`)) delete historyValidationErrors[key]
    })
  }
  const setHistoryValidationError = (
    tab: HistoryTabName,
    index: number,
    field: string,
    message: string,
    firstFailure: { value?: ValidationTarget }
  ): void => {
    const key = historyFieldKey(tab, index, field)
    historyValidationErrors[key] = message
    firstFailure.value ??= { tab, historyKey: key, message }
  }

  const validateHistories = (): ValidationTarget | undefined => {
    clearHistoryValidation()
    const firstFailure: { value?: ValidationTarget } = {}

    form.contracts.forEach((item, index) => {
      if (!item.contractNo.trim())
        setHistoryValidationError('contracts', index, 'contractNo', '请输入合同编号', firstFailure)
      if (!item.contractType)
        setHistoryValidationError(
          'contracts',
          index,
          'contractType',
          '请选择合同类型',
          firstFailure
        )
      if (!item.contractStatus)
        setHistoryValidationError(
          'contracts',
          index,
          'contractStatus',
          '请选择合同状态',
          firstFailure
        )
      if (!item.startDate)
        setHistoryValidationError('contracts', index, 'startDate', '请选择开始日期', firstFailure)
      else if (!validateDates(item.startDate, item.endDate))
        setHistoryValidationError(
          'contracts',
          index,
          'endDate',
          '结束日期不能早于开始日期',
          firstFailure
        )
    })
    form.educations.forEach((item, index) => {
      if (!item.schoolName.trim())
        setHistoryValidationError('educations', index, 'schoolName', '请输入学校名称', firstFailure)
      if (!item.educationLevel)
        setHistoryValidationError('educations', index, 'educationLevel', '请选择学历', firstFailure)
      if (!validateDates(item.startDate, item.endDate))
        setHistoryValidationError(
          'educations',
          index,
          'endDate',
          '结束日期不能早于开始日期',
          firstFailure
        )
    })
    form.workExperiences.forEach((item, index) => {
      if (!item.companyName.trim())
        setHistoryValidationError(
          'workExperiences',
          index,
          'companyName',
          '请输入公司名称',
          firstFailure
        )
      if (!item.jobTitle.trim())
        setHistoryValidationError(
          'workExperiences',
          index,
          'jobTitle',
          '请输入工作岗位',
          firstFailure
        )
      if (!item.startDate)
        setHistoryValidationError(
          'workExperiences',
          index,
          'startDate',
          '请选择开始日期',
          firstFailure
        )
      else if (!validateDates(item.startDate, item.endDate))
        setHistoryValidationError(
          'workExperiences',
          index,
          'endDate',
          '结束日期不能早于开始日期',
          firstFailure
        )
    })
    form.trainings.forEach((item, index) => {
      if (!item.trainingName.trim())
        setHistoryValidationError(
          'trainings',
          index,
          'trainingName',
          '请输入培训名称',
          firstFailure
        )
      if (!item.trainingType)
        setHistoryValidationError(
          'trainings',
          index,
          'trainingType',
          '请选择培训类型',
          firstFailure
        )
      if (!item.startDate)
        setHistoryValidationError('trainings', index, 'startDate', '请选择开始日期', firstFailure)
      else if (!validateDates(item.startDate, item.endDate))
        setHistoryValidationError(
          'trainings',
          index,
          'endDate',
          '结束日期不能早于开始日期',
          firstFailure
        )
    })
    form.rewards.forEach((item, index) => {
      if (!item.recordType)
        setHistoryValidationError('rewards', index, 'recordType', '请选择奖惩类型', firstFailure)
      if (!item.title.trim())
        setHistoryValidationError('rewards', index, 'title', '请输入奖惩标题', firstFailure)
      if (!item.recordDate)
        setHistoryValidationError('rewards', index, 'recordDate', '请选择发生日期', firstFailure)
    })

    return firstFailure.value
  }

  const parseBasicValidationFailure = (error: unknown): ValidationTarget => {
    if (!error || typeof error !== 'object') {
      return { tab: 'basic', message: '请完善基础信息中的必填项' }
    }
    const [field, details] = Object.entries(error)[0] ?? []
    const firstDetail = Array.isArray(details) ? details[0] : details
    const message =
      firstDetail && typeof firstDetail === 'object'
        ? String(Reflect.get(firstDetail, 'message') ?? '请完善基础信息中的必填项')
        : '请完善基础信息中的必填项'
    return { tab: 'basic', basicField: field, message }
  }

  const focusValidationTarget = async (target: ValidationTarget): Promise<void> => {
    page.activeTab = target.tab
    await nextTick()
    if (target.basicField) basicFormRef.value?.scrollToField(target.basicField)
    await nextTick()

    const selector = target.historyKey
      ? `[data-validation-key="${target.historyKey}"]`
      : '.hr-profile-page .el-form-item.is-error'
    const field = document.querySelector<HTMLElement>(selector)
    field?.scrollIntoView({ behavior: 'smooth', block: 'center' })
    window.setTimeout(() => {
      field
        ?.querySelector<HTMLElement>(
          'input:not([disabled]), textarea:not([disabled]), [role="combobox"]:not([aria-disabled="true"])'
        )
        ?.focus({ preventScroll: true })
    }, 320)
  }

  watch(
    () => form.contracts,
    () => clearHistoryValidation('contracts'),
    { deep: true }
  )
  watch(
    () => form.educations,
    () => clearHistoryValidation('educations'),
    { deep: true }
  )
  watch(
    () => form.workExperiences,
    () => clearHistoryValidation('workExperiences'),
    { deep: true }
  )
  watch(
    () => form.trainings,
    () => clearHistoryValidation('trainings'),
    { deep: true }
  )
  watch(
    () => form.rewards,
    () => clearHistoryValidation('rewards'),
    { deep: true }
  )

  const normalizeEmployee = (): Employee => {
    const employee = omit(structuredClone(toRaw(form)), [
      'contracts',
      'educations',
      'workExperiences',
      'trainings',
      'rewards',
      'driverCarrierId',
      'driverType',
      'driverLicenseType',
      'driverLicenseExpireDate',
      'tenant',
      'organization',
      'account',
      'fieldAccess',
      'isRecordOwner',
      'historyCounts',
      'historiesMasked',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime'
    ]) as Employee
    const employeeRecord = employee as Employee & Record<string, unknown>
    if (!canEditContactDetails.value) {
      ;[
        'phone',
        'email',
        'homeAddress',
        'emergencyContactName',
        'emergencyContactRelation',
        'emergencyContactPhone'
      ].forEach((key) => delete employeeRecord[key])
    }
    if (!canEditIdentityDetails.value) {
      ;[
        'gender',
        'birthDate',
        'idCardNo',
        'ethnicity',
        'educationLevel',
        'schoolName',
        'majorName',
        'maritalStatus',
        'politicalStatus',
        'nativePlace'
      ].forEach((key) => delete employeeRecord[key])
    }
    if (!canEditCareerRecords.value) delete employeeRecord.remark
    if (!isPlatformSuper.value) employee.tenantId = getUserInfo.value.tenantId
    return employee
  }

  const handleSave = async (): Promise<void> => {
    try {
      await basicFormRef.value?.validate()
    } catch (error) {
      const failure = parseBasicValidationFailure(error)
      await focusValidationTarget(failure)
      ElMessage.warning(failure.message)
      return
    }
    const historyFailure = canEditCareerRecords.value ? validateHistories() : undefined
    if (historyFailure) {
      await focusValidationTarget(historyFailure)
      ElMessage.warning(historyFailure.message)
      return
    }

    page.saving = true
    try {
      const payload: Api.Hr.EmployeeProfilePayload = {
        employee: normalizeEmployee(),
        driver: isDriverEmployeeCreate.value
          ? {
              carrierId: form.driverCarrierId,
              driverType: form.driverType,
              licenseType: form.driverLicenseType,
              licenseExpireDate: form.driverLicenseExpireDate
            }
          : null
      }
      if (canEditCareerRecords.value) {
        payload.contracts = structuredClone(toRaw(form.contracts))
        payload.educations = structuredClone(toRaw(form.educations))
        payload.workExperiences = structuredClone(toRaw(form.workExperiences))
        payload.trainings = structuredClone(toRaw(form.trainings))
        payload.rewards = structuredClone(toRaw(form.rewards))
      } else if (canEditCompensationDetails.value) {
        payload.contracts = structuredClone(toRaw(form.contracts))
        payload.trainings = structuredClone(toRaw(form.trainings))
        payload.rewards = structuredClone(toRaw(form.rewards))
      }
      await saveEmployeeProfile(payload)
      ElMessage.success('员工完整档案已保存')
      goBack()
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : '员工档案保存失败，请稍后重试')
    } finally {
      page.saving = false
    }
  }

  const goBack = (): void => {
    void router.push('/hr/personnel/employee-roster')
  }

  watch(selectedPosition, (position) => {
    if (position) form.jobTitle = position.positionName
    if (!isDriverEmployeeCreate.value) {
      form.driverCarrierId = ''
      return
    }
    void loadDriverCarrierOptions()
  })

  onMounted(() => void initializePage())
</script>

<style scoped lang="scss">
  .hr-profile-page {
    --profile-accent: var(--el-color-primary);

    :deep(> .art-async-state) {
      display: flex;
      flex-direction: column;
      min-height: 0;
    }

    &__summary {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) minmax(180px, 260px);
      gap: 20px;
      align-items: center;
      padding: 18px 22px;
      margin-bottom: 14px;
      background: linear-gradient(
        110deg,
        var(--el-bg-color) 0%,
        var(--el-bg-color) 58%,
        color-mix(in srgb, var(--profile-accent) 6%, var(--el-bg-color)) 100%
      );
      border: 1px solid
        color-mix(in srgb, var(--profile-accent) 18%, var(--el-border-color-lighter));
    }

    &__access-notice {
      margin-bottom: 14px;
    }

    &__avatar {
      display: inline-flex;
      min-width: 118px;
      padding: 6px;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--custom-radius);
      box-shadow: 0 8px 22px rgb(15 23 42 / 8%);
    }

    &__avatar :deep(.upload-container) {
      color: var(--el-text-color-secondary);
      background: var(--el-fill-color-extra-light);
      border-color: var(--el-border-color);
      border-radius: calc(var(--custom-radius) - 4px);
    }

    &__avatar :deep(.resource-btn) {
      color: var(--el-text-color-secondary);
      background: var(--el-bg-color);
      border-color: var(--el-border-color-lighter);
      border-radius: calc(var(--custom-radius) - 4px) calc(var(--custom-radius) - 4px) 0 0;
    }

    &__summary-copy {
      min-width: 0;
    }

    &__summary-copy > span {
      font-size: 11px;
      font-weight: 800;
      color: var(--profile-accent);
      letter-spacing: 0.14em;
    }

    &__summary-copy strong {
      display: block;
      margin-top: 4px;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 22px;
      white-space: nowrap;
    }

    &__summary-copy p {
      margin: 5px 0 0;
      color: var(--el-text-color-secondary);
    }

    &__completion {
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 8px 12px;
      align-items: end;
    }

    &__completion small {
      color: var(--el-text-color-secondary);
    }

    &__completion strong {
      font-size: 22px;
      color: var(--profile-accent);
    }

    &__completion :deep(.el-progress) {
      grid-column: 1 / -1;
    }

    &__tabs {
      flex: 1 0 auto;
      min-height: 0;
      padding: 0 22px 22px;
      overflow: hidden;
    }

    &__tabs :deep(.el-tabs__header) {
      position: sticky;
      top: 0;
      z-index: 4;
      padding: 0 22px;
      margin: 0 -22px 22px;
      background: var(--el-bg-color);
    }

    &__tabs :deep(.el-tabs__nav-wrap::after) {
      height: 1px;
    }

    :deep(.hr-profile-page__tab-count) {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 20px;
      height: 20px;
      padding: 0 6px;
      margin-left: 4px;
      font-size: 11px;
      background: var(--el-fill-color);
      border-radius: 999px;
    }

    :deep(.hr-profile-page__record-form) {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 0 18px;
    }

    :deep(.hr-profile-page__record-form .el-form-item) {
      min-width: 0;
      margin-bottom: 18px;
    }

    :deep(.hr-profile-page__record-form .el-select),
    :deep(.hr-profile-page__record-form .el-date-editor),
    :deep(.hr-profile-page__record-form .el-input-number) {
      width: 100%;
    }

    :deep(.hr-profile-page__record-form .is-wide) {
      grid-column: 1 / -1;
    }

    :deep(.hr-profile-page__compensation-form) {
      max-width: 360px;
      padding: 0 18px;
    }

    :deep(.hr-profile-page__compensation-form .el-input-number) {
      width: 100%;
    }

    &__history-mask {
      display: grid;
      gap: 16px;
      padding: 8px 0;
    }

    &__history-counts {
      display: grid;
      grid-template-columns: repeat(5, minmax(0, 1fr));
      gap: 10px;

      > div {
        display: grid;
        gap: 3px;
        padding: 16px;
        text-align: center;
        background: var(--el-fill-color-lighter);
        border-radius: var(--custom-radius);
      }

      strong {
        font-size: 22px;
      }

      span {
        color: var(--el-text-color-secondary);
      }
    }

    &__save-hint {
      display: block;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }

    &__save-hint b {
      color: var(--el-color-danger);
    }

    &__footer {
      flex: none;
      margin-top: calc(var(--art-space-4) + var(--art-sticky-offset));
    }

    @media (width <= 980px) {
      &__summary {
        grid-template-columns: auto minmax(0, 1fr);
      }

      &__completion {
        grid-column: 1 / -1;
      }

      :deep(.hr-profile-page__record-form) {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__history-counts {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }
    }

    @media (width <= 640px) {
      &__summary {
        grid-template-columns: 1fr;
        padding: 16px;
        text-align: center;
      }

      &__avatar {
        justify-self: center;
      }

      &__tabs {
        padding-inline: 14px;
      }

      &__tabs :deep(.el-tabs__header) {
        padding-inline: 14px;
        margin-inline: -14px;
      }

      :deep(.hr-profile-page__record-form) {
        grid-template-columns: 1fr;
      }

      :deep(.hr-profile-page__record-form .is-wide) {
        grid-column: auto;
      }

      &__history-counts {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__save-hint {
        display: none;
      }
    }
  }
</style>
