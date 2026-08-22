export {
  deleteEmployee,
  fetchEmployeeList,
  fetchEmployeeOrganizationTree,
  fetchEmployeeProfile,
  fetchEmployeeSelectorList,
  saveEmployeeProfile
} from '@/api/modules/hr/employee'

export {
  addPosition,
  deletePosition,
  editPosition,
  fetchEmployeeDriverCarrierOptions,
  fetchPositionList,
  fetchPositionOptions
} from '@/api/modules/hr/position'

export {
  completeLifecycleTask,
  deleteHrWorkspaceRecord,
  effectPersonnelChange,
  effectRecruitmentRequisition,
  fetchHrWorkspaceRecords,
  saveHrWorkspaceRecord,
  submitHrApproval
} from '@/api/modules/hr/workspace'
