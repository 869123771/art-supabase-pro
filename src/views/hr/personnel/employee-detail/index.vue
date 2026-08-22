<template>
  <ArtPageShell
    class="employee-detail-page"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    :empty="!profile"
    empty-text="暂无员工档案"
    @retry="loadPage"
  >
    <ArtPageHeader
      :title="profile?.employeeName || '员工档案详情'"
      :subtitle="profile?.employeeNo || '--'"
      show-back
      @back="goBack"
    >
      <ElButton
        v-auth="'Hr:Employee:Edit'"
        type="primary"
        :disabled="!profile?.id"
        @click="editProfile"
      >
        <ArtSvgIcon icon="ri:edit-line" />编辑员工档案
      </ElButton>
    </ArtPageHeader>

    <template v-if="profile">
      <section class="employee-detail-page__summary art-card-xs">
        <ElAvatar :size="84" :src="profile.avatarUrl || undefined">
          {{ employeeInitials }}
        </ElAvatar>
        <div class="employee-detail-page__identity">
          <span>EMPLOYEE PROFILE</span>
          <h1>{{ profile.employeeName }}</h1>
          <p>{{ profile.jobTitle || '暂未维护工作岗位' }}</p>
          <div>
            <ArtDictDisplay
              dict-code="hrEmploymentStatus"
              :value="profile.employmentStatus"
              display="tag"
            />
            <ElTag effect="plain" round>{{
              profile.organization?.organizationName || '未归属组织'
            }}</ElTag>
            <ElTag
              v-if="canViewMaintenanceAudit && profile.account?.id"
              type="success"
              effect="plain"
              round
              >已开通系统账号</ElTag
            >
          </div>
        </div>
        <div class="employee-detail-page__quick-facts">
          <div
            ><small>员工编号</small><strong>{{ profile.employeeNo }}</strong></div
          >
          <div
            ><small>入职日期</small><strong>{{ profile.hireDate || '--' }}</strong></div
          >
          <div v-if="canViewContactDetails"
            ><small>联系电话</small><strong>{{ profile.phone || '--' }}</strong></div
          >
        </div>
      </section>

      <ElAlert
        v-if="limitedAccessSummary"
        class="employee-detail-page__access-notice"
        type="info"
        :closable="false"
        show-icon
        :title="limitedAccessSummary"
      />

      <ElTabs v-model="activeTab" class="employee-detail-page__tabs art-card-xs">
        <ElTabPane label="基础信息" name="basic">
          <div class="employee-detail-page__sections">
            <section class="employee-detail-page__section">
              <ArtSectionTitle>组织与任职</ArtSectionTitle>
              <ArtDescriptions :data="profile" :items="employmentItems" :columns="3" />
            </section>
            <section v-if="canViewIdentityDetails" class="employee-detail-page__section">
              <ArtSectionTitle>个人身份</ArtSectionTitle>
              <ArtDescriptions :data="profile" :items="identityItems" :columns="3" />
            </section>
            <section v-if="contactAndOtherItems.length" class="employee-detail-page__section">
              <ArtSectionTitle>联系与其他</ArtSectionTitle>
              <ArtDescriptions :data="profile" :items="contactAndOtherItems" :columns="3" />
            </section>
          </div>
        </ElTabPane>
        <ElTabPane
          v-if="canViewCareerRecords && !profile.historiesMasked"
          :label="`劳动合同 ${profile.contracts.length}`"
          name="contracts"
        >
          <EmployeeHistoryList v-bind="historyPanels.contracts" :records="profile.contracts" />
        </ElTabPane>
        <ElTabPane
          v-if="canViewCareerRecords && !profile.historiesMasked"
          :label="`教育背景 ${profile.educations.length}`"
          name="educations"
        >
          <EmployeeHistoryList v-bind="historyPanels.educations" :records="profile.educations" />
        </ElTabPane>
        <ElTabPane
          v-if="canViewCareerRecords && !profile.historiesMasked"
          :label="`工作经历 ${profile.workExperiences.length}`"
          name="workExperiences"
        >
          <EmployeeHistoryList
            v-bind="historyPanels.workExperiences"
            :records="profile.workExperiences"
          />
        </ElTabPane>
        <ElTabPane
          v-if="canViewCareerRecords && !profile.historiesMasked"
          :label="`培训经历 ${profile.trainings.length}`"
          name="trainings"
        >
          <EmployeeHistoryList v-bind="historyPanels.trainings" :records="profile.trainings" />
        </ElTabPane>
        <ElTabPane
          v-if="canViewCareerRecords && !profile.historiesMasked"
          :label="`奖惩经历 ${profile.rewards.length}`"
          name="rewards"
        >
          <EmployeeHistoryList v-bind="historyPanels.rewards" :records="profile.rewards" />
        </ElTabPane>
        <ElTabPane v-if="profile.historiesMasked" label="履历概览" name="histories">
          <div class="employee-detail-page__masked-history">
            <ElAlert
              title="履历内容已按字段权限脱敏，仅展示记录数量。"
              type="warning"
              :closable="false"
              show-icon
            />
            <div class="employee-detail-page__history-counts">
              <div v-for="item in historyCountItems" :key="item.key">
                <strong>{{ item.value }}</strong
                ><span>{{ item.label }}</span>
              </div>
            </div>
          </div>
        </ElTabPane>
      </ElTabs>
    </template>
  </ArtPageShell>
