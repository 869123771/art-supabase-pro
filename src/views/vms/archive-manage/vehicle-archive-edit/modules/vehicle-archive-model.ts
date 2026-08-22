export type VehicleArchive = Api.Vms.ArchiveManage.VehicleArchive

export type VehicleArchiveForm = VehicleArchive & {
  primaryDriverName: string
  primaryDriverPhone: string
  secondaryDriverName: string
  secondaryDriverPhone: string
}

export type VehicleArchiveWritePayload = Record<string, unknown> & { id?: string }

const EDITABLE_FIELD_ACCESS: Api.Vms.ArchiveManage.VehicleArchiveFieldAccessMap = {
  vehicleIdentifiers: 'edit',
  ownerIdentity: 'edit',
  contactPhones: 'edit',
  mailingAddress: 'edit',
  operationRoute: 'edit',
  documents: 'edit',
  deviceIdentity: 'edit'
}

const SENSITIVE_PAYLOAD_KEYS: Record<Api.Vms.ArchiveManage.VehicleArchiveFieldKey, string[]> = {
  vehicleIdentifiers: [
    'vin',
    'operationCertNo',
    'purchaseCertNo',
    'registrationCertNo',
    'chassisNo',
    'gearboxSerialNo',
    'engineNo',
    'licensePlateCode'
  ],
  ownerIdentity: ['ownerId', 'ownerName', 'ownerGender', 'idCardNo'],
  contactPhones: ['ownerPhone'],
  mailingAddress: ['mailingAddress'],
  operationRoute: ['operationRoute'],
  documents: [
    'drivingLicenseFrontUrl',
    'drivingLicenseBackUrl',
    'operationLicenseUrl',
    'attachments'
  ],
  deviceIdentity: ['acCode', 'terminalPhone']
}

export function requiresVehicleArchiveResubmission(
  auditStatus: VehicleArchive['auditStatus']
): boolean {
  return auditStatus === 'rejected'
}

export function createInitialVehicleArchiveForm(): VehicleArchiveForm {
  return {
    id: undefined,
    plateNo: '',
    carrierId: null,
    carrier: null,
    companyName: '',
    selfNo: '',
    vehicleType: '',
    originType: 'domestic',
    vin: '',
    manufacturer: '',
    brandModel: '',
    operationCertNo: '',
    purchaseCertNo: '',
    registrationCertNo: '',
    vehicleColor: '',
    chassisNo: '',
    acCode: '',
    gearboxSerialNo: '',
    registerDate: '',
    issueDate: '',
    invoiceDate: '',
    startUseDate: '',
    serviceYears: null,
    approvedPassengerCount: null,
    seatCount: null,
    businessType: '',
    isAirConditioned: false,
    operationStatus: 'operating',
    operationStatusChangeDate: '',
    purchaseStatus: '',
    purchaseStatusChangeDate: '',
    inspectionStartDate: '',
    vehicleLevel: '',
    isNewEnergy: false,
    threeGuaranteeMileage: null,
    threeGuaranteeDuration: null,
    warrantyMileage: null,
    warrantyDuration: null,
    remark: '',
    grossMass: null,
    curbWeight: null,
    approvedLoadMass: null,
    overallLength: null,
    overallWidth: null,
    overallHeight: null,
    platform: '',
    frontTrack: null,
    rearTrack: null,
    wheelbase: null,
    axleCount: null,
    tireCount: null,
    leafSpringCount: null,
    isDoubleDeck: false,
    engineNo: '',
    engineModel: '',
    fuelType: '',
    displacement: null,
    emissionStandard: '',
    enginePower: null,
    ratedTorqueSpeed: null,
    engineTorque: null,
    plateColor: '',
    transportIndustry: '',
    operationType: '',
    ownerId: '',
    ownerName: '',
    ownerPhone: '',
    terminalPhone: '',
    ownerGender: '',
    idCardNo: '',
    mailingAddress: '',
    tonnageOrSeat: '',
    primaryDriverId: null,
    primaryDriver: null,
    primaryDriverName: '',
    primaryDriverPhone: '',
    secondaryDriverId: null,
    secondaryDriver: null,
    secondaryDriverName: '',
    secondaryDriverPhone: '',
    operationRoute: '',
    licensePlateCode: '',
    serviceStartTime: '',
    serviceEndTime: '',
    supportPhoto: false,
    vehiclePhotoUrl: '',
    drivingLicenseFrontUrl: '',
    drivingLicenseBackUrl: '',
    operationLicenseUrl: '',
    attachments: [],
    auditStatus: 'pending',
    auditRemark: '',
    fieldAccess: { ...EDITABLE_FIELD_ACCESS },
    isRecordOwner: false
  }
}

export function sanitizeVehicleArchivePayload(
  params: VehicleArchiveForm
): VehicleArchiveWritePayload {
  const {
    id,
    tenantId,
    createBy,
    createTime,
    updateBy,
    updateTime,
    auditBy,
    auditTime,
    auditStatus,
    auditRemark,
    carrier,
    primaryDriver,
    secondaryDriver,
    primaryDriverName,
    primaryDriverPhone,
    secondaryDriverName,
    secondaryDriverPhone,
    driverOneName,
    driverOnePhone,
    driverTwoName,
    driverTwoPhone,
    fieldAccess,
    isRecordOwner,
    ...formPayload
  } = params
  const payload: Record<string, unknown> = {
    ...formPayload,
    attachments: formPayload.attachments ?? [],
    isAirConditioned: formPayload.isAirConditioned ?? false,
    isNewEnergy: formPayload.isNewEnergy ?? false,
    isDoubleDeck: formPayload.isDoubleDeck ?? false,
    supportPhoto: formPayload.supportPhoto ?? false
  }

  void tenantId
  void createBy
  void createTime
  void updateBy
  void updateTime
  void auditBy
  void auditTime
  void auditStatus
  void auditRemark
  void carrier
  void primaryDriver
  void secondaryDriver
  void primaryDriverName
  void primaryDriverPhone
  void secondaryDriverName
  void secondaryDriverPhone
  void driverOneName
  void driverOnePhone
  void driverTwoName
  void driverTwoPhone
  void isRecordOwner

  if (id) {
    Object.entries(SENSITIVE_PAYLOAD_KEYS).forEach(([field, keys]) => {
      if (fieldAccess?.[field as Api.Vms.ArchiveManage.VehicleArchiveFieldKey] === 'edit') return
      keys.forEach((key) => delete payload[key])
    })
  }

  return {
    ...(id ? { id } : {}),
    ...Object.fromEntries(
      Object.entries(payload).map(([key, value]) => [key, value === '' ? null : value])
    )
  }
}
