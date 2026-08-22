import assert from 'node:assert/strict'
import test from 'node:test'
import {
  buildAccidentCaseWritePayload,
  canEditAccidentField,
  canViewAccidentField,
  normalizeAccidentCase
} from '../../src/views/smis/accident-emergency/modules/accident-field-access'

type AccidentCase = Api.Smis.AccidentEmergency.AccidentCaseRecord

const createCase = (overrides: Partial<AccidentCase> = {}): AccidentCase => ({
  id: 'accident-1',
  riskPointId: null,
  reporterUserId: 'reporter-1',
  sourceType: 'manual',
  sourceBusinessId: null,
  caseNo: 'SG-001',
  caseTitle: '测试事故',
  incidentType: 'accident',
  severity: 'general',
  occurredAt: '2026-08-22 08:00:00',
  location: '测试地点',
  longitude: 121.5,
  latitude: 31.2,
  description: '事故详情',
  casualties: 1,
  economicLoss: 1000,
  immediateActions: '现场处置',
  causeAnalysis: '原因分析',
  correctiveActions: '整改措施',
  status: 'reported',
  attachmentRefs: [{ id: 'attachment-1', name: 'evidence.pdf' }],
  remark: '内部备注',
  ...overrides
})

test('new SMIS accident cases are creator-editable before they have an id', () => {
  const record = createCase({ id: undefined, fieldAccess: undefined })

  assert.equal(canViewAccidentField(record, 'incidentLocation'), true)
  assert.equal(canEditAccidentField(record, 'caseEvidence'), true)
  assert.equal(buildAccidentCaseWritePayload(record).description, '事故详情')
})

test('existing SMIS accident cases without access metadata default to hidden', () => {
  const record = createCase({ fieldAccess: undefined })

  assert.equal(canViewAccidentField(record, 'investigationDetails'), false)
  assert.equal(canEditAccidentField(record, 'caseParticipants'), false)
})

test('SMIS accident updates omit every sensitive group that is not editable', () => {
  const payload = buildAccidentCaseWritePayload(
    createCase({
      fieldAccess: {
        incidentLocation: 'read',
        casualtyAndLoss: 'masked',
        investigationDetails: 'edit',
        caseEvidence: 'hidden',
        caseParticipants: 'read'
      }
    })
  )

  assert.equal(payload.location, undefined)
  assert.equal(payload.longitude, undefined)
  assert.equal(payload.casualties, undefined)
  assert.equal(payload.economicLoss, undefined)
  assert.equal(payload.attachmentRefs, undefined)
  assert.equal(payload.reporterUserId, undefined)
  assert.equal(payload.description, '事故详情')
  assert.equal(payload.correctiveActions, '整改措施')
  assert.equal(payload.caseTitle, '测试事故')
})

test('SMIS accident rendering normalizes omitted evidence to an empty list', () => {
  assert.deepEqual(
    normalizeAccidentCase(createCase({ attachmentRefs: undefined })).attachmentRefs,
    []
  )
})
