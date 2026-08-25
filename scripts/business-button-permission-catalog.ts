export interface BusinessButtonDefinition {
  action: string
  title: string
  code?: string
}

export interface BusinessMenuButtonCatalogEntry {
  menuName: string
  buttons: BusinessButtonDefinition[]
}

const button = (action: string, title: string, code?: string): BusinessButtonDefinition => ({
  action,
  title,
  code
})

const crud = (
  options: {
    view?: boolean
    import?: boolean
    export?: boolean
  } = {}
): BusinessButtonDefinition[] => [
  ...(options.view ? [button('View', '查看')] : []),
  button('Add', '新增'),
  button('Edit', '编辑'),
  button('Delete', '删除'),
  ...(options.import ? [button('Import', '导入')] : []),
  ...(options.export ? [button('Export', '导出')] : [])
]

export const businessButtonPermissionCatalog: BusinessMenuButtonCatalogEntry[] = [
  { menuName: 'TmsCargo', buttons: crud({ import: true, export: true }) },
  { menuName: 'TmsCarrier', buttons: crud({ view: true, import: true, export: true }) },
  { menuName: 'TmsCarrierDetail', buttons: [button('AiAnalyze', 'AI 经营评估')] },
  { menuName: 'TmsCarrierPrice', buttons: crud({ view: true, export: true }) },
  { menuName: 'TmsCarrierPriceEdit', buttons: [button('Save', '保存承运商价')] },
  { menuName: 'TmsContract', buttons: crud({ view: true, export: true }) },
  { menuName: 'TmsCustomer', buttons: crud({ view: true, import: true, export: true }) },
  {
    menuName: 'TmsCustomerAddress',
    buttons: [...crud(), button('Geofence', '维护地址围栏')]
  },
  { menuName: 'TmsCustomerPrice', buttons: crud({ view: true, export: true }) },
  { menuName: 'TmsCustomerPriceEdit', buttons: [button('Save', '保存客户价')] },
  { menuName: 'TmsDriver', buttons: crud() },
  { menuName: 'TmsFavoriteRoute', buttons: crud() },
  {
    menuName: 'TmsStation',
    buttons: [...crud({ import: true, export: true }), button('Toggle', '启停站点')]
  },
  {
    menuName: 'TmsOrderOpen',
    buttons: [
      button('Create', '开单'),
      button('AiFill', 'AI 智能填单'),
      button('PrintWaybill', '打印运单'),
      button('PrintLabel', '打印标签'),
      button('DoublePrint', '运单标签双打')
    ]
  },
  {
    menuName: 'TmsOrderList',
    buttons: [
      button('View', '查看'),
      button('Edit', '编辑'),
      button('Delete', '删除'),
      button('Cancel', '取消订单'),
      button('EditFreight', '修改运费'),
      button('AddExpense', '新增费用'),
      button('Export', '导出')
    ]
  },
  {
    menuName: 'TmsPendingWaybillList',
    buttons: [
      button('View', '查看'),
      button('Dispatch', '配载调度'),
      button('Cancel', '取消订单'),
      button('Export', '导出')
    ]
  },
  {
    menuName: 'TmsLoadedWaybillList',
    buttons: [
      button('View', '查看'),
      button('Export', '导出'),
      button('Print', '打印'),
      button('Accept', '确认接单', 'TmsWaybill:Accept'),
      button('Loading', '装货', 'TmsWaybill:Loading'),
      button('Depart', '确认发车', 'TmsWaybill:Depart'),
      button('Arrive', '确认到达', 'TmsWaybill:Arrive'),
      button('Unloading', '卸货', 'TmsWaybill:Unloading'),
      button('Sign', '签收', 'TmsWaybill:Sign'),
      button('Complete', '确认完成', 'TmsWaybill:Complete'),
      button('Cancel', '取消运单', 'TmsWaybill:Cancel')
    ]
  },
  {
    menuName: 'TmsDeliveryManagement',
    buttons: [
      button('View', '查看'),
      button('ArchiveReceipt', '归档回单'),
      button('OcrReceipt', 'AI 回单识别'),
      button('ManageException', '处理回单异常')
    ]
  },
  {
    menuName: 'TmsInTransitMonitor',
    buttons: [
      button('View', '查看监控详情'),
      button('AiAnalyze', 'AI 运输异常分析'),
      button('ContactDriver', '联系司机'),
      button('SendReminder', '发送在途提醒')
    ]
  },
  {
    menuName: 'TmsTransportEvent',
    buttons: [button('View', '查看运输事件')]
  },
  {
    menuName: 'TmsRoutePerformance',
    buttons: [button('View', '查看线路效能')]
  },

  { menuName: 'InsuranceCompany', buttons: crud({ import: true, export: true }) },
  { menuName: 'Parts', buttons: crud({ import: true, export: true }) },
  { menuName: 'PartsCategory', buttons: crud({ import: true, export: true }) },
  { menuName: 'Supplier', buttons: crud({ import: true, export: true }) },
  {
    menuName: 'VehicleArchiveManage',
    buttons: crud({ view: true }).map((item) => ({
      ...item,
      code: `VehicleArchive:${item.action}`
    }))
  },
  {
    menuName: 'VehicleAccident',
    buttons: crud({ view: true, export: true }).map((item) => ({
      ...item,
      code: `VehicleAccident:${item.action}`
    }))
  },
  {
    menuName: 'VehicleMaintenance',
    buttons: crud({ view: true, export: true }).map((item) => ({
      ...item,
      code: `VehicleMaintenance:${item.action}`
    }))
  },
  {
    menuName: 'VehiclePartsManage',
    buttons: crud({ view: true }).map((item) => ({
      ...item,
      code: `VehiclePartUsage:${item.action}`
    }))
  },
  {
    menuName: 'VehicleRoutineInspection',
    buttons: crud({ view: true, export: true }).map((item) => ({
      ...item,
      code: `VehicleRoutineInspection:${item.action}`
    }))
  },
  {
    menuName: 'VehicleInspection',
    buttons: crud({ export: true }).map((item) => ({
      ...item,
      code: `VehicleInspection:${item.action}`
    }))
  },
  {
    menuName: 'VehicleInsurance',
    buttons: crud({ view: true, export: true }).map((item) => ({
      ...item,
      code: `VehicleInsurance:${item.action}`
    }))
  },
  {
    menuName: 'VehicleMileage',
    buttons: [button('Export', '导出', 'VehicleMileage:Export')]
  },
  {
    menuName: 'VehicleViolation',
    buttons: [button('Export', '导出', 'VehicleViolation:Export')]
  },
  ...[
    'VehicleInspectionExpiry',
    'VehicleInsuranceExpiry',
    'VehicleMaintenanceExpiry',
    'VehiclePartServiceLife',
    'VehicleServiceLife'
  ].map((menuName) => ({
    menuName,
    buttons: [
      button('View', '查看工单'),
      button('CreateWorkOrder', '创建工单'),
      button('TransitionWorkOrder', '处理工单')
    ]
  })),
  {
    menuName: 'VehicleQuery',
    buttons: [button('View', '查看'), button('AiAnalyze', 'AI 健康分析')]
  },
  {
    menuName: 'VehicleFleetHealth',
    buttons: [button('View', '查看车队健康', 'VehicleFleetHealth:View')]
  },

  {
    menuName: 'TmsCapacityPlanning',
    buttons: [button('View', '查看运力容量', 'TmsCapacityPlanning:View')]
  },
  {
    menuName: 'FinanceExceptionCenter',
    buttons: [button('View', '查看财务异常', 'FinanceExceptionCenter:View')]
  },
  {
    menuName: 'HrSkillMatrix',
    buttons: [button('View', '查看技能矩阵', 'Hr:SkillMatrix:View')]
  },

  {
    menuName: 'SmisPositionSafetyResponsibility',
    buttons: [
      button('View', '查看岗位安全责任制', 'SmisPositionSafetyResponsibility:View'),
      button('Add', '新增隐患排查标准', 'SmisPositionSafetyResponsibility:Add'),
      button('Edit', '编辑隐患排查标准', 'SmisPositionSafetyResponsibility:Edit'),
      button('Delete', '删除隐患排查标准', 'SmisPositionSafetyResponsibility:Delete'),
      button('Import', '导入隐患排查标准', 'SmisPositionSafetyResponsibility:Import'),
      button(
        'DownloadTemplate',
        '下载导入模板',
        'SmisPositionSafetyResponsibility:DownloadTemplate'
      )
    ]
  },
  {
    menuName: 'SmisPositionRiskList',
    buttons: [
      button('View', '查看岗位风险清单', 'SmisPositionRiskList:View'),
      button('Add', '新增隐患控制措施', 'SmisPositionRiskList:Add'),
      button('Edit', '编辑隐患控制措施', 'SmisPositionRiskList:Edit'),
      button('Delete', '删除隐患控制措施', 'SmisPositionRiskList:Delete')
    ]
  },
  {
    menuName: 'SmisPositionWorkInstruction',
    buttons: [
      button('View', '查看岗位作业指导书', 'SmisPositionWorkInstruction:View'),
      button('Add', '新增岗位作业指导书', 'SmisPositionWorkInstruction:Add'),
      button('Edit', '编辑岗位作业指导书', 'SmisPositionWorkInstruction:Edit'),
      button('Delete', '删除岗位作业指导书', 'SmisPositionWorkInstruction:Delete')
    ]
  },
  {
    menuName: 'SmisLeaveInformation',
    buttons: [
      button('View', '查看请假信息', 'SmisLeaveInformation:View'),
      button('Add', '新增请假信息', 'SmisLeaveInformation:Add'),
      button('Edit', '编辑请假信息', 'SmisLeaveInformation:Edit'),
      button('Delete', '删除请假信息', 'SmisLeaveInformation:Delete'),
      button('Export', '导出请假信息', 'SmisLeaveInformation:Export')
    ]
  },

  {
    menuName: 'HrEmployeeRoster',
    buttons: [
      button('View', '查看员工', 'Hr:Employee:View'),
      button('Add', '新增员工', 'Hr:Employee:Add'),
      button('Edit', '编辑员工', 'Hr:Employee:Edit'),
      button('Delete', '删除员工', 'Hr:Employee:Delete')
    ]
  },
  {
    menuName: 'HrOrganizationPosition',
    buttons: [button('View', '查看组织岗位人员', 'Hr:OrganizationPosition:View')]
  },
  {
    menuName: 'HrPosition',
    buttons: [
      button('View', '查看岗位', 'Hr:Position:View'),
      button('Add', '新增岗位', 'Hr:Position:Add'),
      button('Edit', '编辑岗位', 'Hr:Position:Edit'),
      button('Delete', '删除岗位', 'Hr:Position:Delete')
    ]
  },
  {
    menuName: 'HrJobArchitecture',
    buttons: [
      button('JobFamilyView', '查看职族', 'Hr:JobFamily:View'),
      button('JobFamilyAdd', '新增职族', 'Hr:JobFamily:Add'),
      button('JobFamilyEdit', '编辑职族', 'Hr:JobFamily:Edit'),
      button('JobFamilyDelete', '删除职族', 'Hr:JobFamily:Delete'),
      button('GradeView', '查看职级', 'Hr:Grade:View'),
      button('GradeAdd', '新增职级', 'Hr:Grade:Add'),
      button('GradeEdit', '编辑职级', 'Hr:Grade:Edit'),
      button('GradeDelete', '删除职级', 'Hr:Grade:Delete'),
      button('JobProfileView', '查看标准职务', 'Hr:JobProfile:View'),
      button('JobProfileAdd', '新增标准职务', 'Hr:JobProfile:Add'),
      button('JobProfileEdit', '编辑标准职务', 'Hr:JobProfile:Edit'),
      button('JobProfileDelete', '删除标准职务', 'Hr:JobProfile:Delete')
    ]
  },
  {
    menuName: 'HrPersonnelChange',
    buttons: [
      button('View', '查看异动', 'Hr:PersonnelChange:View'),
      button('Add', '新增异动', 'Hr:PersonnelChange:Add'),
      button('Edit', '编辑异动', 'Hr:PersonnelChange:Edit'),
      button('Delete', '删除异动', 'Hr:PersonnelChange:Delete'),
      button('Submit', '提交审批', 'Hr:PersonnelChange:Submit'),
      button('Effect', '生效异动', 'Hr:PersonnelChange:Effect')
    ]
  },
  {
    menuName: 'HrLifecycle',
    buttons: [
      button('View', '查看事项', 'Hr:Lifecycle:View'),
      button('Add', '新增事项', 'Hr:Lifecycle:Add'),
      button('Edit', '编辑事项', 'Hr:Lifecycle:Edit'),
      button('Delete', '删除事项', 'Hr:Lifecycle:Delete'),
      button('Submit', '提交审批', 'Hr:Lifecycle:Submit'),
      button('CompleteTask', '完成任务', 'Hr:Lifecycle:CompleteTask'),
      button('Start', '启动或推进事项', 'Hr:Lifecycle:Start'),
      button('CompleteCase', '办结生命周期事项', 'Hr:Lifecycle:CompleteCase'),
      button('WaiveTask', '豁免生命周期任务', 'Hr:Lifecycle:WaiveTask'),
      button('ManageTemplate', '管理标准任务包', 'Hr:Lifecycle:ManageTemplate')
    ]
  },
  {
    menuName: 'HrCompliance',
    buttons: [
      button('View', '查看合同资质', 'Hr:Compliance:View'),
      button('Add', '新增资质', 'Hr:Compliance:Add'),
      button('Edit', '编辑合同资质', 'Hr:Compliance:Edit'),
      button('Delete', '删除资质', 'Hr:Compliance:Delete')
    ]
  },
  {
    menuName: 'HrHeadcount',
    buttons: [
      button('View', '查看人力规划与编制', 'Hr:Headcount:View'),
      button('Add', '新增规划或有效编制', 'Hr:Headcount:Add'),
      button('Edit', '编辑规划或有效编制', 'Hr:Headcount:Edit'),
      button('Delete', '删除规划或有效编制', 'Hr:Headcount:Delete'),
      button('Submit', '提交人力规划', 'Hr:Headcount:Submit'),
      button('Approve', '审批人力规划', 'Hr:Headcount:Approve'),
      button('Activate', '启用人力规划', 'Hr:Headcount:Activate'),
      button('Close', '关闭人力规划', 'Hr:Headcount:Close')
    ]
  },
  {
    menuName: 'HrCompensation',
    buttons: [
      button('View', '查看薪酬管理', 'Hr:Compensation:View'),
      button('PolicyAdd', '新增薪酬政策', 'Hr:Compensation:Policy:Add'),
      button('PolicyEdit', '编辑薪酬政策', 'Hr:Compensation:Policy:Edit'),
      button('PolicyDelete', '删除薪酬政策', 'Hr:Compensation:Policy:Delete'),
      button('RecordAdd', '新增员工薪酬', 'Hr:Compensation:Record:Add'),
      button('RecordEdit', '编辑员工薪酬', 'Hr:Compensation:Record:Edit'),
      button('RecordDelete', '删除员工薪酬', 'Hr:Compensation:Record:Delete'),
      button('AmountView', '查看薪酬金额', 'Hr:Compensation:Amount:View'),
      button('AmountEdit', '编辑薪酬金额', 'Hr:Compensation:Amount:Edit'),
      button('Approve', '批准与终止薪酬', 'Hr:Compensation:Approve')
    ]
  },
  {
    menuName: 'HrAbsence',
    buttons: [
      button('View', '查看假勤管理', 'Hr:Absence:View'),
      button('PolicyAdd', '新增假别与政策', 'Hr:Absence:Policy:Add'),
      button('PolicyEdit', '编辑假别与政策', 'Hr:Absence:Policy:Edit'),
      button('PolicyDelete', '删除假别与政策', 'Hr:Absence:Policy:Delete'),
      button('BalanceAdjust', '调整休假余额', 'Hr:Absence:Balance:Adjust'),
      button('RequestAdd', '新增休假申请', 'Hr:Absence:Request:Add'),
      button('RequestEdit', '编辑休假申请', 'Hr:Absence:Request:Edit'),
      button('RequestDelete', '删除休假申请', 'Hr:Absence:Request:Delete'),
      button('Submit', '提交与撤销休假', 'Hr:Absence:Submit'),
      button('Approve', '审批休假申请', 'Hr:Absence:Approve'),
      button('ReasonView', '查看休假原因与证明', 'Hr:Absence:Reason:View')
    ]
  },
  {
    menuName: 'HrWorkforceRisk',
    buttons: [button('View', '查看人力风险', 'Hr:WorkforceRisk:View')]
  },
  {
    menuName: 'HrTalentInventory',
    buttons: [button('View', '查看人才盘点', 'Hr:TalentInventory:View')]
  },
  {
    menuName: 'HrSuccession',
    buttons: [
      button('View', '查看继任规划', 'Hr:Succession:View'),
      button('PlanAdd', '新增继任计划', 'Hr:Succession:Plan:Add'),
      button('PlanEdit', '编辑继任计划', 'Hr:Succession:Plan:Edit'),
      button('PlanDelete', '删除继任计划', 'Hr:Succession:Plan:Delete'),
      button('CandidateAdd', '提名继任候选人', 'Hr:Succession:Candidate:Add'),
      button('CandidateEdit', '编辑继任候选人', 'Hr:Succession:Candidate:Edit'),
      button('CandidateDelete', '删除继任候选人', 'Hr:Succession:Candidate:Delete'),
      button('CandidateReview', '评审继任候选人', 'Hr:Succession:Candidate:Review'),
      button('ActionAdd', '新增发展行动', 'Hr:Succession:Action:Add'),
      button('ActionEdit', '编辑发展行动', 'Hr:Succession:Action:Edit'),
      button('ActionDelete', '删除发展行动', 'Hr:Succession:Action:Delete')
    ]
  },
  {
    menuName: 'HrAttendance',
    buttons: [
      button('View', '查看考勤', 'Hr:Attendance:View'),
      button('Add', '新增考勤排班', 'Hr:Attendance:Add'),
      button('Edit', '编辑考勤排班', 'Hr:Attendance:Edit'),
      button('Delete', '删除考勤排班', 'Hr:Attendance:Delete'),
      button('Evaluate', '执行工时核算', 'Hr:Attendance:Evaluate'),
      button('ReviewCorrection', '审核考勤修正', 'Hr:Attendance:ReviewCorrection'),
      button('ClosePeriod', '考勤期间封账', 'Hr:Attendance:ClosePeriod')
    ]
  },
  {
    menuName: 'HrSelfService',
    buttons: [
      button('View', '查看员工申请', 'Hr:SelfService:View'),
      button('Add', '新增员工申请', 'Hr:SelfService:Add'),
      button('Edit', '编辑员工申请', 'Hr:SelfService:Edit'),
      button('Delete', '删除员工申请', 'Hr:SelfService:Delete'),
      button('Submit', '提交员工申请', 'Hr:SelfService:Submit')
    ]
  },
  {
    menuName: 'HrPerformance',
    buttons: [
      button('View', '查看绩效', 'Hr:Performance:View'),
      button('Add', '新增绩效', 'Hr:Performance:Add'),
      button('Edit', '编辑绩效', 'Hr:Performance:Edit'),
      button('Delete', '删除绩效', 'Hr:Performance:Delete'),
      button('Activate', '启动或取消绩效周期', 'Hr:Performance:Activate'),
      button('Review', '提交绩效评价', 'Hr:Performance:Review'),
      button('Calibrate', '维护绩效校准结果', 'Hr:Performance:Calibrate'),
      button('Complete', '定案绩效结果', 'Hr:Performance:Complete')
    ]
  },
  {
    menuName: 'HrTalentDevelopment',
    buttons: [
      button('View', '查看人才发展', 'Hr:Talent:View'),
      button('Add', '新增人才发展记录', 'Hr:Talent:Add'),
      button('Edit', '编辑人才发展记录', 'Hr:Talent:Edit'),
      button('Delete', '删除人才发展记录', 'Hr:Talent:Delete'),
      button('PlanTransition', '推进培养计划', 'Hr:Talent:Plan:Transition'),
      button('CourseAdd', '新增课程', 'Hr:Talent:Course:Add'),
      button('CourseEdit', '编辑课程', 'Hr:Talent:Course:Edit'),
      button('CoursePublish', '发布与停用课程', 'Hr:Talent:Course:Publish'),
      button('CourseCompetency', '维护课程能力映射', 'Hr:Talent:Course:Competency'),
      button('SessionAdd', '新增培训班次', 'Hr:Talent:Session:Add'),
      button('SessionEdit', '编辑培训班次', 'Hr:Talent:Session:Edit'),
      button('SessionTransition', '推进培训班次', 'Hr:Talent:Session:Transition'),
      button('EnrollmentAdd', '安排员工学习', 'Hr:Talent:Enrollment:Add'),
      button('EnrollmentManage', '登记学习结果', 'Hr:Talent:Enrollment:Manage'),
      button('CertificateManage', '管理学习证书', 'Hr:Talent:Certificate:Manage')
    ]
  },
  {
    menuName: 'HrRecruitment',
    buttons: [
      button('View', '查看招聘', 'Hr:Recruitment:View'),
      button('Add', '新增招聘记录', 'Hr:Recruitment:Add'),
      button('Edit', '编辑招聘记录', 'Hr:Recruitment:Edit'),
      button('Delete', '删除招聘记录', 'Hr:Recruitment:Delete'),
      button('Submit', '提交招聘审批', 'Hr:Recruitment:Submit'),
      button('Effect', '启动招聘', 'Hr:Recruitment:Effect'),
      button('CandidateMove', '推进候选人阶段', 'Hr:Recruitment:Candidate:Move'),
      button('SensitiveView', '查看招聘敏感信息', 'Hr:Recruitment:Sensitive:View'),
      button('InterviewAdd', '安排面试', 'Hr:Recruitment:Interview:Add'),
      button('InterviewEdit', '调整或取消面试', 'Hr:Recruitment:Interview:Edit'),
      button('InterviewComplete', '提交面试评价', 'Hr:Recruitment:Interview:Complete'),
      button('OfferAdd', '创建 Offer', 'Hr:Recruitment:Offer:Add'),
      button('OfferEdit', '编辑 Offer', 'Hr:Recruitment:Offer:Edit'),
      button('OfferSubmit', '提交 Offer 审批', 'Hr:Recruitment:Offer:Submit'),
      button('OfferApprove', '审批 Offer', 'Hr:Recruitment:Offer:Approve'),
      button('OfferSend', '发送或撤回 Offer', 'Hr:Recruitment:Offer:Send'),
      button('OfferRespond', '登记 Offer 反馈', 'Hr:Recruitment:Offer:Respond'),
      button('HandoffAdd', '创建入职交接', 'Hr:Recruitment:Handoff:Add'),
      button('HandoffEdit', '编辑入职交接', 'Hr:Recruitment:Handoff:Edit'),
      button('HandoffComplete', '推进入职交接', 'Hr:Recruitment:Handoff:Complete'),
      button('TaskManage', '管理入职任务', 'Hr:Recruitment:Task:Manage')
    ]
  },
  {
    menuName: 'FinanceAccountSet',
    buttons: [
      button('View', '查看会计期间'),
      button('Add', '新增账套'),
      button('Edit', '编辑账套'),
      button('Active', '启用账套'),
      button('Suspended', '停用账套'),
      button('Archived', '归档账套'),
      button('ManagePeriod', '维护会计期间')
    ]
  },
  {
    menuName: 'FinanceAccountingSubject',
    buttons: [
      button('Initialize', '初始化核算基础'),
      button('Add', '新增科目'),
      button('Edit', '编辑科目'),
      button('Toggle', '启停科目')
    ]
  },
  {
    menuName: 'FinanceAccountingAuxiliary',
    buttons: [
      button('AddType', '新增维度'),
      button('EditType', '编辑维度'),
      button('DeleteType', '删除维度'),
      button('Sync', '同步主数据'),
      button('Add', '新增核算项目'),
      button('Edit', '编辑核算项目'),
      button('Toggle', '启停核算项目')
    ]
  },
  {
    menuName: 'FinanceAccountingCurrency',
    buttons: [
      button('AddCurrency', '新增外币'),
      button('EditCurrency', '编辑币种'),
      button('Toggle', '启停币种'),
      button('Add', '新增汇率'),
      button('Edit', '编辑汇率')
    ]
  },
  {
    menuName: 'FinanceOpeningBalance',
    buttons: [
      button('Add', '录入余额'),
      button('Edit', '编辑余额'),
      button('Delete', '删除余额'),
      button('Confirm', '确认并锁定'),
      button('Reopen', '反确认')
    ]
  },
  {
    menuName: 'FinanceVoucherCenter',
    buttons: [
      button('View', '查看'),
      button('Add', '新增凭证'),
      button('Edit', '编辑凭证'),
      button('Export', '导出'),
      button('Submit', '提交'),
      button('Approve', '审核通过'),
      button('Reject', '驳回'),
      button('Post', '过账'),
      button('Void', '作废'),
      button('Reverse', '冲销')
    ]
  },
  { menuName: 'FinanceVoucherTemplate', buttons: crud() },
  {
    menuName: 'FinanceAutoPosting',
    buttons: [
      button('Add', '新增规则'),
      button('Edit', '编辑规则'),
      button('Delete', '删除规则'),
      button('ProcessPending', '批量处理待办'),
      button('Retry', '重试事件'),
      button('View', '查看事件')
    ]
  },
  {
    menuName: 'FinanceFinancialReports',
    buttons: [
      button('ViewConfig', '查看取数口径'),
      button('EditConfig', '维护取数口径'),
      button('Export', '导出')
    ]
  },
  {
    menuName: 'FinanceLedgerCenter',
    buttons: [button('View', '查看账簿'), button('Export', '导出')]
  },
  {
    menuName: 'FinanceFixedAsset',
    buttons: [
      button('Add', '新增资产'),
      button('Edit', '编辑资产'),
      button('Delete', '删除资产'),
      button('ManageCategory', '维护资产类别'),
      button('Activate', '确认转固'),
      button('Suspend', '暂停折旧'),
      button('Resume', '恢复使用'),
      button('Dispose', '资产处置'),
      button('Depreciation', '折旧管理')
    ]
  },
  {
    menuName: 'FinanceCommercialBill',
    buttons: [
      button('View', '查看'),
      button('Add', '新增票据'),
      button('Edit', '编辑票据'),
      button('Delete', '删除票据'),
      button('Receive', '确认收票'),
      button('Issue', '确认出票'),
      button('Endorse', '背书转让'),
      button('Discount', '票据贴现'),
      button('Settle', '到期结算'),
      button('Cancel', '取消票据')
    ]
  },
  {
    menuName: 'FinancePayroll',
    buttons: [
      button('View', '查看'),
      button('Add', '新增批次'),
      button('Edit', '编辑批次'),
      button('Calculate', '计算薪资'),
      button('Approve', '审批并计提'),
      button('Pay', '确认发放'),
      button('Cancel', '取消批次')
    ]
  },
  {
    menuName: 'FinanceTaxManagement',
    buttons: [
      button('View', '查看'),
      button('Add', '新增税务期间'),
      button('Edit', '编辑税务期间'),
      button('Calculate', '计算税额'),
      button('Review', '复核税额'),
      button('File', '确认申报'),
      button('Pay', '确认缴税'),
      button('Cancel', '取消期间')
    ]
  },
  {
    menuName: 'FinancePeriodClose',
    buttons: [
      button('View', '查看'),
      button('Add', '发起关账'),
      button('Carryforward', '生成损益结转凭证'),
      button('Recheck', '重新检查'),
      button('Close', '确认结账'),
      button('Cancel', '取消关账'),
      button('Reopen', '反结账')
    ]
  },
  { menuName: 'FinanceFundAccount', buttons: crud() },
  {
    menuName: 'FinanceCashForecast',
    buttons: [button('View', '查看资金预测')]
  },
  {
    menuName: 'FinanceReceivableAging',
    buttons: [button('View', '查看应收账龄')]
  },
  {
    menuName: 'FinanceFundTransfer',
    buttons: [
      button('View', '查看'),
      button('Add', '新增调拨'),
      button('Edit', '编辑调拨'),
      button('Delete', '删除调拨'),
      button('Submit', '提交审批'),
      button('Approve', '审批通过'),
      button('Reject', '驳回'),
      button('Execute', '执行入账'),
      button('Reverse', '冲销调拨')
    ]
  },
  {
    menuName: 'FinanceBankReconciliation',
    buttons: [
      button('Add', '导入银行流水'),
      button('View', '进入对账'),
      button('AutoMatch', '自动匹配'),
      button('Match', '手工匹配'),
      button('Unmatch', '取消匹配'),
      button('Ignore', '忽略流水'),
      button('Complete', '完成对账'),
      button('Void', '作废对账')
    ]
  },
  {
    menuName: 'FinanceCashTransaction',
    buttons: [
      button('Import', 'AI 批量导入流水'),
      button('Add', '登记客户收款'),
      button('CreatePayment', '发起承运商付款申请'),
      button('View', '查看'),
      button('Allocate', '继续核销'),
      button('Void', '作废收付款'),
      button('Export', '导出')
    ]
  },
  {
    menuName: 'FinanceInvoiceManagement',
    buttons: [
      button('View', '查看'),
      button('Add', '登记发票'),
      button('Edit', '编辑'),
      button('Delete', '删除'),
      button('Submit', '提交复核'),
      button('Approve', '审核通过'),
      button('Reject', '驳回'),
      button('Void', '作废'),
      button('AiAudit', 'AI 合规审核'),
      button('Export', '导出')
    ]
  },
  ...['FinanceCarrierSettlement', 'FinanceCustomerSettlement'].map((menuName) => ({
    menuName,
    buttons: [
      button('View', '查看'),
      button('Add', '生成对账单'),
      button('Submit', '提交审核'),
      button('Approve', '审核通过'),
      button('Reject', '驳回'),
      button('Void', '作废'),
      button('Delete', '删除'),
      button('Export', '导出')
    ]
  })),
  {
    menuName: 'FinanceCarrierPaymentApplication',
    buttons: [
      button('View', '查看'),
      button('Add', '新建付款申请'),
      button('Edit', '编辑'),
      button('Delete', '删除'),
      button('Submit', '提交审批'),
      button('ViewApproval', '查看审批'),
      button('Execute', '付款登记'),
      button('Cancel', '取消'),
      button('Export', '导出')
    ]
  },
  {
    menuName: 'FinanceWaybillCost',
    buttons: [
      button('View', '查看'),
      button('Add', '新增运单费用'),
      button('Edit', '编辑费用'),
      button('Delete', '删除费用'),
      button('Submit', '提交审核'),
      button('Convert', '转费用报销'),
      button('Pay', '出纳付款'),
      button('AiAudit', 'AI 费用审核'),
      button('OcrLogs', 'OCR 识别记录'),
      button('ApprovalHistory', '审批记录')
    ]
  },
  { menuName: 'FinanceExpenseItem', buttons: [...crud(), button('AddChild', '新增下级')] },
  {
    menuName: 'FinanceWaybillProfit',
    buttons: [button('AiProfitAnalysis', 'AI 利润诊断'), button('Export', '导出')]
  }
]

