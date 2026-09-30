import assert from 'node:assert/strict'
import test from 'node:test'
import {
  createWorkflowTemplateDraft,
  workflowTemplates
} from '../../src/views/workflow/definition/modules/workflow-templates'
import { getWorkflowBusinessContract } from '../../src/views/workflow/modules/workflow-business-contracts'

test('workflow templates only expose fields from registered business contracts', () => {
  for (const template of workflowTemplates) {
    const contract = getWorkflowBusinessContract(template.businessType)
    assert.equal(template.fieldCount, contract.fields.length)
    assert.ok(template.nodeNames.length >= 1)
  }
})

test('workflow template drafts are isolated and fail closed by default', () => {
  const first = createWorkflowTemplateDraft('waybill-cost')
  const second = createWorkflowTemplateDraft('waybill-cost')

  assert.equal(first.businessType, 'tms_waybill_cost')
  assert.equal(first.config.allowAutoApprove, false)
  assert.equal(first.config.nodes.length, 2)
  assert.notEqual(first.config.nodes[0].key, second.config.nodes[0].key)

  first.config.nodes[0].name = '已修改'
  assert.equal(second.config.nodes[0].name, '费用审核')
})