</template>

<script setup lang="ts">
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import EmployeeHistoryList from './modules/employee-history-list.vue'
  import { fetchEmployeeProfile } from '@/api/hr'
  import { useUserStore } from '@/store/modules/user'
  import { canViewField, getFieldAccess } from '@/utils/field-permission'

  defineOptions({ name: 'HrEmployeeDetail' })

  type EmployeeProfile = Api.Hr.EmployeeProfile
  type HistoryRecord = { id?: string }
  type DescriptionItem = ArtDescriptionItem<Partial<EmployeeProfile>>

  const route = useRoute()
  const router = useRouter()
  const userStore = useUserStore()
  const activeTab = ref('basic')
  const profile = shallowRef<EmployeeProfile>()
  const page = reactive<{ loading: boolean; error: Error | null }>({ loading: false, error: null })

  const employeeInitials = computed(() => {
    const name = profile.value?.employeeName.trim() || ''
    return Array.from(name).slice(0, 1).join('').toUpperCase() || '员'
  })
  const canViewContactDetails = computed(() =>
    canViewField(profile.value?.fieldAccess, 'contactDetails')
  )
  const canViewIdentityDetails = computed(() =>
    canViewField(profile.value?.fieldAccess, 'identityDetails')
  )
  const canViewCompensationDetails = computed(() =>
    canViewField(profile.value?.fieldAccess, 'compensationDetails')
  )
  const canViewCareerRecords = computed(() =>
    canViewField(profile.value?.fieldAccess, 'careerRecords')
  )
  const canViewMaintenanceAudit = computed(() =>
    canViewField(profile.value?.fieldAccess, 'maintenanceAudit')
  )
  const isPlaintextField = (field: Api.Hr.EmployeeFieldKey): boolean =>
    ['read', 'edit'].includes(getFieldAccess(profile.value?.fieldAccess, field))
  const limitedAccessSummary = computed(() => {
    if (!profile.value || profile.value.isRecordOwner) return ''
    const limitedCount = (
      [
        'contactDetails',
        'identityDetails',
        'compensationDetails',
        'careerRecords',
        'maintenanceAudit'
      ] as Api.Hr.EmployeeFieldKey[]
    ).filter(
      (field) => !['read', 'edit'].includes(getFieldAccess(profile.value?.fieldAccess, field))
    ).length
    return limitedCount ? `${limitedCount} 组敏感信息已按你的字段权限隐藏或脱敏。` : ''
  })

  const employmentItems: DescriptionItem[] = [
    {
      key: 'tenant',
      label: '所属租户',
      value: (data: Partial<EmployeeProfile>) => data.tenant?.tenantName
    },
    {
      key: 'organization',
      label: '所属组织',
      value: (data: Partial<EmployeeProfile>) => data.organization?.organizationName
    },
    { key: 'employeeNo', label: '员工编号', field: 'employeeNo', copyable: true },
    { key: 'jobTitle', label: '工作岗位', field: 'jobTitle' },
    {
      key: 'employmentStatus',
      label: '任职状态',
      field: 'employmentStatus',
      dictCode: 'hrEmploymentStatus',
      dictDisplay: 'tag'
    },
    {
      key: 'employmentType',
      label: '用工类型',
      field: 'employmentType',
      dictCode: 'hrEmploymentType'
    },
    { key: 'hireDate', label: '入职日期', field: 'hireDate' },
    { key: 'probationEndDate', label: '转正日期', field: 'probationEndDate' },
    { key: 'leaveDate', label: '离职日期', field: 'leaveDate' },
    { key: 'contractStartDate', label: '合同开始', field: 'contractStartDate' },
    { key: 'contractEndDate', label: '合同结束', field: 'contractEndDate' }
  ]
  const identityItemDefinitions: DescriptionItem[] = [
    { key: 'gender', label: '性别', field: 'gender', dictCode: 'sex' },
    { key: 'birthDate', label: '出生日期', field: 'birthDate' },
    { key: 'idCardNo', label: '身份证号', field: 'idCardNo', copyable: true },
    { key: 'ethnicity', label: '民族', field: 'ethnicity', dictCode: 'hrEthnicity' },
    {
      key: 'maritalStatus',
      label: '婚姻状况',
      field: 'maritalStatus',
      dictCode: 'hrMaritalStatus'
    },
    {
      key: 'politicalStatus',
      label: '政治面貌',
      field: 'politicalStatus',
      dictCode: 'hrPoliticalStatus'
    },
    { key: 'nativePlace', label: '籍贯', field: 'nativePlace' },
    {
      key: 'educationLevel',
      label: '最高学历',
      field: 'educationLevel',
      dictCode: 'hrEducationLevel'
    },
    { key: 'schoolName', label: '毕业院校', field: 'schoolName' },
    { key: 'majorName', label: '专业', field: 'majorName' }
  ]
  const identityItems = computed<DescriptionItem[]>(() =>
    identityItemDefinitions.map((item) =>
      isPlaintextField('identityDetails')
        ? item
        : {
            ...item,
            copyable: false,
            dictCode: undefined,
            value: (data: Partial<EmployeeProfile>) =>
              item.field ? Reflect.get(data, item.field) : undefined
          }
    )
  )
  const contactItemDefinitions: DescriptionItem[] = [
    { key: 'phone', label: '手机号码', field: 'phone', copyable: true },
    { key: 'email', label: '电子邮箱', field: 'email', copyable: true },
    { key: 'homeAddress', label: '家庭住址', field: 'homeAddress' },
    { key: 'emergencyContactName', label: '紧急联系人', field: 'emergencyContactName' },
    {
      key: 'emergencyContactRelation',
      label: '联系人关系',
      field: 'emergencyContactRelation',
      dictCode: 'hrEmergencyRelation'
    },
    {
      key: 'emergencyContactPhone',
      label: '紧急联系电话',
      field: 'emergencyContactPhone',
      copyable: true
    },
    { key: 'remark', label: '备注', field: 'remark', span: 3 }
  ]
  const contactAndOtherItems = computed<DescriptionItem[]>(() =>
    contactItemDefinitions
      .filter((item) =>
        item.key === 'remark' ? canViewCareerRecords.value : canViewContactDetails.value
      )
      .map((item) =>
        item.key === 'remark' || isPlaintextField('contactDetails')
          ? item
          : {
              ...item,
              copyable: false,
              dictCode: undefined,
              value: (data: Partial<EmployeeProfile>) =>
                item.field ? Reflect.get(data, item.field) : undefined
            }
      )
  )

  const dictLabel = (code: string, value: unknown): string => {
    const options = userStore.getDictMap[code] ?? []
    return String(options.find((item) => String(item.value) === String(value))?.label ?? '')
  }
  const historyPanelDefinitions = {
    contracts: createHistoryPanel(
      '劳动合同',
      '合同期限、签署状态、工作地点与薪资信息',
      'ri:file-list-3-line',
      [
        item('contractNo', '合同编号', true),
        dictItem('contractType', '合同类型', 'hrContractType'),
        dictItem('contractStatus', '合同状态', 'hrContractStatus'),
        item('signDate', '签署日期'),
        item('startDate', '开始日期'),
        item('endDate', '结束日期'),
        item('probationEndDate', '试用期结束'),
        item('workLocation', '工作地点'),
        item('monthlySalary', '月薪'),
        item('remark', '备注', false, 3)
      ],
      (record, index) => String(read(record, 'contractNo') || `合同 ${index + 1}`),
      (record) => dictLabel('hrContractStatus', read(record, 'contractStatus'))
    ),
    educations: createHistoryPanel(
      '教育背景',
      '学历、学位、学校与证书信息',
      'ri:graduation-cap-line',
      [
        item('schoolName', '学校名称'),
        item('majorName', '专业'),
        dictItem('educationLevel', '学历', 'hrEducationLevel'),
        dictItem('degree', '学位', 'hrDegree'),
        item('startDate', '开始日期'),
        item('endDate', '结束日期'),
        item('certificateNo', '证书编号', true),
        item('remark', '备注', false, 3)
      ],
      (record, index) => String(read(record, 'schoolName') || `教育经历 ${index + 1}`),
      (record) => dictLabel('hrEducationLevel', read(record, 'educationLevel'))
    ),
    workExperiences: createHistoryPanel(
      '工作经历',
      '入职前任职公司、岗位职责和证明人',
      'ri:briefcase-4-line',
      [
        item('companyName', '公司名称'),
        item('departmentName', '所在部门'),
        item('jobTitle', '工作岗位'),
        item('startDate', '开始日期'),
        item('endDate', '结束日期'),
        item('referenceName', '证明人'),
        item('referencePhone', '证明人电话', true),
        item('leavingReason', '离职原因'),
        item('responsibilities', '主要职责', false, 3)
      ],
      (record, index) => String(read(record, 'companyName') || `工作经历 ${index + 1}`),
      (record) => String(read(record, 'jobTitle') || '')
    ),
    trainings: createHistoryPanel(
      '培训经历',
      '培训项目、结果、证书与费用',
      'ri:presentation-line',
      [
        item('trainingName', '培训名称'),
        dictItem('trainingType', '培训类型', 'hrTrainingType'),
        item('providerName', '培训机构'),
        item('startDate', '开始日期'),
        item('endDate', '结束日期'),
        dictItem('trainingResult', '培训结果', 'hrTrainingResult'),
        item('certificateNo', '证书编号', true),
        item('cost', '培训费用'),
        item('remark', '备注', false, 3)
      ],
      (record, index) => String(read(record, 'trainingName') || `培训经历 ${index + 1}`),
      (record) => dictLabel('hrTrainingResult', read(record, 'trainingResult'))
    ),
    rewards: createHistoryPanel(
      '奖惩经历',
      '奖励、处分及其认定级别',
      'ri:award-line',
      [
        dictItem('recordType', '奖惩类型', 'hrRewardType'),
        dictItem('recordLevel', '奖惩级别', 'hrRewardLevel'),
        item('title', '奖惩标题'),
        item('recordDate', '发生日期'),
        item('issuingOrganization', '颁发/认定机构'),
        item('amount', '金额'),
        item('description', '详细说明', false, 3)
      ],
      (record, index) => String(read(record, 'title') || `奖惩记录 ${index + 1}`),
      (record) => dictLabel('hrRewardType', read(record, 'recordType'))
    )
  }
  const compensationKeys = new Set(['monthlySalary', 'cost', 'amount'])
  const historyPanels = computed(
    () =>
      Object.fromEntries(
        Object.entries(historyPanelDefinitions).map(([key, panel]) => [
          key,
          {
            ...panel,
            items: canViewCompensationDetails.value
              ? panel.items
              : panel.items.filter((item) => !compensationKeys.has(String(item.key)))
          }
        ])
      ) as typeof historyPanelDefinitions
  )
  const historyCountItems = computed(() => [
    { key: 'contracts', label: '劳动合同', value: profile.value?.historyCounts?.contracts ?? 0 },
    { key: 'educations', label: '教育背景', value: profile.value?.historyCounts?.educations ?? 0 },
    {
      key: 'workExperiences',
      label: '工作经历',
      value: profile.value?.historyCounts?.workExperiences ?? 0
    },
    { key: 'trainings', label: '培训经历', value: profile.value?.historyCounts?.trainings ?? 0 },
    { key: 'rewards', label: '奖惩经历', value: profile.value?.historyCounts?.rewards ?? 0 }
  ])

  function item(
    key: string,
    label: string,
    copyable = false,
    span?: number
  ): ArtDescriptionItem<HistoryRecord> {
    return { key, label, field: key, copyable, span }
  }
  function read(record: HistoryRecord, key: string): unknown {
    return Reflect.get(record, key)
  }
  function dictItem(
    key: string,
    label: string,
    dictCode: string
  ): ArtDescriptionItem<HistoryRecord> {
    return { key, label, field: key, dictCode }
  }
  function createHistoryPanel(
    title: string,
    description: string,
    icon: string,
    items: ArtDescriptionItem<HistoryRecord>[],
    getTitle: (record: HistoryRecord, index: number) => string,
    getSubtitle: (record: HistoryRecord) => string
  ) {
    return { title, description, icon, items, getTitle, getSubtitle }
  }

  const loadPage = async (): Promise<void> => {
    page.loading = true
    page.error = null
    try {
      await Promise.all([
        userStore.fetchDictList(),
        ...[
          'sex',
          'hrEmploymentStatus',
          'hrEmploymentType',
          'hrEducationLevel',
          'hrEthnicity',
          'hrMaritalStatus',
          'hrPoliticalStatus',
          'hrEmergencyRelation',
          'hrContractType',
          'hrContractStatus',
          'hrDegree',
          'hrTrainingType',
          'hrTrainingResult',
          'hrRewardType',
          'hrRewardLevel'
        ].map((code) => userStore.ensureDictLoaded(code))
      ])
      const result = await fetchEmployeeProfile(String(route.params.id || ''))
      if (!result) throw new Error('员工档案不存在，或当前账号无权查看')
      profile.value = result
      activeTab.value = result.historiesMasked ? 'histories' : 'basic'
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('员工档案加载失败')
    } finally {
      page.loading = false
    }
  }
  const goBack = (): void => void router.push('/hr/personnel/employee-roster')
  const editProfile = (): void => {
    if (profile.value?.id) void router.push(`/hr/personnel/employee-profile/${profile.value.id}`)
  }

  onMounted(() => void loadPage())
