export type HrWorkspaceKey =
  | 'personnelChange'
  | 'lifecycle'
  | 'compliance'
  | 'headcount'
  | 'attendance'
  | 'selfService'
  | 'performance'
  | 'talent'
  | 'recruitment'

export interface HrWorkspaceColumn {
  key: keyof Api.Hr.WorkspaceRecord | string
  label: string
  minWidth?: number
  width?: number
  dictCode?: string
  dateTime?: boolean
  suffix?: string
}

export interface HrWorkspaceField {
  key: keyof Api.Hr.WorkspaceRecord
  label: string
  type: 'input' | 'select' | 'date' | 'number' | 'switch' | 'timeSelect'
  required?: boolean
  dictCode?: string
  optionEntity?: Api.Hr.WorkspaceEntity
  optionLabelKeys?: Array<keyof Api.Hr.WorkspaceRecord | string>
  span?: number
  props?: Record<string, unknown>
}

export interface HrWorkspaceTab {
  key: string
  label: string
  entity: Api.Hr.WorkspaceEntity
  statusDict?: string
  statusKey?: keyof Api.Hr.WorkspaceRecord
  columns: HrWorkspaceColumn[]
  fields: HrWorkspaceField[]
  defaults: Api.Hr.WorkspaceRecord
  approvalBusinessType?: string
  canEffect?: boolean
  canCompleteTask?: boolean
}

export interface HrWorkspaceDefinition {
  eyebrow: string
  title: string
  description: string
  icon: string
  tags: string[]
  tabs: HrWorkspaceTab[]
}

const employeeField = (): HrWorkspaceField => ({
  key: 'employeeId',
  label: '员工',
  type: 'select',
  required: true,
  optionEntity: 'personnelChange',
  optionLabelKeys: ['employee.employeeNo', 'employee.employeeName']
})
const positionField = (
  key: 'positionId' | 'fromPositionId' | 'toPositionId',
  label: string
): HrWorkspaceField => ({
  key,
  label,
  type: 'select',
  optionEntity: 'headcount',
  optionLabelKeys: ['position.positionCode', 'position.positionName']
})
const organizationField = (
  key: 'organizationId' | 'fromOrganizationId' | 'toOrganizationId',
  label: string
): HrWorkspaceField => ({
  key,
  label,
  type: 'select',
  optionEntity: 'headcount',
  optionLabelKeys: ['organization.organizationCode', 'organization.organizationName']
})
const input = (
  key: keyof Api.Hr.WorkspaceRecord,
  label: string,
  required = false
): HrWorkspaceField => ({ key, label, type: 'input', required })
const date = (
  key: keyof Api.Hr.WorkspaceRecord,
  label: string,
  required = false
): HrWorkspaceField => ({ key, label, type: 'date', required })
const number = (
  key: keyof Api.Hr.WorkspaceRecord,
  label: string,
  required = false
): HrWorkspaceField => ({ key, label, type: 'number', required, props: { min: 0 } })
const dict = (
  key: keyof Api.Hr.WorkspaceRecord,
  label: string,
  dictCode: string,
  required = false
): HrWorkspaceField => ({ key, label, type: 'select', dictCode, required })

