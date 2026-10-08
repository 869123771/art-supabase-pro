import {
  fetchEquipmentInspectionDeleteDestination,
  fetchScmPurchaseDeleteDestination,
  fetchWmsDocumentDeleteDestination
} from '@/api/master-data-delete'
import type { MasterDataDeleteDependencyMeta } from './index.vue'

const purchaseReferenceRoutes: Record<string, string> = {
  initial_inbound: 'WmsInitialPurchaseInbound',
  initial_return: 'WmsInitialPurchaseReturn',
  purchase_inbound: 'WmsPurchaseInbound',
  purchase_return: 'WmsPurchaseReturn',
  other_inbound: 'WmsOtherInbound',
  other_return: 'WmsOtherInbound',
  entrusted_processing_inbound: 'WmsEntrustedProcessingInbound',
  entrusted_processing_return: 'WmsEntrustedProcessingReturn'
}

const scmPurchaseReferenceRoutes: Record<string, string> = {
  purchase_request: 'ScmPurchaseRequest',
  purchase_contract: 'ScmPurchaseContract',
  purchase_order: 'ScmPurchaseOrder',
  receipt_notice: 'ScmReceiptNotice'
}

const warehouseDocumentRoutes = {
  wms_purchase_document: purchaseReferenceRoutes,
  wms_sales_document: {
    initial_outbound: 'WmsInitialSalesOutbound',
    initial_return: 'WmsInitialSalesReturn',
    outbound: 'WmsSalesOutbound',
    return: 'WmsSalesReturnDocument',
    other_outbound: 'WmsOtherOutbound',
    other_return: 'WmsOtherOutbound'
  },
  wms_production_material_document: {
    issue: 'WmsProductionIssue',
    return: 'WmsProductionReturn',
    finished_inbound: 'WmsFinishedInbound',
    finished_return: 'WmsFinishedReturn'
  },
  wms_count_adjustment_document: { gain: 'WmsCountGain', loss: 'WmsCountLoss' }
} satisfies Record<Parameters<typeof fetchWmsDocumentDeleteDestination>[0], Record<string, string>>