export const systemButtonPermissionCatalog: BusinessMenuButtonCatalogEntry[] = [
  { menuName: 'Organization', buttons: crud({ view: true }) },
  {
    menuName: 'Menu',
    buttons: [
      button('View', '查看菜单'),
      button('Add', '新增菜单'),
      button('Edit', '编辑菜单'),
      button('Delete', '删除菜单')
    ]
  },
  {
    menuName: 'Tenant',
    buttons: [button('Add', '新增租户'), button('Edit', '编辑租户'), button('Delete', '停用租户')]
  },
  {
    menuName: 'SystemParam',
    buttons: [
      button('Add', '新增参数', 'System:SystemParam:Add'),
      button('Edit', '编辑参数', 'System:SystemParam:Edit'),
      button('Delete', '删除参数', 'System:SystemParam:Delete')
    ]
  },
  {
    menuName: 'DocumentNumberRule',
    buttons: [
      button('Add', '新增编号规则', 'System:DocumentNumberRule:Add'),
      button('Edit', '编辑编号规则', 'System:DocumentNumberRule:Edit')
    ]
  },
  {
    menuName: 'User',
    buttons: [
      button('Add', '新增用户'),
      button('Edit', '编辑用户'),
      button('Delete', '注销用户'),
      button('AssignRole', '分配角色'),
      button('ResetPassword', '初始化密码')
    ]
  },
  {
    menuName: 'Role',
    buttons: [
      button('Add', '新增角色'),
      button('Edit', '编辑角色'),
      button('Delete', '删除角色'),
      button('AssignPermission', '配置菜单权限')
    ]
  },
  {
    menuName: 'WebsiteConfig',
    buttons: [button('Publish', '保存并发布配置')]
  },
  {
    menuName: 'AiConfiguration',
    buttons: [button('Edit', '编辑 AI 配置')]
  },
  {
    menuName: 'AiPrompt',
    buttons: [
      button('Add', '新建 Prompt 版本'),
      button('Edit', '编辑 Prompt 草稿'),
      button('Publish', '发布或回滚 Prompt'),
      button('Clone', '复制 Prompt 版本'),
      button('Delete', '删除 Prompt 草稿')
    ]
  },
  {
    menuName: 'AiProjectPlanner',
    buttons: [button('ManageWorkflow', '推进建议状态')]
  },
  {
    menuName: 'GeofenceConfig',
    buttons: [button('Edit', '编辑电子围栏')]
  },
  {
    menuName: 'FieldPermission',
    buttons: [button('Manage', '维护字段权限')]
  },
  {
    menuName: 'NotificationReminder',
    buttons: [
      button('View', '查看提醒配置'),
      button('AddRule', '新增提醒规则'),
      button('EditRule', '编辑提醒规则'),
      button('DeleteRule', '删除提醒规则'),
      button('EditChannel', '配置通知渠道'),
      button('TestChannel', '测试通知渠道'),
      button('Dispatch', '立即执行提醒')
    ]
  }
].map((entry) => ({
  ...entry,
  buttons: entry.buttons.map((definition) => ({
    ...definition,
    code: definition.code ?? `System:${entry.menuName}:${definition.action}`
  }))
}))

export const managedButtonPermissionCatalog = [
  ...businessButtonPermissionCatalog,
  ...systemButtonPermissionCatalog
]

export const resolveCatalogPermissionCode = (
  menuName: string,
  definition: BusinessButtonDefinition
): string => definition.code ?? `${menuName}:${definition.action}`
