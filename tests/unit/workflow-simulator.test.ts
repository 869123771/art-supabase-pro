import assert from 'node:assert/strict'
import test from 'node:test'
import {
  createWorkflowSimulationContext,
  inspectWorkflowConfig,
  simulateWorkflow
} from '../../src/views/workflow/modules/workflow-simulator'

const fields: Api.Workflow.WorkflowContextField[] = [
  { key: 'amount', label: '费用金额', valueType: 'number' },
  { key: 'costType', label: '费用类型', valueType: 'text' }
]

function createNode(
  key: string,
  order: number,
  condition: Api.Workflow.WorkflowCondition
): Api.Workflow.WorkflowNode {
  return {
    key,
    name: `节点 ${order}`,
    order,
    approvalMode: 'any',
    approvalThresholdPercent: 100,
    rejectVetoEnabled: true,
    allowSelfApproval: false,
    dueHours: 24,
    reminderBeforeMinutes: 60,
    escalationEnabled: true,
    escalateAfterHours: 4,
    assignee: { type: 'roles', roleCodes: ['R_FINANCE'] },
    condition
  }
}

test('workflow simulator identifies every matching node and the first scheduled node', () => {
  const config: Api.Workflow.WorkflowConfig = {
    nodes: [
      createNode('manager', 1, { field: 'amount', operator: 'gt', value: 10000 }),
      createNode('finance', 2, { operator: 'always' })
    ],
    allowAutoApprove: false
  }

  const result = simulateWorkflow(config, fields, { amount: 12000, costType: 'fuel' })

  assert.equal(result.outcome, 'matched')
  assert.equal(result.matchedCount, 2)
  assert.equal(result.firstMatchedNodeKey, 'manager')
  assert.equal(result.traces[0].isFirstMatched, true)
  assert.equal(result.simulationStates.finance, 'matched')
})

test('workflow simulator fails closed when every condition is skipped', () => {
  const config: Api.Workflow.WorkflowConfig = {
    nodes: [createNode('manager', 1, { field: 'amount', operator: 'gte', value: 10000 })],
    allowAutoApprove: false
  }

  const result = simulateWorkflow(config, fields, { amount: 5000 })

  assert.equal(result.outcome, 'blocked')
  assert.equal(result.matchedCount, 0)
  assert.equal(result.skippedCount, 1)
  assert.ok(result.diagnostics.some((item) => item.code === 'SAMPLE_BLOCKED'))
})

test('workflow simulator makes automatic approval explicit when enabled', () => {
  const config: Api.Workflow.WorkflowConfig = {
    nodes: [createNode('manager', 1, { field: 'costType', operator: 'eq', value: 'fuel' })],
    allowAutoApprove: true
  }

  const result = simulateWorkflow(config, fields, { costType: 'toll' })

  assert.equal(result.outcome, 'auto-approved')
  assert.ok(result.diagnostics.some((item) => item.code === 'AUTO_APPROVE_ENABLED'))
  assert.ok(result.diagnostics.some((item) => item.code === 'SAMPLE_AUTO_APPROVED'))
})

test('workflow config inspection blocks contradictory initiator approval rules', () => {
  const node = createNode('initiator', 1, { operator: 'always' })
  node.assignee = { type: 'initiator' }
  node.allowSelfApproval = false

  const diagnostics = inspectWorkflowConfig({ nodes: [node] }, fields)

  assert.ok(
    diagnostics.some(
      (item) => item.code === 'INITIATOR_SELF_APPROVAL_CONFLICT' && item.severity === 'error'
    )
  )
})

test('workflow simulator creates a sample that exercises configured conditions', () => {
  const nodes = [
    createNode('amount', 1, { field: 'amount', operator: 'gt', value: 20000 }),
    createNode('type', 2, { field: 'costType', operator: 'in', value: ['fuel', 'toll'] })
  ]

  const context = createWorkflowSimulationContext(fields, nodes)

  assert.equal(context.amount, 20001)
  assert.equal(context.costType, 'fuel')
  assert.equal(simulateWorkflow({ nodes }, fields, context).matchedCount, 2)
})