export function createRecordReferenceNavigation(
  hasAuth: (permission: string) => boolean
): Record<string, Partial<MasterDataDeleteDependencyMeta>> {
  const permitted = (permission: string) => ({ canNavigate: () => hasAuth(permission) })
  const warehouseReferences = Object.fromEntries(
    Object.entries(warehouseDocumentRoutes).map(([table, routes]) => [
      table,
      {
        routeNames: Object.values(routes),
        canNavigate: () => Object.values(routes).some((name) => hasAuth(`${name}:View`)),
        resolveRouteName: async (record: { targetId: string }) => {
          // Keys originate from the closed route catalog above, never from record data.
          const destination = await fetchWmsDocumentDeleteDestination(
            table as keyof typeof warehouseDocumentRoutes,
            record.targetId
          )
          const name = destination
            ? (routes as Record<string, string>)[destination.kind]
            : undefined
          return name && hasAuth(`${name}:View`) ? name : null
        }
      }
    ])
  )
  return {
    ...warehouseReferences,
    mdm_warehouse_bin: { routeName: 'MdmWarehouseBin', ...permitted('MdmWarehouseBin:View') },
    wms_inventory_batch: { routeName: 'MdmInventoryBatch', ...permitted('MdmInventoryBatch:View') },
    wms_inventory_reservation: {
      routeName: 'MdmInventoryReservation',
      ...permitted('MdmInventoryReservation:View')
    },
    wms_package_placement: {
      routeName: 'MdmInventoryPackage',
      ...permitted('MdmInventoryPackage:View')
    },
    wms_serial_number: { routeName: 'MdmInventorySerial', ...permitted('MdmInventorySerial:View') },
    wms_opening_balance: { routeName: 'WmsInitialStock', ...permitted('WmsInitialStock:View') },
    wms_initial_stock_document: {
      routeName: 'WmsInitialStock',
      ...permitted('WmsInitialStock:View')
    },
    wms_transfer_request_document: { routeName: 'WmsTransfer', ...permitted('WmsTransfer:View') },
    wms_transfer_document: {
      routeName: 'WmsDirectTransfer',
      ...permitted('WmsDirectTransfer:View')
    },
    wms_issue_request: {
      routeName: 'WmsIssueRequest',
      routeQuery: { resourceType: 'wms_issue_request' },
      ...permitted('WmsIssueRequest:View')
    },
    mdm_employee: {
      ...permitted('Hr:Employee:View'),
      routeParams: (record) => ({ id: record.targetId })
    },
    mdm_employee_assignment: permitted('Hr:Employee:View'),
    fms_fixed_asset: permitted('FinanceFixedAsset:View'),
    mdm_job_profile: permitted('Hr:JobProfile:View'),
    hr_external_engagement: permitted('Hr:ContingentWorkforce:View'),
    hr_external_worker: permitted('Hr:ContingentWorkforce:View'),
    mdm_external_vendor: permitted('Hr:ContingentWorkforce:View'),
    hr_external_engagement_control: permitted('Hr:ContingentWorkforce:View'),
    hr_employee_contract: permitted('Hr:Compliance:View'),
    hr_employee_qualification: permitted('Hr:Compliance:View'),
    hr_performance_cycle: permitted('Hr:Performance:View'),
    hr_performance_review: permitted('Hr:Performance:View'),
    hr_performance_goal: permitted('Hr:Performance:View'),
    hr_performance_check_in: permitted('Hr:Performance:View'),
    hr_performance_calibration_session: permitted('Hr:Performance:View'),
    hr_internal_mobility_application: permitted('Hr:InternalMobility:View'),
    hr_internal_opportunity: permitted('Hr:InternalMobility:View'),
    hr_lifecycle_case: permitted('Hr:Lifecycle:View'),
    hr_lifecycle_task: permitted('Hr:Lifecycle:View'),
    hr_lifecycle_template: permitted('Hr:Lifecycle:View'),
    hr_lifecycle_template_task: permitted('Hr:Lifecycle:View'),
    hr_personnel_change: permitted('Hr:PersonnelChange:View'),
    hr_position_headcount: permitted('Hr:Headcount:View'),
    hr_recruitment_handoff: permitted('Hr:Recruitment:View'),
    hr_recruitment_requisition: permitted('Hr:Recruitment:View'),
    hr_candidate: permitted('Hr:Recruitment:View'),
    hr_succession_plan: permitted('Hr:Succession:View'),
    hr_succession_candidate: permitted('Hr:Succession:View'),
    hr_succession_development_action: permitted('Hr:Succession:View'),
    hr_training_plan: permitted('Hr:Talent:View'),
    hr_learning_course: permitted('Hr:Talent:View'),
    hr_learning_course_competency: permitted('Hr:Talent:View'),
    hr_learning_session: permitted('Hr:Talent:View'),
    hr_training_enrollment: permitted('Hr:Talent:View'),
    hr_learning_certificate: permitted('Hr:Talent:View'),
    hr_organization_design_scenario: permitted('Hr:OrganizationDesign:View'),
    hr_organization_design_change: permitted('Hr:OrganizationDesign:View'),
    hr_shift: permitted('Hr:Attendance:View'),
    hr_shift_assignment: permitted('Hr:Attendance:View'),
    hr_attendance_record: permitted('Hr:Attendance:View'),
    hr_attendance_correction: permitted('Hr:Attendance:View'),
    hr_attendance_period: permitted('Hr:Attendance:View'),
    hr_leave_type: permitted('Hr:Absence:View'),
    hr_leave_policy: permitted('Hr:Absence:View'),
    hr_leave_balance: permitted('Hr:Absence:View'),
    hr_leave_request: permitted('Hr:Absence:View'),
    hr_leave_ledger: permitted('Hr:Absence:View'),
    hr_pay_component: permitted('Hr:Compensation:View'),
    hr_compensation_plan: permitted('Hr:Compensation:View'),
    hr_salary_band: permitted('Hr:Compensation:View'),
    hr_employee_compensation: permitted('Hr:Compensation:View'),
    hr_compensation_review_cycle: permitted('Hr:CompensationReview:View'),
    hr_compensation_review_item: permitted('Hr:CompensationReview:View'),
    hr_compensation_review_budget: permitted('Hr:CompensationReview:View'),
    hr_policy_document: permitted('Hr:PolicyAcknowledgement:View'),
    hr_policy_receipt: permitted('Hr:PolicyAcknowledgement:View'),
    hr_self_service_request: permitted('Hr:SelfService:View'),
    hr_service_catalog: permitted('Hr:SelfService:View'),
    hr_employee_relation_case: permitted('Hr:EmployeeRelations:View'),
    hr_employee_relation_action: permitted('Hr:EmployeeRelations:View'),
    hr_workforce_plan_line: permitted('Hr:Headcount:View'),
    hr_workforce_plan_cycle: permitted('Hr:Headcount:View'),
    smis_position_risk_control: permitted('SmisPositionRiskList:View'),
    smis_position_safety_responsibility: permitted('SmisPositionSafetyResponsibility:View'),
    smis_position_work_instruction_scope: permitted('SmisPositionWorkInstruction:View'),
    scm_purchase_document: {
      routeNames: Object.values(scmPurchaseReferenceRoutes),
      canNavigate: () =>
        Object.values(scmPurchaseReferenceRoutes).some((name) => hasAuth(`${name}:View`)),
      resolveRouteName: async (record) => {
        const destination = await fetchScmPurchaseDeleteDestination(record.targetId)
        const name = destination ? scmPurchaseReferenceRoutes[destination.kind] : undefined
        return name && hasAuth(`${name}:View`) ? name : null
      }
    },
    mdm_material: {
      routeName: 'MdmMaterialArchive',
      canNavigate: () => hasAuth('MdmMaterialArchive:View')
    },
    mdm_equipment: {
      routeName: 'SmisEquipmentLedgerDetail',
      routeParams: (record) => ({ id: record.targetId }),
      canNavigate: () => hasAuth('SmisEquipmentLedger:View')
    },
    smis_equipment_inspection: {
      routeName: 'SmisEquipmentLedgerDetail',
      routeQuery: { tab: 'inspections' },
      routeParams: async (record) => {
        const destination = await fetchEquipmentInspectionDeleteDestination(record.recordId)
        return destination?.equipmentId ? { id: destination.equipmentId } : null
      },
      canNavigate: () => hasAuth('SmisEquipmentLedger:View')
    }
  }
}
