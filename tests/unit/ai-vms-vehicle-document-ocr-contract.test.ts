import assert from 'node:assert/strict'
import test from 'node:test'
import {
  areVmsVehicleDocumentImageUrlsInScope,
  isValidVmsVehicleDocumentTenantScope,
  normalizeVmsVehicleDocumentOcrResponse,
  validateVmsVehicleDocumentOcrPayload
} from '../../supabase/functions/_shared/ai-vms-vehicle-document-ocr-contract'

const projectUrl = 'https://example.supabase.co'
const ownTenant = '11111111-1111-4111-8111-111111111111'
const otherTenant = '22222222-2222-4222-8222-222222222222'
const ownImage = `${projectUrl}/storage/v1/object/public/attachments/${ownTenant}/license.png`
const otherImage = `${projectUrl}/storage/v1/object/public/attachments/${otherTenant}/license.png`

test('vehicle OCR accepts only project attachment images in the effective tenant', () => {
  assert.equal(areVmsVehicleDocumentImageUrlsInScope([ownImage], projectUrl, ownTenant), true)
  assert.equal(areVmsVehicleDocumentImageUrlsInScope([otherImage], projectUrl, ownTenant), false)
  assert.equal(
    areVmsVehicleDocumentImageUrlsInScope([ownImage, otherImage], projectUrl, null),
    true
  )
  assert.equal(
    areVmsVehicleDocumentImageUrlsInScope(
      [`https://other.example/storage/v1/object/public/attachments/${ownTenant}/license.png`],
      projectUrl,
      ownTenant
    ),
    false
  )
  assert.equal(
    areVmsVehicleDocumentImageUrlsInScope(
      [`${projectUrl}/storage/v1/object/public/attachments/${ownTenant}`],
      projectUrl,
      ownTenant
    ),
    false
  )
  assert.equal(isValidVmsVehicleDocumentTenantScope('all'), false)
})

test('vehicle OCR normalizes document fields and requires structured confidence', () => {
  const result = normalizeVmsVehicleDocumentOcrResponse({
    rawText: ' 车牌号：测试A12345 ',
    confidence: 1.3,
    fieldConfidence: { plateNo: 0.9 },
    warnings: [],
    document: { plateNo: ' 测试A12345 ', registerDate: '2026/09/29' }
  })
  assert.equal(result.document.plateNo, '测试A12345')
  assert.equal(result.document.registerDate, '2026-09-29')
  assert.equal(result.confidence, 1)
  assert.equal(
    validateVmsVehicleDocumentOcrPayload({
      rawText: '号牌号码：测试A12345',
      confidence: 0.9,
      fieldConfidence: {},
      document: { plateNo: '测试A12345' }
    }).valid,
    true
  )
  assert.equal(validateVmsVehicleDocumentOcrPayload({ confidence: 2, document: {} }).valid, false)
  assert.deepEqual(
    validateVmsVehicleDocumentOcrPayload({
      rawText: '',
      confidence: 0.9,
      fieldConfidence: {},
      document: {}
    }).errors,
    ['document_fields_missing', 'image_text_missing']
  )
})
