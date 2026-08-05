import assert from 'node:assert/strict'
import test from 'node:test'
import {
  compareAiOrderPayloads,
  validateAiOrderProviderPayload
} from '../../supabase/functions/_shared/ai-order-contract'

function createValidPayload() {
  return {
    summary: '已识别订单资料',
    confidence: 0.92,
    fieldConfidence: { originStationName: 0.98 },
    missingFields: [],
    warnings: [],
    order: {
      originStationName: '杭州',
      transportFee: 120,
      cargoItems: [
        {
          cargoName: '纸箱',
          packageType: 'box',
          unit: 'box',
          quantity: 2,
          weightKg: 20,
          volumeM3: 0.5
        }
      ]
    }
  }
}

test('AI order contract accepts a structurally valid extraction', () => {
  assert.deepEqual(validateAiOrderProviderPayload(createValidPayload()), {
    valid: true,
    errors: []
  })
})

test('AI order contract rejects unsafe numeric and confidence values', () => {
  const payload = createValidPayload()
  payload.confidence = 1.2
  payload.order.transportFee = -1
  payload.order.cargoItems[0].quantity = -2

  const result = validateAiOrderProviderPayload(payload)
  assert.equal(result.valid, false)
  assert.ok(result.errors.some((error) => error.includes('confidence')))
  assert.ok(result.errors.some((error) => error.includes('transportFee')))
  assert.ok(result.errors.some((error) => error.includes('quantity')))
})

test('AI order comparison only scores fields actually proposed by AI', () => {
  assert.deepEqual(
    compareAiOrderPayloads(
      {
        originStationName: ' 杭州 ',
        destinationStationName: null,
        transportFee: 120,
        cargoItems: [{ cargoName: '纸箱', quantity: 2 }]
      },
      {
        originStationName: '杭州',
        destinationStationName: '上海',
        transportFee: 130,
        cargoItems: [{ quantity: 2, cargoName: '纸箱' }]
      }
    ),
    {
      acceptedFields: ['cargoItems', 'originStationName'],
      correctedFields: ['transportFee']
    }
  )
})