</script>

<style scoped lang="scss">
  .employee-detail-page {
    &__summary {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) minmax(320px, 0.85fr);
      gap: 22px;
      align-items: center;
      padding: 22px 26px;
      margin-bottom: 14px;
      background: linear-gradient(110deg, var(--el-bg-color) 58%, var(--el-color-primary-light-9));

      :deep(.el-avatar) {
        font-size: 24px;
        font-weight: 700;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-8);
        border: 4px solid var(--el-bg-color);
        box-shadow: 0 10px 26px rgb(15 23 42 / 10%);
      }
    }

    &__identity {
      min-width: 0;

      > span {
        font-size: 11px;
        font-weight: 800;
        color: var(--el-color-primary);
        letter-spacing: 0.12em;
      }

      h1 {
        margin: 4px 0;
        font-size: 24px;
      }

      p {
        margin: 0;
        color: var(--el-text-color-secondary);
      }

      > div {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        margin-top: 12px;
      }
    }

    &__quick-facts {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      background: color-mix(in srgb, var(--el-bg-color) 88%, transparent);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--custom-radius);

      > div {
        min-width: 0;
        padding: 13px 15px;
      }

      > div:not(:last-child) {
        border-right: 1px solid var(--el-border-color-lighter);
      }

      small,
      strong {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      small {
        color: var(--el-text-color-secondary);
      }

      strong {
        margin-top: 4px;
        font-size: 14px;
      }
    }

    &__tabs {
      padding: 0 20px 20px;
    }

    &__access-notice {
      margin-bottom: 14px;
    }

    &__masked-history {
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

    &__sections {
      display: grid;
      gap: 14px;
    }

    &__section {
      padding: 18px;
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--custom-radius);
    }

    @media (width <= 1000px) {
      &__summary {
        grid-template-columns: auto minmax(0, 1fr);
      }

      &__quick-facts {
        grid-column: 1 / -1;
      }

      &__history-counts {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }
    }

    @media (width <= 640px) {
      &__summary {
        grid-template-columns: 1fr;
        padding: 18px;
        text-align: center;
      }

      &__summary :deep(.el-avatar) {
        justify-self: center;
      }

      &__identity > div {
        justify-content: center;
      }

      &__quick-facts {
        grid-template-columns: 1fr;
        text-align: left;
      }

      &__quick-facts > div:not(:last-child) {
        border-right: 0;
        border-bottom: 1px solid var(--el-border-color-lighter);
      }

      &__tabs {
        padding-inline: 14px;
      }

      &__history-counts {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }
  }
</style>
