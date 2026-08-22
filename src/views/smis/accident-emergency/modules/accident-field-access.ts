import {
  canEditField,
  canViewField,
  getFieldAccess,
  type FieldAccessLevel
} from '@/utils/field-permission'

type AccidentCase = Api.Smis.AccidentEmergency.AccidentCaseRecord
type FieldKey = Api.Smis.AccidentEmergency.AccidentCaseFieldKey

const FIELD_GROUPS = {
  incidentLocation: ['location', 'longitude', 'latitude'],
  casualtyAndLoss: ['casualties', 'economicLoss'],
  investigationDetails: [
    'description',
    'immediateActions',
    'causeAnalysis',
    'correctiveActions',
    'remark'
  ],
  caseEvidence: ['attachmentRefs'],
  caseParticipants: ['reporterUserId', 'investigatorUserId']
} as const satisfies Record<FieldKey, readonly (keyof AccidentCase)[]>

const fallbackAccess = (record: Pick<AccidentCase, 'id'>): FieldAccessLevel =>
  record.id ? 'hidden' : 'edit'

export const getAccidentFieldAccess = (record: AccidentCase, field: FieldKey): FieldAccessLevel =>
  getFieldAccess(record.fieldAccess, field, fallbackAccess(record))

export const canViewAccidentField = (record: AccidentCase, field: FieldKey): boolean =>
  canViewField(record.fieldAccess, field, fallbackAccess(record))

export const canEditAccidentField = (record: AccidentCase, field: FieldKey): boolean =>
  canEditField(record.fieldAccess, field, fallbackAccess(record))

export const normalizeAccidentCase = (record: AccidentCase): AccidentCase => ({
  ...record,
  attachmentRefs: Array.isArray(record.attachmentRefs) ? record.attachmentRefs : []
})

export const buildAccidentCaseWritePayload = (record: AccidentCase): AccidentCase => {
  if (!record.id) return normalizeAccidentCase(record)

  const payload = { ...normalizeAccidentCase(record) }
  ;(
    Object.entries(FIELD_GROUPS) as Array<
      [FieldKey, readonly Extract<keyof AccidentCase, string>[]]
    >
  ).forEach(([field, keys]) => {
    if (canEditAccidentField(record, field)) return
    keys.forEach((key) => delete payload[key])
  })
  return payload
}