export const hrWorkspaceDefinitions: Record<HrWorkspaceKey, HrWorkspaceDefinition> = {
  personnelChange: {
    eyebrow: 'PEOPLE LIFECYCLE',
    title: '人事异动中心',
    icon: 'ri:swap-box-line',
    description:
      '集中管理转正、调动、晋升、停复职与离职，审批通过后按生效日期更新员工当前任职快照。',
    tags: ['审批留痕', '变更前后快照', '到期生效'],
    tabs: [
      {
        key: 'changes',
        label: '异动单',
        entity: 'personnelChange',
        statusDict: 'hrApprovalStatus',
        statusKey: 'status',
        approvalBusinessType: 'hr_personnel_change',
        canEffect: true,
        columns: [
          { key: 'changeNo', label: '异动单号', minWidth: 150 },
          { key: 'employee.employeeName', label: '员工', minWidth: 120 },
          { key: 'changeType', label: '异动类型', width: 110, dictCode: 'hrPersonnelChangeType' },
          { key: 'effectiveDate', label: '生效日期', width: 120 },
          { key: 'status', label: '状态', width: 110, dictCode: 'hrApprovalStatus' },
          { key: 'reason', label: '异动原因', minWidth: 220 }
        ],
        fields: [
          input('changeNo', '异动单号', true),
          employeeField(),
          dict('changeType', '异动类型', 'hrPersonnelChangeType', true),
          date('effectiveDate', '生效日期', true),
          organizationField('fromOrganizationId', '原组织'),
          organizationField('toOrganizationId', '新组织'),
          positionField('fromPositionId', '原岗位'),
          positionField('toPositionId', '新岗位'),
          dict('fromEmploymentStatus', '原任职状态', 'hrEmploymentStatus'),
          dict('toEmploymentStatus', '新任职状态', 'hrEmploymentStatus'),
          input('fromJobTitle', '原职务'),
          input('toJobTitle', '新职务'),
          { ...input('reason', '异动原因', true), span: 24, props: { type: 'textarea', rows: 3 } },
          { ...input('remark', '备注'), span: 24, props: { type: 'textarea', rows: 2 } }
        ],
        defaults: { status: 'draft' }
      }
    ]
  },
  lifecycle: {
    eyebrow: 'ONBOARDING & OFFBOARDING',
    title: '入转调离工作台',
    icon: 'ri:user-settings-line',
    description: '通过可审计任务清单衔接账号、组织岗位、司机档案、资产交接与资料归档。',
    tags: ['任务清单', '跨系统交接', '完成闭环'],
    tabs: [
      {
        key: 'cases',
        label: '生命周期事项',
        entity: 'lifecycleCase',
        statusDict: 'hrApprovalStatus',
        statusKey: 'status',
        approvalBusinessType: 'hr_lifecycle_case',
        columns: [
          { key: 'caseNo', label: '事项编号', minWidth: 150 },
          { key: 'employee.employeeName', label: '员工', minWidth: 120 },
          { key: 'caseType', label: '事项类型', width: 110, dictCode: 'hrLifecycleCaseType' },
          { key: 'plannedEffectiveDate', label: '计划日期', width: 120 },
          { key: 'status', label: '状态', width: 110, dictCode: 'hrApprovalStatus' },
          { key: 'remark', label: '说明', minWidth: 200 }
        ],
        fields: [
          input('caseNo', '事项编号', true),
          employeeField(),
          dict('caseType', '事项类型', 'hrLifecycleCaseType', true),
          date('plannedEffectiveDate', '计划生效日期', true),
          { ...input('remark', '事项说明'), span: 24, props: { type: 'textarea', rows: 3 } }
        ],
        defaults: { status: 'draft' }
      },
      {
        key: 'tasks',
        label: '交接任务',
        entity: 'lifecycleTask',
        statusDict: 'hrLifecycleTaskStatus',
        statusKey: 'status',
        canCompleteTask: true,
        columns: [
          { key: 'lifecycleCase.caseNo', label: '事项编号', minWidth: 150 },
          { key: 'taskType', label: '任务类型', width: 120, dictCode: 'hrLifecycleTaskType' },
          { key: 'taskName', label: '任务名称', minWidth: 180 },
          { key: 'dueDate', label: '截止日期', width: 120 },
          { key: 'status', label: '状态', width: 110, dictCode: 'hrLifecycleTaskStatus' },
          { key: 'completionNote', label: '完成说明', minWidth: 180 }
        ],
        fields: [
          {
            key: 'lifecycleCaseId',
            label: '生命周期事项',
            type: 'select',
            required: true,
            optionEntity: 'lifecycleCase',
            optionLabelKeys: ['caseNo', 'employee.employeeName']
          },
          dict('taskType', '任务类型', 'hrLifecycleTaskType', true),
          input('taskName', '任务名称', true),
          date('dueDate', '截止日期'),
          number('sort', '排序'),
          { ...input('completionNote', '处理说明'), span: 24, props: { type: 'textarea', rows: 3 } }
        ],
        defaults: { status: 'pending', sort: 0 }
      }
    ]
  },
  compliance: {
    eyebrow: 'COMPLIANCE DESK',
    title: '合同与资质工作台',
    icon: 'ri:verified-badge-line',
    description: '跨员工汇总劳动合同与任职资质，统一管理续签、证书附件和到期风险。',
    tags: ['合同到期', '资质复审', '附件留存'],
    tabs: [
      {
        key: 'contracts',
        label: '劳动合同',
        entity: 'contract',
        statusDict: 'hrContractStatus',
        statusKey: 'contractStatus',
        columns: [
          { key: 'contractNo', label: '合同编号', minWidth: 150 },
          { key: 'employee.employeeName', label: '员工', minWidth: 120 },
          { key: 'contractType', label: '合同类型', width: 120, dictCode: 'hrContractType' },
          { key: 'startDate', label: '开始日期', width: 120 },
          { key: 'endDate', label: '到期日期', width: 120 },
          { key: 'contractStatus', label: '状态', width: 110, dictCode: 'hrContractStatus' }
        ],
        fields: [
          input('contractNo', '合同编号', true),
          employeeField(),
          dict('contractType', '合同类型', 'hrContractType', true),
          dict('contractStatus', '合同状态', 'hrContractStatus', true),
          date('signDate', '签订日期'),
          date('startDate', '开始日期', true),
          date('endDate', '结束日期'),
          date('probationEndDate', '试用期结束'),
          input('workLocation', '工作地点'),
          number('monthlySalary', '月薪'),
          number('renewalReminderDays', '提前提醒天数'),
          input('attachmentUrl', '合同附件地址'),
          { ...input('remark', '备注'), span: 24, props: { type: 'textarea', rows: 2 } }
        ],
        defaults: { contractStatus: 'active', contractType: 'fixed_term', renewalReminderDays: 30 }
      },
      {
        key: 'qualifications',
        label: '资质证照',
        entity: 'qualification',
        statusDict: 'hrQualificationStatus',
        statusKey: 'status',
        columns: [
          { key: 'employee.employeeName', label: '员工', minWidth: 120 },
          {
            key: 'qualificationType',
            label: '资质类型',
            width: 120,
            dictCode: 'hrQualificationType'
          },
          { key: 'qualificationName', label: '资质名称', minWidth: 180 },
          { key: 'certificateNo', label: '证书编号', minWidth: 150 },
          { key: 'expiryDate', label: '到期日期', width: 120 },
          { key: 'status', label: '状态', width: 110, dictCode: 'hrQualificationStatus' }
        ],
        fields: [
          employeeField(),
          dict('qualificationType', '资质类型', 'hrQualificationType', true),
          input('qualificationName', '资质名称', true),
          input('certificateNo', '证书编号'),
          input('issuer', '发证机构'),
          date('issueDate', '发证日期'),
          date('expiryDate', '到期日期'),
          dict('status', '资质状态', 'hrQualificationStatus', true),
          number('reminderDays', '提前提醒天数'),
          input('attachmentUrl', '证书附件地址'),
          { ...input('remark', '备注'), span: 24, props: { type: 'textarea', rows: 2 } }
        ],
        defaults: { status: 'valid', reminderDays: 30 }
      }
    ]
  },
  headcount: {
    eyebrow: 'WORKFORCE PLAN',
    title: '编制管理',
    icon: 'ri:organization-chart',
    description: '按组织与岗位维护核定编制和有效期，为招聘需求和岗位缺口提供统一依据。',
    tags: ['组织岗位口径', '有效期控制', '缺编依据'],
    tabs: [
      {
        key: 'headcount',
        label: '岗位编制',
        entity: 'headcount',
        columns: [
          { key: 'organization.organizationName', label: '组织', minWidth: 160 },
          { key: 'position.positionName', label: '岗位', minWidth: 150 },
          { key: 'approvedCount', label: '核定人数', width: 110 },
          { key: 'occupiedCount', label: '在岗人数', width: 110 },
          { key: 'vacancyCount', label: '编制缺口', width: 110 },
          { key: 'effectiveFrom', label: '生效日期', width: 120 },
          { key: 'effectiveTo', label: '失效日期', width: 120 },
          { key: 'enabled', label: '启用', width: 90, dictCode: 'commonBoolean' }
        ],
        fields: [
          organizationField('organizationId', '组织'),
          positionField('positionId', '岗位'),
          number('approvedCount', '核定人数', true),
          date('effectiveFrom', '生效日期', true),
          date('effectiveTo', '失效日期'),
          { key: 'enabled', label: '启用', type: 'switch' },
          { ...input('remark', '备注'), span: 24, props: { type: 'textarea', rows: 2 } }
        ],
        defaults: {
          approvedCount: 0,
          effectiveFrom: new Date().toISOString().slice(0, 10),
          enabled: true
        }
      }
    ]
  },
  attendance: {
    eyebrow: 'TIME & ATTENDANCE',
    title: '考勤排班',
    icon: 'ri:calendar-check-line',
    description: '维护班次、排班和月度考勤事实，请假加班申请由员工自助和统一工作流承接。',
    tags: ['班次排班', '考勤异常', 'TMS 汇总边界'],
    tabs: [
      {
        key: 'shifts',
        label: '班次',
        entity: 'shift',
        columns: [
          { key: 'shiftCode', label: '班次编码', width: 130 },
          { key: 'shiftName', label: '班次名称', minWidth: 140 },
          { key: 'shiftType', label: '类型', width: 110, dictCode: 'hrShiftType' },
          { key: 'startTime', label: '上班时间', width: 110 },
          { key: 'endTime', label: '下班时间', width: 110 },
          { key: 'enabled', label: '启用', width: 90, dictCode: 'commonBoolean' }
        ],
        fields: [
          input('shiftCode', '班次编码', true),
          input('shiftName', '班次名称', true),
          dict('shiftType', '班次类型', 'hrShiftType', true),
          { key: 'startTime', label: '上班时间', type: 'timeSelect', required: true },
          { key: 'endTime', label: '下班时间', type: 'timeSelect', required: true },
          number('breakMinutes', '休息分钟'),
          { key: 'crossDay', label: '跨日班次', type: 'switch' },
          { key: 'enabled', label: '启用', type: 'switch' },
          input('remark', '备注')
        ],
        defaults: { shiftType: 'regular', breakMinutes: 0, crossDay: false, enabled: true }
      },
      {
        key: 'assignments',
        label: '排班',
        entity: 'shiftAssignment',
        statusDict: 'hrShiftAssignmentStatus',
        statusKey: 'assignmentStatus',
        columns: [
          { key: 'workDate', label: '工作日期', width: 120 },
          { key: 'employee.employeeName', label: '员工', minWidth: 120 },
          { key: 'shift.shiftName', label: '班次', minWidth: 120 },
          {
            key: 'assignmentStatus',
            label: '状态',
            width: 110,
            dictCode: 'hrShiftAssignmentStatus'
          },
          { key: 'remark', label: '备注', minWidth: 180 }
        ],
        fields: [
          employeeField(),
          {
            key: 'shiftId',
            label: '班次',
            type: 'select',
            required: true,
            optionEntity: 'shift',
            optionLabelKeys: ['shiftCode', 'shiftName']
          },
          date('workDate', '工作日期', true),
          dict('assignmentStatus', '排班状态', 'hrShiftAssignmentStatus', true),
          input('remark', '备注')
        ],
        defaults: { assignmentStatus: 'scheduled' }
      },
      {
        key: 'records',
        label: '考勤记录',
        entity: 'attendance',
        statusDict: 'hrAttendanceStatus',
        statusKey: 'attendanceStatus',
        columns: [
          { key: 'workDate', label: '日期', width: 120 },
          { key: 'employee.employeeName', label: '员工', minWidth: 120 },
          { key: 'shift.shiftName', label: '班次', minWidth: 120 },
          { key: 'workMinutes', label: '工时', width: 90, suffix: ' 分钟' },
          { key: 'overtimeMinutes', label: '加班', width: 90, suffix: ' 分钟' },
          { key: 'attendanceStatus', label: '状态', width: 110, dictCode: 'hrAttendanceStatus' },
          { key: 'source', label: '来源', width: 120, dictCode: 'hrAttendanceSource' }
        ],
        fields: [
          employeeField(),
          {
            key: 'shiftId',
            label: '班次',
            type: 'select',
            optionEntity: 'shift',
            optionLabelKeys: ['shiftCode', 'shiftName']
          },
          date('workDate', '工作日期', true),
          date('clockInAt', '上班打卡'),
          date('clockOutAt', '下班打卡'),
          number('workMinutes', '工作分钟'),
          number('overtimeMinutes', '加班分钟'),
          dict('attendanceStatus', '考勤状态', 'hrAttendanceStatus', true),
          dict('source', '数据来源', 'hrAttendanceSource', true),
          input('remark', '备注')
        ],
        defaults: {
          attendanceStatus: 'normal',
          source: 'manual',
          workMinutes: 0,
          overtimeMinutes: 0
        }
      }
    ]
  },
  selfService: {
    eyebrow: 'EMPLOYEE SELF SERVICE',
    title: '员工自助',
    icon: 'ri:user-shared-line',
    description: '员工提交请假、加班、档案变更、证明与调动申请，并查看本人审批进度。',
    tags: ['本人数据', '统一审批', '进度可查'],
    tabs: [
      {
        key: 'requests',
        label: '我的申请',
        entity: 'selfServiceRequest',
        statusDict: 'hrApprovalStatus',
        statusKey: 'status',
        approvalBusinessType: 'hr_self_service_request',
        columns: [
          { key: 'requestNo', label: '申请编号', minWidth: 150 },
          { key: 'employee.employeeName', label: '申请人', minWidth: 120 },
          {
            key: 'requestType',
            label: '申请类型',
            width: 120,
            dictCode: 'hrSelfServiceRequestType'
          },
          { key: 'title', label: '申请主题', minWidth: 180 },
          { key: 'startAt', label: '开始时间', minWidth: 150, dateTime: true },
          { key: 'durationHours', label: '时长', width: 90, suffix: ' 小时' },
          { key: 'status', label: '状态', width: 110, dictCode: 'hrApprovalStatus' }
        ],
        fields: [
          input('requestNo', '申请编号', true),
          employeeField(),
          dict('requestType', '申请类型', 'hrSelfServiceRequestType', true),
          input('title', '申请主题', true),
          date('startAt', '开始时间'),
          date('endAt', '结束时间'),
          number('durationHours', '时长（小时）'),
          { ...input('reason', '申请原因', true), span: 24, props: { type: 'textarea', rows: 3 } }
        ],
        defaults: { status: 'draft' }
      }
    ]
  },
  performance: {
    eyebrow: 'PERFORMANCE CYCLE',
    title: '绩效考核',
    icon: 'ri:bar-chart-box-line',
    description: '建立考核周期、员工评价和目标结果，可引用运输时效、安全与服务质量作为证据。',
    tags: ['周期管理', '目标评分', '结果确认'],
    tabs: [
      {
        key: 'cycles',
        label: '考核周期',
        entity: 'performanceCycle',
        statusDict: 'hrPerformanceCycleStatus',
        statusKey: 'status',
        columns: [
          { key: 'cycleCode', label: '周期编码', width: 140 },
          { key: 'cycleName', label: '周期名称', minWidth: 160 },
          { key: 'startDate', label: '开始日期', width: 120 },
          { key: 'endDate', label: '结束日期', width: 120 },
          { key: 'status', label: '状态', width: 110, dictCode: 'hrPerformanceCycleStatus' }
        ],
        fields: [
          input('cycleCode', '周期编码', true),
          input('cycleName', '周期名称', true),
          date('startDate', '开始日期', true),
          date('endDate', '结束日期', true),
          dict('status', '周期状态', 'hrPerformanceCycleStatus', true),
          { ...input('description', '周期说明'), span: 24, props: { type: 'textarea', rows: 3 } }
        ],
        defaults: { status: 'draft' }
      },
      {
        key: 'reviews',
        label: '员工考核',
        entity: 'performanceReview',
        statusDict: 'hrPerformanceReviewStatus',
        statusKey: 'status',
        columns: [
          { key: 'cycle.cycleName', label: '考核周期', minWidth: 150 },
          { key: 'employee.employeeName', label: '员工', minWidth: 120 },
          { key: 'totalScore', label: '总分', width: 90 },
          { key: 'performanceLevel', label: '等级', width: 100, dictCode: 'hrPerformanceLevel' },
          { key: 'status', label: '状态', width: 110, dictCode: 'hrPerformanceReviewStatus' }
        ],
        fields: [
          {
            key: 'cycleId',
            label: '考核周期',
            type: 'select',
            required: true,
            optionEntity: 'performanceCycle',
            optionLabelKeys: ['cycleCode', 'cycleName']
          },
          employeeField(),
          number('totalScore', '总分'),
          dict('performanceLevel', '绩效等级', 'hrPerformanceLevel'),
          dict('status', '考核状态', 'hrPerformanceReviewStatus', true),
          {
            ...input('employeeSummary', '员工总结'),
            span: 24,
            props: { type: 'textarea', rows: 3 }
          },
          {
            ...input('reviewerComment', '主管评价'),
            span: 24,
            props: { type: 'textarea', rows: 3 }
          }
        ],
        defaults: { status: 'draft' }
      },
      {
        key: 'goals',
        label: '考核目标',
        entity: 'performanceGoal',
        columns: [
          { key: 'goalName', label: '目标名称', minWidth: 180 },
          { key: 'targetDescription', label: '目标标准', minWidth: 220 },
          { key: 'weight', label: '权重', width: 90, suffix: '%' },
          { key: 'actualResult', label: '实际结果', minWidth: 180 },
          { key: 'score', label: '得分', width: 90 }
        ],
        fields: [
          {
            key: 'reviewId',
            label: '员工考核',
            type: 'select',
            required: true,
            optionEntity: 'performanceReview',
            optionLabelKeys: ['employee.employeeName', 'cycle.cycleName']
          },
          input('goalName', '目标名称', true),
          {
            ...input('targetDescription', '目标标准', true),
            span: 24,
            props: { type: 'textarea', rows: 2 }
          },
          number('weight', '权重（%）', true),
          number('score', '得分'),
          input('evidenceSource', '证据来源'),
          { ...input('actualResult', '实际结果'), span: 24, props: { type: 'textarea', rows: 2 } }
        ],
        defaults: { weight: 0 }
      }
    ]
  },
  talent: {
    eyebrow: 'TALENT DEVELOPMENT',
    title: '培训与能力',
    icon: 'ri:book-open-line',
    description: '从培训计划延伸到参与结果、岗位能力要求与员工能力评估，形成发展闭环。',
    tags: ['培训计划', '能力矩阵', '岗位匹配'],
    tabs: [
      {
        key: 'plans',
        label: '培训计划',
        entity: 'trainingPlan',
        statusDict: 'hrTrainingPlanStatus',
        statusKey: 'status',
        columns: [
          { key: 'planCode', label: '计划编码', width: 140 },
          { key: 'planName', label: '计划名称', minWidth: 180 },
          { key: 'trainingType', label: '培训类型', width: 120, dictCode: 'hrTrainingType' },
          { key: 'startDate', label: '开始日期', width: 120 },
          { key: 'budget', label: '预算', width: 110 },
          { key: 'status', label: '状态', width: 110, dictCode: 'hrTrainingPlanStatus' }
        ],
        fields: [
          input('planCode', '计划编码', true),
          input('planName', '计划名称', true),
          dict('trainingType', '培训类型', 'hrTrainingType', true),
          date('startDate', '开始日期', true),
          date('endDate', '结束日期'),
          input('providerName', '培训机构'),
          number('budget', '预算'),
          dict('status', '计划状态', 'hrTrainingPlanStatus', true),
          { ...input('objective', '培训目标'), span: 24, props: { type: 'textarea', rows: 3 } }
        ],
        defaults: { status: 'draft' }
      },
      {
        key: 'enrollments',
        label: '培训参与',
        entity: 'trainingEnrollment',
        statusDict: 'hrTrainingEnrollmentStatus',
        statusKey: 'status',
        columns: [
          { key: 'plan.planName', label: '培训计划', minWidth: 160 },
          { key: 'employee.employeeName', label: '员工', minWidth: 120 },
          { key: 'status', label: '参与状态', width: 110, dictCode: 'hrTrainingEnrollmentStatus' },
          { key: 'score', label: '成绩', width: 90 },
          { key: 'certificateNo', label: '证书编号', minWidth: 140 }
        ],
        fields: [
          {
            key: 'planId',
            label: '培训计划',
            type: 'select',
            required: true,
            optionEntity: 'trainingPlan',
            optionLabelKeys: ['planCode', 'planName']
          },
          employeeField(),
          dict('status', '参与状态', 'hrTrainingEnrollmentStatus', true),
          number('score', '成绩'),
          input('result', '培训结果'),
          input('certificateNo', '证书编号'),
          input('remark', '备注')
        ],
        defaults: { status: 'enrolled' }
      },
      {
        key: 'competencies',
        label: '能力字典',
        entity: 'competency',
        columns: [
          { key: 'competencyCode', label: '能力编码', width: 140 },
          { key: 'competencyName', label: '能力名称', minWidth: 160 },
          { key: 'category', label: '能力类别', width: 120, dictCode: 'hrCompetencyCategory' },
          { key: 'enabled', label: '启用', width: 90, dictCode: 'commonBoolean' },
          { key: 'description', label: '说明', minWidth: 220 }
        ],
        fields: [
          input('competencyCode', '能力编码', true),
          input('competencyName', '能力名称', true),
          dict('category', '能力类别', 'hrCompetencyCategory', true),
          { key: 'enabled', label: '启用', type: 'switch' },
          { ...input('description', '能力说明'), span: 24, props: { type: 'textarea', rows: 3 } }
        ],
        defaults: { enabled: true }
      },
      {
        key: 'positionMatrix',
        label: '岗位能力',
        entity: 'positionCompetency',
        columns: [
          { key: 'position.positionName', label: '岗位', minWidth: 150 },
          { key: 'competency.competencyName', label: '能力项', minWidth: 160 },
          { key: 'requiredLevel', label: '要求等级', width: 120, dictCode: 'hrCompetencyLevel' },
          { key: 'weight', label: '权重', width: 90, suffix: '%' }
        ],
        fields: [
          positionField('positionId', '岗位'),
          {
            key: 'competencyId',
            label: '能力项',
            type: 'select',
            required: true,
            optionEntity: 'competency',
            optionLabelKeys: ['competencyCode', 'competencyName']
          },
          dict('requiredLevel', '要求等级', 'hrCompetencyLevel', true),
          number('weight', '权重（%）')
        ],
        defaults: { weight: 0 }
      },
      {
        key: 'employeeMatrix',
        label: '员工能力',
        entity: 'employeeCompetency',
        columns: [
          { key: 'employee.employeeName', label: '员工', minWidth: 120 },
          { key: 'competency.competencyName', label: '能力项', minWidth: 160 },
          { key: 'currentLevel', label: '当前等级', width: 120, dictCode: 'hrCompetencyLevel' },
          { key: 'assessedDate', label: '评估日期', width: 120 },
          { key: 'evidence', label: '评估依据', minWidth: 200 }
        ],
        fields: [
          employeeField(),
          {
            key: 'competencyId',
            label: '能力项',
            type: 'select',
            required: true,
            optionEntity: 'competency',
            optionLabelKeys: ['competencyCode', 'competencyName']
          },
          dict('currentLevel', '当前等级', 'hrCompetencyLevel', true),
          date('assessedDate', '评估日期', true),
          { ...input('evidence', '评估依据'), span: 24, props: { type: 'textarea', rows: 3 } }
        ],
        defaults: { assessedDate: new Date().toISOString().slice(0, 10) }
      }
    ]
  },
  recruitment: {
    eyebrow: 'RECRUITMENT PIPELINE',
    title: '招聘工作台',
    icon: 'ri:user-add-line',
    description: '从招聘需求审批到候选人筛选、面试、Offer 和入职转化，形成可追踪招聘漏斗。',
    tags: ['需求审批', '候选人阶段', '入职转化'],
    tabs: [
      {
        key: 'requisitions',
        label: '招聘需求',
        entity: 'recruitmentRequisition',
        statusDict: 'hrRecruitmentStatus',
        statusKey: 'status',
        approvalBusinessType: 'hr_recruitment_requisition',
        canEffect: true,
        columns: [
          { key: 'requisitionNo', label: '需求编号', width: 150 },
          { key: 'organization.organizationName', label: '组织', minWidth: 140 },
          { key: 'position.positionName', label: '岗位', minWidth: 140 },
          { key: 'openingCount', label: '需求人数', width: 100 },
          { key: 'hiredCount', label: '已录用', width: 90 },
          { key: 'expectedOnboardDate', label: '期望到岗', width: 120 },
          { key: 'status', label: '状态', width: 110, dictCode: 'hrRecruitmentStatus' }
        ],
        fields: [
          input('requisitionNo', '需求编号', true),
          organizationField('organizationId', '招聘组织'),
          positionField('positionId', '招聘岗位'),
          number('openingCount', '需求人数', true),
          number('hiredCount', '已录用人数'),
          date('expectedOnboardDate', '期望到岗日期'),
          dict('employmentType', '用工类型', 'hrEmploymentType', true),
          { ...input('reason', '招聘原因', true), span: 24, props: { type: 'textarea', rows: 3 } },
          { ...input('requirements', '任职要求'), span: 24, props: { type: 'textarea', rows: 3 } }
        ],
        defaults: { status: 'draft', openingCount: 1, hiredCount: 0, employmentType: 'full_time' }
      },
      {
        key: 'candidates',
        label: '候选人',
        entity: 'candidate',
        statusDict: 'hrCandidateStage',
        statusKey: 'stage',
        columns: [
          { key: 'candidateName', label: '候选人', minWidth: 120 },
          { key: 'requisition.requisitionNo', label: '招聘需求', minWidth: 150 },
          { key: 'phone', label: '联系电话', width: 130 },
          { key: 'source', label: '来源', width: 110, dictCode: 'hrCandidateSource' },
          { key: 'stage', label: '阶段', width: 110, dictCode: 'hrCandidateStage' },
          { key: 'expectedSalary', label: '期望薪资', width: 110 }
        ],
        fields: [
          {
            key: 'requisitionId',
            label: '招聘需求',
            type: 'select',
            required: true,
            optionEntity: 'recruitmentRequisition',
            optionLabelKeys: ['requisitionNo', 'position.positionName']
          },
          input('candidateName', '候选人姓名', true),
          input('phone', '联系电话'),
          input('email', '电子邮箱'),
          dict('source', '候选人来源', 'hrCandidateSource', true),
          dict('stage', '候选人阶段', 'hrCandidateStage', true),
          number('expectedSalary', '期望薪资'),
          input('resumeUrl', '简历附件地址'),
          date('offerDate', 'Offer 日期'),
          {
            ...input('interviewFeedback', '面试反馈'),
            span: 24,
            props: { type: 'textarea', rows: 3 }
          },
          { ...input('remark', '备注'), span: 24, props: { type: 'textarea', rows: 2 } }
        ],
        defaults: { source: 'referral', stage: 'new' }
      }
    ]
  }
}
