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
    menuName: 'SmisStatutoryHoliday',
    buttons: [
      button('View', '查看法定节假日', 'SmisStatutoryHoliday:View'),
      button('Add', '新增法定节假日', 'SmisStatutoryHoliday:Add'),
      button('Edit', '编辑法定节假日', 'SmisStatutoryHoliday:Edit'),
      button('Delete', '删除法定节假日', 'SmisStatutoryHoliday:Delete'),
      button('Import', '导入法定节假日', 'SmisStatutoryHoliday:Import'),
      button('Export', '导出法定节假日', 'SmisStatutoryHoliday:Export')
    ]
  },
  {
    menuName: 'SmisSite',
    buttons: [
      button('View', '查看场所', 'SmisSite:View'),
      button('Add', '新增场所', 'SmisSite:Add'),
      button('Edit', '编辑场所', 'SmisSite:Edit'),
      button('Delete', '删除场所', 'SmisSite:Delete'),
      button('Import', '导入场所', 'SmisSite:Import'),
      button('Export', '导出场所', 'SmisSite:Export')
    ]
  },
  {
    menuName: 'SmisInspectionCategory',
    buttons: [
      button('View', '查看检验类别', 'SmisInspectionCategory:View'),
      button('Add', '新增检验类别', 'SmisInspectionCategory:Add'),
      button('Edit', '编辑检验类别', 'SmisInspectionCategory:Edit'),
      button('Delete', '删除检验类别', 'SmisInspectionCategory:Delete')
    ]
  },
  {
    menuName: 'SmisEquipmentCategory',
    buttons: [
      button('View', '查看设备分类', 'SmisEquipmentCategory:View'),
      button('Add', '新增设备分类', 'SmisEquipmentCategory:Add'),
      button('Edit', '编辑设备分类', 'SmisEquipmentCategory:Edit'),
      button('Delete', '删除设备分类', 'SmisEquipmentCategory:Delete')
    ]
  },
  {
    menuName: 'SmisMaterialCategory',
    buttons: [
      button('View', '查看物料类别', 'SmisMaterialCategory:View'),
      button('Add', '新增物料类别', 'SmisMaterialCategory:Add'),
      button('Edit', '编辑物料类别', 'SmisMaterialCategory:Edit'),
      button('Delete', '删除物料类别', 'SmisMaterialCategory:Delete')
    ]
  },
  {
    menuName: 'SmisMaterialInformation',
    buttons: [
      button('View', '查看物料信息', 'SmisMaterialInformation:View'),
      button('Add', '新增物料信息', 'SmisMaterialInformation:Add'),
      button('Edit', '编辑物料信息', 'SmisMaterialInformation:Edit'),
      button('Delete', '删除物料信息', 'SmisMaterialInformation:Delete'),
      button('Export', '导出物料信息', 'SmisMaterialInformation:Export')
    ]
  },
  {
    menuName: 'SmisPpeIssuanceStandard',
    buttons: [
      button('View', '查看发放标准', 'SmisPpeIssuanceStandard:View'),
      button('Add', '新增发放标准', 'SmisPpeIssuanceStandard:Add'),
      button('Edit', '编辑发放标准', 'SmisPpeIssuanceStandard:Edit'),
      button('Delete', '删除发放标准', 'SmisPpeIssuanceStandard:Delete'),
      button('Export', '导出发放标准', 'SmisPpeIssuanceStandard:Export')
    ]
  },
  {
    menuName: 'SmisPpePersonalStandard',
    buttons: [
      button('View', '查看个人标准', 'SmisPpePersonalStandard:View'),
      button('Generate', '生成个人标准', 'SmisPpePersonalStandard:Generate'),
      button('Schedule', '设置领用计划', 'SmisPpePersonalStandard:Schedule'),
      button('Export', '导出个人标准', 'SmisPpePersonalStandard:Export')
    ]
  },
  {
    menuName: 'SmisPpeIssuanceRecord',
    buttons: [
      button('View', '查看发放记录', 'SmisPpeIssuanceRecord:View'),
      button('Add', '新增发放记录', 'SmisPpeIssuanceRecord:Add'),
      button('Copy', '复制并新增', 'SmisPpeIssuanceRecord:Copy'),
      button('Edit', '编辑发放记录', 'SmisPpeIssuanceRecord:Edit'),
      button('Delete', '删除发放记录', 'SmisPpeIssuanceRecord:Delete'),
      button('Issue', '发放过账', 'SmisPpeIssuanceRecord:Issue'),
      button('Import', '导入发放记录', 'SmisPpeIssuanceRecord:Import'),
      button('DownloadTemplate', '下载导入模板', 'SmisPpeIssuanceRecord:DownloadTemplate'),
      button('Export', '导出发放记录', 'SmisPpeIssuanceRecord:Export'),
      button('Statistics', '发放统计分析', 'SmisPpeIssuanceRecord:Statistics'),
      button('Print', '打印劳保单', 'SmisPpeIssuanceRecord:Print')
    ]
  },
  {
    menuName: 'SmisPpePersonalRequisition',
    buttons: [
      button('View', '查看个人领用', 'SmisPpePersonalRequisition:View'),
      button('Generate', '生成到期领用单', 'SmisPpePersonalRequisition:Generate'),
      button('Push', '下推发放', 'SmisPpePersonalRequisition:Push'),
      button('Confirm', '确认本人领用', 'SmisPpePersonalRequisition:Confirm'),
      button('Export', '导出个人领用', 'SmisPpePersonalRequisition:Export'),
      button('Statistics', '个人领用统计', 'SmisPpePersonalRequisition:Statistics'),
      button('Configure', '配置自动确认', 'SmisPpePersonalRequisition:Configure')
    ]
  },
  {
    menuName: 'SmisToolIssuanceStandard',
    buttons: [
      button('View', '查看发放标准', 'SmisToolIssuanceStandard:View'),
      button('Add', '新增发放标准', 'SmisToolIssuanceStandard:Add'),
      button('Edit', '编辑发放标准', 'SmisToolIssuanceStandard:Edit'),
      button('Delete', '删除发放标准', 'SmisToolIssuanceStandard:Delete'),
      button('Export', '导出发放标准', 'SmisToolIssuanceStandard:Export')
    ]
  },
  {
    menuName: 'SmisToolPersonalStandard',
    buttons: [
      button('View', '查看个人标准', 'SmisToolPersonalStandard:View'),
      button('Generate', '生成个人标准', 'SmisToolPersonalStandard:Generate'),
      button('Schedule', '设置领用计划', 'SmisToolPersonalStandard:Schedule'),
      button('Export', '导出个人标准', 'SmisToolPersonalStandard:Export')
    ]
  },
  {
    menuName: 'SmisToolIssuanceRecord',
    buttons: [
      button('View', '查看发放记录', 'SmisToolIssuanceRecord:View'),
      button('Add', '新增发放记录', 'SmisToolIssuanceRecord:Add'),
      button('Copy', '复制并新增', 'SmisToolIssuanceRecord:Copy'),
      button('Edit', '编辑发放记录', 'SmisToolIssuanceRecord:Edit'),
      button('Delete', '删除发放记录', 'SmisToolIssuanceRecord:Delete'),
      button('Issue', '发放过账', 'SmisToolIssuanceRecord:Issue'),
      button('Import', '导入发放记录', 'SmisToolIssuanceRecord:Import'),
      button('DownloadTemplate', '下载导入模板', 'SmisToolIssuanceRecord:DownloadTemplate'),
      button('Export', '导出发放记录', 'SmisToolIssuanceRecord:Export'),
      button('Statistics', '发放统计分析', 'SmisToolIssuanceRecord:Statistics'),
      button('Print', '打印工器具发放单', 'SmisToolIssuanceRecord:Print')
    ]
  },
  {
    menuName: 'SmisToolPersonalRequisition',
    buttons: [
      button('View', '查看个人领用', 'SmisToolPersonalRequisition:View'),
      button('Generate', '生成到期领用单', 'SmisToolPersonalRequisition:Generate'),
      button('Push', '下推发放', 'SmisToolPersonalRequisition:Push'),
      button('Confirm', '确认本人领用', 'SmisToolPersonalRequisition:Confirm'),
      button('Export', '导出个人领用', 'SmisToolPersonalRequisition:Export'),
      button('Statistics', '个人领用统计', 'SmisToolPersonalRequisition:Statistics'),
      button('Configure', '配置自动确认', 'SmisToolPersonalRequisition:Configure')
    ]
  },
  {
    menuName: 'SmisToolRequisitionReturn',
    buttons: [
      button('View', '查看归还单', 'SmisToolRequisitionReturn:View'),
      button('Add', '新增归还单', 'SmisToolRequisitionReturn:Add'),
      button('Copy', '复制并新增', 'SmisToolRequisitionReturn:Copy'),
      button('Edit', '编辑归还单', 'SmisToolRequisitionReturn:Edit'),
      button('Delete', '删除归还单', 'SmisToolRequisitionReturn:Delete'),
      button('Return', '发起归还', 'SmisToolRequisitionReturn:Return'),
      button('Submit', '提交归还审批', 'SmisToolRequisitionReturn:Submit'),
      button('Export', '导出归还单', 'SmisToolRequisitionReturn:Export')
    ]
  },
  {
    menuName: 'SmisThreeViolationEducation',
    buttons: [
      button('View', '查看三违教育信息', 'SmisThreeViolationEducation:View'),
      button('Add', '新增三违人员信息', 'SmisThreeViolationEducation:Add'),
      button('Copy', '复制并新增', 'SmisThreeViolationEducation:Copy'),
      button('Edit', '编辑三违人员信息', 'SmisThreeViolationEducation:Edit'),
      button('Delete', '删除三违人员信息', 'SmisThreeViolationEducation:Delete'),
      button('RecordEducation', '记录教育信息', 'SmisThreeViolationEducation:RecordEducation'),
      button('Export', '导出三违教育信息', 'SmisThreeViolationEducation:Export'),
      button('Print', '打印安全教育台账', 'SmisThreeViolationEducation:Print')
    ]
  },
  {
    menuName: 'SmisViolationCategory',
    buttons: [
      button('View', '查看违章分类', 'SmisViolationCategory:View'),
      button('Add', '新增违章分类', 'SmisViolationCategory:Add'),
      button('Edit', '编辑违章分类', 'SmisViolationCategory:Edit'),
      button('Delete', '删除违章分类', 'SmisViolationCategory:Delete'),
      button('Export', '导出违章分类', 'SmisViolationCategory:Export')
    ]
  },
  {
    menuName: 'SmisWorkItem',
    buttons: [
      button('View', '查看作业项目', 'SmisWorkItem:View'),
      button('Add', '新增作业项目', 'SmisWorkItem:Add'),
      button('Edit', '编辑作业项目', 'SmisWorkItem:Edit'),
      button('Delete', '删除作业项目', 'SmisWorkItem:Delete'),
      button('Export', '导出作业项目', 'SmisWorkItem:Export')
    ]
  },
  {
    menuName: 'SmisWorkCategory',
    buttons: [
      button('View', '查看作业类别', 'SmisWorkCategory:View'),
      button('Add', '新增作业类别', 'SmisWorkCategory:Add'),
      button('Edit', '编辑作业类别', 'SmisWorkCategory:Edit'),
      button('Delete', '删除作业类别', 'SmisWorkCategory:Delete'),
      button('Export', '导出作业类别', 'SmisWorkCategory:Export')
    ]
  },
  {
    menuName: 'SmisPermittedOperationItem',
    buttons: [
      button('View', '查看准操项目', 'SmisPermittedOperationItem:View'),
      button('Add', '新增准操项目', 'SmisPermittedOperationItem:Add'),
      button('Edit', '编辑准操项目', 'SmisPermittedOperationItem:Edit'),
      button('Delete', '删除准操项目', 'SmisPermittedOperationItem:Delete'),
      button('Export', '导出准操项目', 'SmisPermittedOperationItem:Export')
    ]
  },
  {
    menuName: 'SmisSpecialEquipmentPersonnelCertificateLedger',
    buttons: [
      button('View', '查看人员证件台账', 'SmisPersonnelCertificateLedger:View'),
      button('Add', '新增人员证件', 'SmisPersonnelCertificateLedger:Add'),
      button('Copy', '复制并新增', 'SmisPersonnelCertificateLedger:Copy'),
      button('Edit', '编辑人员证件', 'SmisPersonnelCertificateLedger:Edit'),
      button('Delete', '删除人员证件', 'SmisPersonnelCertificateLedger:Delete'),
      button('Export', '导出人员证件台账', 'SmisPersonnelCertificateLedger:Export'),
      button('ViewHistory', '查看复审记录', 'SmisPersonnelCertificateLedger:ViewHistory')
    ]
  },
  {
    menuName: 'SmisSpecialEquipmentOperatorCertificateLedger',
    buttons: [
      button('View', '查看作业人员证件台账', 'SmisSpecialEquipmentOperatorCertificateLedger:View'),
      button('Add', '新增作业人员证件', 'SmisSpecialEquipmentOperatorCertificateLedger:Add'),
      button('Copy', '复制并新增', 'SmisSpecialEquipmentOperatorCertificateLedger:Copy'),
      button('Edit', '编辑作业人员证件', 'SmisSpecialEquipmentOperatorCertificateLedger:Edit'),
      button('Delete', '删除作业人员证件', 'SmisSpecialEquipmentOperatorCertificateLedger:Delete'),
      button(
        'Export',
        '导出作业人员证件台账',
        'SmisSpecialEquipmentOperatorCertificateLedger:Export'
      ),
      button(
        'ViewHistory',
        '查看作业人员复审记录',
        'SmisSpecialEquipmentOperatorCertificateLedger:ViewHistory'
      )
    ]
  },
  {
    menuName: 'SmisSpecialOperationCertificate',
    buttons: [
      button('View', '查看特种作业操作证', 'SmisSpecialOperationCertificate:View'),
      button('Add', '新增特种作业操作证', 'SmisSpecialOperationCertificate:Add'),
      button('Copy', '复制并新增', 'SmisSpecialOperationCertificate:Copy'),
      button('Edit', '编辑特种作业操作证', 'SmisSpecialOperationCertificate:Edit'),
      button('Delete', '删除特种作业操作证', 'SmisSpecialOperationCertificate:Delete'),
      button('Export', '导出特种作业操作证', 'SmisSpecialOperationCertificate:Export'),
      button('ViewHistory', '查看特种作业复审记录', 'SmisSpecialOperationCertificate:ViewHistory')
    ]
  },
  {
    menuName: 'SmisSafetyManagerCertificate',
    buttons: [
      button('View', '查看安全管理人员证', 'SmisSafetyManagerCertificate:View'),
      button('Add', '新增安全管理人员证', 'SmisSafetyManagerCertificate:Add'),
      button('Copy', '复制并新增', 'SmisSafetyManagerCertificate:Copy'),
      button('Edit', '编辑安全管理人员证', 'SmisSafetyManagerCertificate:Edit'),
      button('Delete', '删除安全管理人员证', 'SmisSafetyManagerCertificate:Delete'),
      button('Export', '导出安全管理人员证', 'SmisSafetyManagerCertificate:Export'),
      button(
        'ViewHistory',
        '查看安全管理人员证复审记录',
        'SmisSafetyManagerCertificate:ViewHistory'
      )
    ]
  },
  {
    menuName: 'SmisRegisteredSafetyEngineerLedger',
    buttons: [
      button('View', '查看注册安全工程师台账', 'SmisRegisteredSafetyEngineerLedger:View'),
      button('Add', '新增注册安全工程师证', 'SmisRegisteredSafetyEngineerLedger:Add'),
      button('Copy', '复制并新增', 'SmisRegisteredSafetyEngineerLedger:Copy'),
      button('Edit', '编辑注册安全工程师证', 'SmisRegisteredSafetyEngineerLedger:Edit'),
      button('Delete', '删除注册安全工程师证', 'SmisRegisteredSafetyEngineerLedger:Delete'),
      button('Export', '导出注册安全工程师台账', 'SmisRegisteredSafetyEngineerLedger:Export'),
      button(
        'ViewHistory',
        '查看注册安全工程师复审记录',
        'SmisRegisteredSafetyEngineerLedger:ViewHistory'
      )
    ]
  },
  {
    menuName: 'SmisSafetyQualificationReportAnalysis',
    buttons: [button('View', '查看安全资质报表分析', 'SmisSafetyQualificationReportAnalysis:View')]
  },
  {
    menuName: 'SmisAntiViolationStandardLibrary',
    buttons: [
      button('View', '查看反违章标准', 'SmisAntiViolationStandardLibrary:View'),
      button('Add', '新增反违章标准', 'SmisAntiViolationStandardLibrary:Add'),
      button('Edit', '编辑反违章标准', 'SmisAntiViolationStandardLibrary:Edit'),
      button('Delete', '删除反违章标准', 'SmisAntiViolationStandardLibrary:Delete'),
      button('Import', '导入反违章标准', 'SmisAntiViolationStandardLibrary:Import'),
      button('Export', '导出反违章标准', 'SmisAntiViolationStandardLibrary:Export')
    ]
  },
  {
    menuName: 'SmisViolationRecord',
    buttons: [
      button('View', '查看违章记录', 'SmisViolationRecord:View'),
      button('Add', '新增违章记录', 'SmisViolationRecord:Add'),
      button('Copy', '复制并新增', 'SmisViolationRecord:Copy'),
      button('Edit', '编辑违章记录', 'SmisViolationRecord:Edit'),
      button('Delete', '删除违章记录', 'SmisViolationRecord:Delete'),
      button('Export', '导出违章记录', 'SmisViolationRecord:Export')
    ]
  },
  {
    menuName: 'SmisAnnouncementCategory',
    buttons: [
      button('View', '查看公告分类', 'SmisAnnouncementCategory:View'),
      button('Add', '新增公告分类', 'SmisAnnouncementCategory:Add'),
      button('Edit', '编辑公告分类', 'SmisAnnouncementCategory:Edit'),
      button('Delete', '删除公告分类', 'SmisAnnouncementCategory:Delete'),
      button('Export', '导出公告分类', 'SmisAnnouncementCategory:Export')
    ]
  },
  {
    menuName: 'SmisViolationAnnouncement',
    buttons: [
      button('View', '查看公告', 'SmisViolationAnnouncement:View'),
      button('Add', '新建公告', 'SmisViolationAnnouncement:Add'),
      button('Edit', '编辑公告草稿', 'SmisViolationAnnouncement:Edit'),
      button('Delete', '删除公告草稿', 'SmisViolationAnnouncement:Delete'),
      button('Publish', '发布公告', 'SmisViolationAnnouncement:Publish'),
      button('Withdraw', '撤回公告', 'SmisViolationAnnouncement:Withdraw'),
      button('ReadStats', '查看查阅情况', 'SmisViolationAnnouncement:ReadStats')
    ]
  },
  {
    menuName: 'SmisStorageLocation',
    buttons: [
      button('View', '查看存放位置', 'SmisStorageLocation:View'),
      button('Add', '新增存放位置', 'SmisStorageLocation:Add'),
      button('Edit', '编辑存放位置', 'SmisStorageLocation:Edit'),
      button('Delete', '删除存放位置', 'SmisStorageLocation:Delete')
    ]
  },
  {
    menuName: 'SmisEquipmentLedgerList',
    buttons: [
      button('View', '查看设备台账', 'SmisEquipmentLedger:View'),
      button('Add', '新增设备', 'SmisEquipmentLedger:Add'),
      button('Edit', '编辑设备', 'SmisEquipmentLedger:Edit'),
      button('Delete', '删除设备', 'SmisEquipmentLedger:Delete'),
      button('Attachment', '维护设备附件', 'SmisEquipmentLedger:Attachment'),
      button('Inspection', '维护设备检验', 'SmisEquipmentLedger:Inspection')
    ]
  },
  {
    menuName: 'SmisEquipmentDepreciation',
    buttons: [
      button('View', '查看设备折旧', 'SmisEquipmentDepreciation:View'),
      button('Add', '新增设备折旧', 'SmisEquipmentDepreciation:Add'),
      button('Edit', '编辑设备折旧', 'SmisEquipmentDepreciation:Edit'),
      button('Delete', '删除设备折旧', 'SmisEquipmentDepreciation:Delete')
    ]
  },
  {
    menuName: 'SmisInspectionDeclaration',
    buttons: [
      button('View', '查看检验申报', 'SmisInspectionDeclaration:View'),
      button('Add', '新增检验申报', 'SmisInspectionDeclaration:Add'),
      button('Edit', '编辑检验申报', 'SmisInspectionDeclaration:Edit'),
      button('Delete', '删除检验申报', 'SmisInspectionDeclaration:Delete')
    ]
  },
  {
    menuName: 'SmisSpecialEquipmentAnalysis',
    buttons: [button('View', '查看特种设备统计', 'SmisSpecialEquipmentAnalysis:View')]
  },
  {
    menuName: 'SmisSpecialEquipmentLedger',
    buttons: [
      button('View', '查看特种设备台账', 'SmisSpecialEquipmentLedger:View'),
      button('ReminderView', '查看设备提醒', 'SmisEquipmentReminder:View'),
      button('ReminderManage', '维护设备提醒', 'SmisEquipmentReminder:Manage')
    ]
  },
  {
    menuName: 'SmisSupplier',
    buttons: [
      button('View', '查看供应商', 'SmisSupplier:View'),
      button('Add', '新增供应商', 'SmisSupplier:Add'),
      button('Edit', '编辑供应商', 'SmisSupplier:Edit'),
      button('Delete', '删除供应商', 'SmisSupplier:Delete'),
      button('Export', '导出供应商', 'SmisSupplier:Export')
    ]
  },
  {
    menuName: 'SmisAllDocuments',
    buttons: [
      button('View', '查看全部文档', 'SmisAllDocuments:View'),
      button('Add', '新增文档', 'SmisAllDocuments:Add'),
      button('Upload', '上传文档或新版本', 'SmisAllDocuments:Upload'),
      button('Edit', '编辑文档', 'SmisAllDocuments:Edit'),
      button('Delete', '删除草稿文档', 'SmisAllDocuments:Delete'),
      button('Export', '导出文档清单', 'SmisAllDocuments:Export'),
      button('Follow', '关注或取消关注文档', 'SmisAllDocuments:Follow'),
      button('Share', '分享文档', 'SmisAllDocuments:Share'),
      button('CategoryAdd', '新增文档分类', 'SmisAllDocuments:CategoryAdd'),
      button('CategoryEdit', '编辑文档分类', 'SmisAllDocuments:CategoryEdit'),
      button('CategoryDelete', '删除文档分类', 'SmisAllDocuments:CategoryDelete')
    ]
  },
  {
    menuName: 'SmisRequiredKnowledge',
    buttons: [
      button('View', '查看应知应会', 'SmisRequiredKnowledge:View'),
      button('Add', '新增应知应会', 'SmisRequiredKnowledge:Add'),
      button('Edit', '编辑应知应会', 'SmisRequiredKnowledge:Edit'),
      button('Delete', '删除应知应会', 'SmisRequiredKnowledge:Delete'),
      button('Export', '导出应知应会', 'SmisRequiredKnowledge:Export'),
      button('CategoryAdd', '新增文档分类', 'SmisRequiredKnowledge:CategoryAdd'),
      button('CategoryEdit', '编辑文档分类', 'SmisRequiredKnowledge:CategoryEdit'),
      button('CategoryDelete', '删除文档分类', 'SmisRequiredKnowledge:CategoryDelete')
    ]
  },
  {
    menuName: 'SmisSafetyManagementSystem',
    buttons: [
      button('View', '查看安全管理制度', 'SmisSafetyManagementSystem:View'),
      button('Add', '新增安全管理制度', 'SmisSafetyManagementSystem:Add'),
      button('Edit', '编辑安全管理制度', 'SmisSafetyManagementSystem:Edit'),
      button('Delete', '删除安全管理制度', 'SmisSafetyManagementSystem:Delete'),
      button('Export', '导出安全管理制度', 'SmisSafetyManagementSystem:Export')
    ]
  },
  {
    menuName: 'SmisLegalRegulation',
    buttons: [
      button('View', '查看法律法规', 'SmisLegalRegulation:View'),
      button('Add', '新增法律法规', 'SmisLegalRegulation:Add'),
      button('Copy', '复制并新增法律法规', 'SmisLegalRegulation:Copy'),
      button('Edit', '编辑法律法规', 'SmisLegalRegulation:Edit'),
      button('Delete', '删除法律法规', 'SmisLegalRegulation:Delete'),
      button('Export', '导出法律法规', 'SmisLegalRegulation:Export'),
      button('ComplianceView', '查看合规性评价', 'SmisLegalRegulation:ComplianceView'),
      button('ComplianceAdd', '新增合规性评价', 'SmisLegalRegulation:ComplianceAdd'),
      button('ComplianceCopy', '复制并新增合规性评价', 'SmisLegalRegulation:ComplianceCopy'),
      button('ComplianceEdit', '编辑合规性评价', 'SmisLegalRegulation:ComplianceEdit'),
      button('ComplianceDelete', '删除合规性评价', 'SmisLegalRegulation:ComplianceDelete')
    ]
  },
  {
    menuName: 'SmisHazardSourceLedger',
    buttons: [
      button('View', '查看危险源台账', 'SmisHazardSourceLedger:View'),
      button('Add', '新增危险源', 'SmisHazardSourceLedger:Add'),
      button('Edit', '编辑危险源', 'SmisHazardSourceLedger:Edit'),
      button('Delete', '删除危险源', 'SmisHazardSourceLedger:Delete'),
      button('Submit', '提交危险源', 'SmisHazardSourceLedger:Submit'),
      button('Import', '导入危险源', 'SmisHazardSourceLedger:Import'),
      button('Export', '导出危险源', 'SmisHazardSourceLedger:Export'),
      button('Statistics', '危险源统计分析', 'SmisHazardSourceLedger:Statistics'),
      button('DownloadTemplate', '下载危险源导入模板', 'SmisHazardSourceLedger:DownloadTemplate')
    ]
  },
  {
    menuName: 'SmisAccidentFlashReport',
    buttons: [
      button('View', '查看事故快报', 'SmisAccidentFlashReport:View'),
      button('Add', '新增事故快报', 'SmisAccidentFlashReport:Add'),
      button('Edit', '编辑事故快报', 'SmisAccidentFlashReport:Edit'),
      button('Delete', '删除事故快报', 'SmisAccidentFlashReport:Delete'),
      button('Export', '导出事故快报', 'SmisAccidentFlashReport:Export')
    ]
  },
  {
    menuName: 'SmisHistoricalAccidentCases',
    buttons: [
      button('View', '查看历史事故案例', 'SmisHistoricalAccidentCases:View'),
      button('Add', '新增历史事故案例', 'SmisHistoricalAccidentCases:Add'),
      button('Edit', '编辑历史事故案例', 'SmisHistoricalAccidentCases:Edit'),
      button('Delete', '删除历史事故案例', 'SmisHistoricalAccidentCases:Delete'),
      button('Export', '导出历史事故案例', 'SmisHistoricalAccidentCases:Export')
    ]
  },
  {
    menuName: 'SmisSafetyAccidentStatistics',
    buttons: [button('View', '查看安全事故统计', 'SmisSafetyAccidentStatistics:View')]
  },
  {
    menuName: 'SmisWorkInjuryDeclaration',
    buttons: [
      button('View', '查看工伤申报', 'SmisWorkInjuryDeclaration:View'),
      button('Add', '新增工伤申报', 'SmisWorkInjuryDeclaration:Add'),
      button('Edit', '编辑工伤申报', 'SmisWorkInjuryDeclaration:Edit'),
      button('Delete', '删除工伤申报', 'SmisWorkInjuryDeclaration:Delete'),
      button('Export', '导出工伤申报', 'SmisWorkInjuryDeclaration:Export')
    ]
  },
  {
    menuName: 'SmisAccidentInvestigation',
    buttons: [
      button('View', '查看事故分析单', 'SmisAccidentInvestigation:View'),
      button('Add', '新增事故分析单', 'SmisAccidentInvestigation:Add'),
      button('Edit', '编辑事故分析单', 'SmisAccidentInvestigation:Edit'),
      button('Delete', '删除事故分析单', 'SmisAccidentInvestigation:Delete'),
      button('Export', '导出事故分析单', 'SmisAccidentInvestigation:Export')
    ]
  },
  {
    menuName: 'SmisEmergencyRescuePlan',
    buttons: [
      button('View', '查看应急预案', 'SmisEmergencyRescuePlan:View'),
      button('Add', '新增应急预案', 'SmisEmergencyRescuePlan:Add'),
      button('Edit', '编辑应急预案', 'SmisEmergencyRescuePlan:Edit'),
      button('Delete', '删除应急预案', 'SmisEmergencyRescuePlan:Delete'),
      button('Submit', '提交应急预案', 'SmisEmergencyRescuePlan:Submit'),
      button('Void', '置废应急预案', 'SmisEmergencyRescuePlan:Void'),
      button('Activate', '恢复有效预案', 'SmisEmergencyRescuePlan:Activate'),
      button('Push', '下推演练计划', 'SmisEmergencyRescuePlan:Push')
    ]
  },
  {
    menuName: 'SmisEmergencyDrillPlan',
    buttons: [
      button('View', '查看演练计划', 'SmisEmergencyDrillPlan:View'),
      button('Add', '新增演练计划', 'SmisEmergencyDrillPlan:Add'),
      button('Edit', '编辑演练计划', 'SmisEmergencyDrillPlan:Edit'),
      button('Delete', '删除演练计划', 'SmisEmergencyDrillPlan:Delete'),
      button('Submit', '提交演练计划', 'SmisEmergencyDrillPlan:Submit'),
      button('Push', '下推演练记录', 'SmisEmergencyDrillPlan:Push')
    ]
  },
  {
    menuName: 'SmisEmergencyDrillRecord',
    buttons: [
      button('View', '查看演练记录', 'SmisEmergencyDrillRecord:View'),
      button('Add', '新增演练记录', 'SmisEmergencyDrillRecord:Add'),
      button('Edit', '编辑演练记录', 'SmisEmergencyDrillRecord:Edit'),
      button('Delete', '删除演练记录', 'SmisEmergencyDrillRecord:Delete'),
      button('Submit', '提交演练记录', 'SmisEmergencyDrillRecord:Submit')
    ]
  },
  {
    menuName: 'SmisEmergencyDrillReport',
    buttons: [button('View', '查看演练报表', 'SmisEmergencyDrillReport:View')]
  },
  {
    menuName: 'SmisSafetyTrainingPlan',
    buttons: [
      button('View', '查看培训计划', 'SmisSafetyTrainingPlan:View'),
      button('Add', '新增培训计划', 'SmisSafetyTrainingPlan:Add'),
      button('Copy', '复制并新增培训计划', 'SmisSafetyTrainingPlan:Copy'),
      button('Edit', '编辑培训计划', 'SmisSafetyTrainingPlan:Edit'),
      button('Delete', '删除培训计划', 'SmisSafetyTrainingPlan:Delete'),
      button('Publish', '发布培训计划', 'SmisSafetyTrainingPlan:Publish'),
      button('CreateRecord', '创建培训记录', 'SmisSafetyTrainingPlan:CreateRecord'),
      button('Export', '导出培训计划', 'SmisSafetyTrainingPlan:Export')
    ]
  },
  {
    menuName: 'SmisSafetyTrainingRecord',
    buttons: [
      button('View', '查看培训记录', 'SmisSafetyTrainingRecord:View'),
      button('Add', '新增培训记录', 'SmisSafetyTrainingRecord:Add'),
      button('Edit', '编辑培训记录及签到', 'SmisSafetyTrainingRecord:Edit'),
      button('Delete', '删除培训记录', 'SmisSafetyTrainingRecord:Delete'),
      button('Submit', '提交培训记录', 'SmisSafetyTrainingRecord:Submit'),
      button('Export', '导出培训记录', 'SmisSafetyTrainingRecord:Export')
    ]
  },
  {
    menuName: 'SmisTrainingStatisticsReport',
    buttons: [
      button('View', '查看培训统计报表', 'SmisTrainingStatisticsReport:View'),
      button('Export', '导出培训统计报表', 'SmisTrainingStatisticsReport:Export')
    ]
  },
  {
    menuName: 'SmisCourseManagement',
    buttons: [
      button('View', '查看课程', 'SmisCourseManagement:View'),
      button('Add', '新增课程', 'SmisCourseManagement:Add'),
      button('Edit', '编辑课程', 'SmisCourseManagement:Edit'),
      button('Delete', '删除课程', 'SmisCourseManagement:Delete'),
      button('Publish', '发布或关闭课程', 'SmisCourseManagement:Publish'),
      button('Assign', '分配学习人员', 'SmisCourseManagement:Assign'),
      button('Learn', '开始或继续学习', 'SmisCourseManagement:Learn'),
      button('ViewLearningRecord', '查看学习记录', 'SmisCourseManagement:ViewLearningRecord'),
      button('Export', '导出课程及学习记录', 'SmisCourseManagement:Export')
    ]
  },
  {
    menuName: 'SmisExamManagement',
    buttons: [
      button('View', '查看试卷', 'SmisExamManagement:View'),
      button('Add', '创建试卷', 'SmisExamManagement:Add'),
      button('Edit', '编辑试卷', 'SmisExamManagement:Edit'),
      button('Delete', '删除试卷', 'SmisExamManagement:Delete'),
      button('Generate', '随机生成试题', 'SmisExamManagement:Generate'),
      button('Publish', '发布或关闭试卷', 'SmisExamManagement:Publish'),
      button('Assign', '分配考试人员', 'SmisExamManagement:Assign'),
      button('Preview', '考试预览', 'SmisExamManagement:Preview'),
      button('Take', '开始或继续考试', 'SmisExamManagement:Take'),
      button('ViewRecord', '查看考试记录', 'SmisExamManagement:ViewRecord'),
      button('ViewDetail', '查看试卷与答卷详情', 'SmisExamManagement:ViewDetail'),
      button('Export', '导出考试记录', 'SmisExamManagement:Export')
    ]
  },
  {
    menuName: 'SmisQuestionBankManagement',
    buttons: [
      button('View', '查看题库', 'SmisQuestionBankManagement:View'),
      button('Add', '新增题目', 'SmisQuestionBankManagement:Add'),
      button('Edit', '编辑题目', 'SmisQuestionBankManagement:Edit'),
      button('Delete', '删除题目', 'SmisQuestionBankManagement:Delete'),
      button('ManageCategory', '维护题库分类', 'SmisQuestionBankManagement:ManageCategory'),
      button('ToggleStatus', '启用或停用题目', 'SmisQuestionBankManagement:ToggleStatus'),
      button('Export', '导出题库', 'SmisQuestionBankManagement:Export')
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
      button('Add', '新增合同或资质', 'Hr:Compliance:Add'),
      button('Edit', '编辑合同资质', 'Hr:Compliance:Edit'),
      button('Delete', '删除合规草稿', 'Hr:Compliance:Delete'),
      button('ContractRenew', '续签劳动合同', 'Hr:Compliance:Contract:Renew'),
      button('ContractTerminate', '终止劳动合同', 'Hr:Compliance:Contract:Terminate'),
      button('QualificationVerify', '核验员工资质', 'Hr:Compliance:Qualification:Verify'),
      button('QualificationRevoke', '撤销员工资质', 'Hr:Compliance:Qualification:Revoke')
    ]
  },
  {
    menuName: 'HrEmployeeRelations',
    buttons: [
      button('View', '查看员工关系案件', 'Hr:EmployeeRelations:View'),
      button('Add', '新增员工关系案件', 'Hr:EmployeeRelations:Add'),
      button('Edit', '编辑员工关系案件', 'Hr:EmployeeRelations:Edit'),
      button('Delete', '删除员工关系案件草稿', 'Hr:EmployeeRelations:Delete'),
      button('Assign', '分派与分级员工关系案件', 'Hr:EmployeeRelations:Assign'),
      button('Investigate', '调查员工关系案件', 'Hr:EmployeeRelations:Investigate'),
      button('Resolve', '提交员工关系案件解决结论', 'Hr:EmployeeRelations:Resolve'),
      button('Close', '结案或重新开启员工关系案件', 'Hr:EmployeeRelations:Close'),
      button('ActionManage', '管理员工关系处置行动', 'Hr:EmployeeRelations:Action:Manage'),
      button('SensitiveView', '查看员工关系敏感内容', 'Hr:EmployeeRelations:Sensitive:View')
    ]
  },
  {
    menuName: 'HrBenefits',
    buttons: [
      button('View', '查看福利与参保', 'Hr:Benefits:View'),
      button('PlanManage', '管理福利计划', 'Hr:Benefits:Plan:Manage'),
      button('EnrollmentManage', '管理员工参保', 'Hr:Benefits:Enrollment:Manage'),
      button('Approve', '审核员工参保', 'Hr:Benefits:Approve'),
      button('EventManage', '管理福利人生事件', 'Hr:Benefits:Event:Manage'),
      button('AmountView', '查看福利缴费金额', 'Hr:Benefits:Amount:View'),
      button('PayrollExport', '导出福利薪资输入', 'Hr:Benefits:Payroll:Export'),
      button('AmountEdit', '维护福利缴费金额', 'Hr:Benefits:Amount:Edit'),
      button('EvidenceView', '查看福利人生事件附件', 'Hr:Benefits:Evidence:View')
    ]
  },
  {
    menuName: 'HrEmployeeExperience',
    buttons: [
      button('View', '查看员工体验工作台', 'Hr:Experience:View'),
      button('SurveyManage', '管理员工体验调查', 'Hr:Experience:Survey:Manage'),
      button('QuestionManage', '管理员工体验调查题目', 'Hr:Experience:Question:Manage'),
      button('Launch', '发布、开放或关闭员工体验调查', 'Hr:Experience:Launch'),
      button('Respond', '填写匿名员工体验调查', 'Hr:Experience:Respond'),
      button('InsightsView', '查看匿名聚合洞察', 'Hr:Experience:Insights:View'),
      button('CommentsView', '查看匿名开放评论', 'Hr:Experience:Comments:View'),
      button('ActionManage', '管理员工体验改善行动', 'Hr:Experience:Action:Manage'),
      button('ActionClose', '验收员工体验改善行动', 'Hr:Experience:Action:Close')
    ]
  },
  {
    menuName: 'HrPeopleAnalytics',
    buttons: [button('View', '查看人力分析', 'Hr:PeopleAnalytics:View')]
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
    menuName: 'HrCompensationReview',
    buttons: [
      button('View', '查看调薪复核', 'Hr:CompensationReview:View'),
      button('CycleManage', '管理调薪周期', 'Hr:CompensationReview:Cycle:Manage'),
      button('BudgetManage', '管理调薪预算', 'Hr:CompensationReview:Budget:Manage'),
      button('Recommend', '提交调薪建议', 'Hr:CompensationReview:Recommend'),
      button('Calibrate', '执行调薪校准', 'Hr:CompensationReview:Calibrate'),
      button('Approve', '批准调薪结果', 'Hr:CompensationReview:Approve'),
      button('Effect', '批量生效调薪', 'Hr:CompensationReview:Effect'),
      button('AmountView', '查看调薪金额', 'Hr:CompensationReview:Amount:View'),
      button('AmountEdit', '编辑调薪金额', 'Hr:CompensationReview:Amount:Edit')
    ]
  },
  {
    menuName: 'HrContingentWorkforce',
    buttons: [
      button('View', '查看外部用工', 'Hr:ContingentWorkforce:View'),
      button('VendorManage', '管理用工供应商', 'Hr:ContingentWorkforce:Vendor:Manage'),
      button('WorkerManage', '管理外部人员', 'Hr:ContingentWorkforce:Worker:Manage'),
      button('EngagementManage', '管理用工任务', 'Hr:ContingentWorkforce:Engagement:Manage'),
      button('ControlManage', '管理准入控制', 'Hr:ContingentWorkforce:Control:Manage'),
      button('Activate', '激活外部用工', 'Hr:ContingentWorkforce:Activate'),
      button('End', '执行外部人员退场', 'Hr:ContingentWorkforce:End'),
      button('PiiView', '查看外部人员联系方式', 'Hr:ContingentWorkforce:PII:View'),
      button('CostView', '查看外部用工成本', 'Hr:ContingentWorkforce:Cost:View'),
      button('CostEdit', '编辑外部用工成本', 'Hr:ContingentWorkforce:Cost:Edit')
    ]
  },
  {
    menuName: 'HrPolicyAcknowledgement',
    buttons: [
      button('View', '查看政策与签收', 'Hr:PolicyAcknowledgement:View'),
      button('PolicyManage', '管理政策草稿', 'Hr:PolicyAcknowledgement:Policy:Manage'),
      button('Publish', '发布与退役政策', 'Hr:PolicyAcknowledgement:Publish'),
      button('ReceiptManage', '管理政策签收', 'Hr:PolicyAcknowledgement:Receipt:Manage'),
      button('EvidenceView', '查看签收凭证', 'Hr:PolicyAcknowledgement:Evidence:View')
    ]
  },
  {
    menuName: 'HrOrganizationDesign',
    buttons: [
      button('View', '查看组织变革方案', 'Hr:OrganizationDesign:View'),
      button('ScenarioManage', '管理组织变革草稿', 'Hr:OrganizationDesign:Scenario:Manage'),
      button('ImpactReview', '提交影响评审', 'Hr:OrganizationDesign:Impact:Review'),
      button('Approve', '审批组织变革方案', 'Hr:OrganizationDesign:Approve'),
      button('Handoff', '移交组织主数据执行', 'Hr:OrganizationDesign:Handoff')
    ]
  },
  {
    menuName: 'HrInternalMobility',
    buttons: [
      button('View', '查看内部人才市场', 'Hr:InternalMobility:View'),
      button('OpportunityManage', '管理内部机会草稿', 'Hr:InternalMobility:Opportunity:Manage'),
      button('Publish', '发布与关闭内部机会', 'Hr:InternalMobility:Publish'),
      button('ApplicationSelf', '提交本人内部申请', 'Hr:InternalMobility:Application:Self'),
      button('ApplicationManage', '评审内部申请', 'Hr:InternalMobility:Application:Manage'),
      button('Convert', '转正式人事异动', 'Hr:InternalMobility:Convert')
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
      button('Submit', '提交员工服务工单', 'Hr:SelfService:Submit'),
      button('Assign', '分派员工服务工单', 'Hr:SelfService:Assign'),
      button('Resolve', '处理员工服务工单', 'Hr:SelfService:Resolve'),
      button('CatalogManage', '管理员工服务目录', 'Hr:SelfService:Catalog:Manage')
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
