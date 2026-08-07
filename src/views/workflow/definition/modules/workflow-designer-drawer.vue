<template>
  <ArtDrawer ref="drawerRef" size="xl">
    <template #header>
      <div class="workflow-designer__title">
        <span><ArtSvgIcon icon="ri:flow-chart" /></span>
        <div>
          <strong>{{ form.data.id ? '编辑审批流程' : '新建审批流程' }}</strong>
          <small>配置版本化流程、审批人和流转条件</small>
        </div>
      </div>
    </template>

    <div class="workflow-designer">
      <section class="workflow-designer__base art-card-xs">
        <ArtSectionTitle>流程信息</ArtSectionTitle>
        <ArtForm
          ref="baseFormRef"
          v-model="form.data"
          :items="baseItems"
          :rules="baseRules"
          :span="12"
          :gutter="18"
          label-position="top"
          :show-reset="false"
          :show-submit="false"
        />
      </section>

      <section class="workflow-designer__preview art-card-xs">
        <div class="workflow-designer__section-header">
          <div>
            <ArtSectionTitle>流程图预览</ArtSectionTitle>
            <p>当前引擎按从左到右顺序执行；分支条件不满足时跳过该节点。</p>
          </div>
          <div class="workflow-designer__preview-actions">
            <ElTag :type="form.data.config.allowAutoApprove ? 'warning' : 'success'" effect="plain">
              {{
                form.data.config.allowAutoApprove ? '允许全跳过后自动通过' : '全条件不命中时阻断'
              }}
            </ElTag>
            <ElButton
              type="primary"
              plain
              :disabled="!form.data.config.nodes.length"
              @click="openSimulator"
            >
              <ArtSvgIcon icon="ri:test-tube-line" />试跑与体检
            </ElButton>
          </div>
        </div>
        <WorkflowFlowMap :nodes="form.data.config.nodes" compact />
      </section>

      <section class="workflow-designer__canvas art-card-xs">
        <header class="workflow-designer__section-header">
          <div>
            <ArtSectionTitle>审批节点</ArtSectionTitle>
            <p>拖拽调整执行顺序；条件不满足的节点会自动跳过。</p>
          </div>
          <div class="workflow-designer__canvas-actions">
            <span>
              已配置 {{ configuredNodeCount }}/{{ form.data.config.nodes.length }} 个节点
              <template v-if="conditionalNodeCount">
                · {{ conditionalNodeCount }} 个条件节点</template
              >
            </span>
            <ElButton type="primary" plain @click="addNode">
              <ArtSvgIcon icon="ri:add-line" />新增节点
            </ElButton>
          </div>
        </header>

        <div class="workflow-designer__workspace">
          <aside class="workflow-designer__nodes">
            <div class="workflow-designer__nodes-header">
              <span>执行顺序</span>
              <small>{{ form.data.config.nodes.length }} 个节点</small>
            </div>
            <ElScrollbar always>
              <div class="workflow-designer__nodes-content">
                <VueDraggable
                  v-model="form.data.config.nodes"
                  handle=".workflow-designer__drag"
                  :animation="180"
                  @end="normalizeNodeOrder"
                >
                  <article
                    v-for="(node, index) in form.data.config.nodes"
                    :key="node.key"
                    :class="['workflow-designer__node', { 'is-active': selectedIndex === index }]"
                  >
                    <button
                      type="button"
                      class="workflow-designer__node-select"
                      :aria-label="`选择${node.name || `审批节点 ${index + 1}`}`"
                      :aria-pressed="selectedIndex === index"
                      @click="selectedIndex = index"
                    >
                      <span class="workflow-designer__drag" title="拖拽排序">
                        <ArtSvgIcon icon="ri:draggable" />
                      </span>
                      <i>{{ index + 1 }}</i>
                      <span>
                        <strong>{{ node.name || `审批节点 ${index + 1}` }}</strong>
                        <small>{{ getAssigneeSummary(node) }}</small>
                      </span>
                    </button>
                    <ElButton
                      text
                      type="danger"
                      :aria-label="`删除${node.name || `审批节点 ${index + 1}`}`"
                      @click="removeNode(index)"
                    >
                      <ArtSvgIcon icon="ri:delete-bin-6-line" />
                    </ElButton>
                  </article>
                </VueDraggable>

                <ArtEmptyState
                  v-if="!form.data.config.nodes.length"
                  title="还没有审批节点"
                  description="至少添加一个节点后才能保存流程。"
                  size="compact"
                  :visual-size="72"
                >
                  <template #action>
                    <ElButton type="primary" @click="addNode">添加首个节点</ElButton>
                  </template>
                </ArtEmptyState>
              </div>
            </ElScrollbar>
          </aside>

          <main class="workflow-designer__editor">
            <ElScrollbar always>
              <div class="workflow-designer__editor-content">
                <template v-if="selectedNode">
                  <div class="workflow-designer__editor-heading">
                    <span><ArtSvgIcon icon="ri:user-settings-line" /></span>
                    <div>
                      <strong
                        >节点 {{ selectedIndex + 1 }} · {{ selectedNode.name || '未命名' }}</strong
                      >
                      <small>设置处理人、会签规则、时限与进入条件</small>
                    </div>
                  </div>
                  <ArtForm
                    ref="nodeFormRef"
                    v-model="selectedNode"
                    :items="nodeItems"
                    :span="12"
                    :gutter="18"
                    label-position="top"
                    :show-reset="false"
                    :show-submit="false"
                  />
                </template>
                <ArtEmptyState
                  v-else
                  title="选择一个节点开始配置"
                  description="左侧节点对应流程的实际执行顺序。"
                  size="compact"
                  :visual-size="82"
                />
              </div>
            </ElScrollbar>
          </main>
        </div>
      </section>
    </div>
  </ArtDrawer>
  <WorkflowSimulatorDialog ref="simulatorDialogRef" />
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import { cloneDeep, trim } from 'lodash-es'
  import { VueDraggable } from 'vue-draggable-plus'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import WorkflowFlowMap from '../../modules/workflow-flow-map.vue'
  import WorkflowSimulatorDialog from './workflow-simulator-dialog.vue'
  import { getWorkflowBusinessContract } from '../../modules/workflow-business-contracts'
  import { useUserStore } from '@/store/modules/user'
  import { fetchGetEnableTenantList } from '@/api/system-manage'
  import {
    fetchWorkflowDefinitionDetail,
    fetchWorkflowRoleOptions,
    fetchWorkflowUserOptions,
    saveWorkflowDefinition
  } from '@/api/workflow'

  defineOptions({ name: 'WorkflowDesignerDrawer' })

  interface DesignerForm extends Api.Workflow.WorkflowDefinitionSavePayload {
    id?: string
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
    reloadOptions: (key?: string) => Promise<void>
  }

  interface SimulatorDialogExpose {
    handleOpen: (data: {
      businessType: string
      businessTypeLabel: string
      config: Api.Workflow.WorkflowConfig
    }) => Promise<void>
  }

  const emit = defineEmits<{ (event: 'success'): void }>()
  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const drawerRef = ref<ArtDrawerExpose<Api.Workflow.WorkflowDefinitionRecord | undefined>>()
  const baseFormRef = ref<FormExpose>()
  const nodeFormRef = ref<FormExpose>()
  const simulatorDialogRef = ref<SimulatorDialogExpose>()
  const selectedIndex = ref(0)
  const identityLocked = ref(false)

  const createNode = (index: number): Api.Workflow.WorkflowNode => ({
    key: `node_${crypto.randomUUID().replaceAll('-', '').slice(0, 12)}`,
    name: `审批节点 ${index + 1}`,
    order: index + 1,
    approvalMode: 'any',
    approvalThresholdPercent: 67,
    rejectVetoEnabled: true,
    allowSelfApproval: false,
    dueHours: 24,
    reminderBeforeMinutes: 60,
    escalationEnabled: true,
    escalateAfterHours: 4,
    assignee: { type: 'roles', roleCodes: [] },
    condition: { operator: 'always' }
  })

  const createInitialForm = (): DesignerForm => ({
    tenantId: undefined,
    code: '',
    name: '',
    businessType: 'tms_waybill_cost',
    description: '',
    changeNote: '',
    config: { nodes: [createNode(0)], allowAutoApprove: false }
  })

  const form = reactive<{ data: DesignerForm }>({ data: createInitialForm() })
  const selectedNode = computed<Api.Workflow.WorkflowNode | undefined>({
    get: () => form.data.config.nodes[selectedIndex.value],
    set: (value) => {
      if (value) form.data.config.nodes[selectedIndex.value] = value
    }
  })
  const configuredNodeCount = computed(
    () =>
      form.data.config.nodes.filter((node) => {
        const assigneeCount =
          node.assignee.type === 'users'
            ? node.assignee.userIds?.length
            : node.assignee.roleCodes?.length
        return (
          Boolean(trim(node.name)) && (node.assignee.type === 'initiator' || Boolean(assigneeCount))
        )
      }).length
  )
  const conditionalNodeCount = computed(
    () => form.data.config.nodes.filter((node) => node.condition.operator !== 'always').length
  )

  const dictOptions = (code: string) => computed(() => getDictMap.value[code] ?? [])
  const businessTypeOptions = dictOptions('workflowBusinessType')
  const approvalModeOptions = dictOptions('workflowApprovalMode')
  const assigneeTypeOptions = dictOptions('workflowAssigneeType')
  const conditionOperatorOptions = dictOptions('workflowConditionOperator')
  const contextFields = computed(() => getWorkflowBusinessContract(form.data.businessType).fields)
  const businessTypeLabel = computed(
    () =>
      businessTypeOptions.value.find((item) => item.value === form.data.businessType)?.label ||
      form.data.businessType ||
      '通用审批'
  )
  const contextFieldOptions = computed(() =>
    contextFields.value.map((field) => ({
      label: `${field.label}（${field.key}）`,
      value: field.key
    }))
  )

  const baseRules = computed<FormRules<DesignerForm>>(() => ({
    tenantId: isPlatformSuper.value
      ? [{ required: true, message: '请选择流程所属租户', trigger: 'change' }]
      : [],
    code: [
      { required: true, message: '请输入流程编码', trigger: 'blur' },
      {
        pattern: /^[A-Za-z][A-Za-z0-9_.-]{1,63}$/,
        message: '以字母开头，可使用字母、数字、点、横线和下划线',
        trigger: 'blur'
      }
    ],
    name: [{ required: true, message: '请输入流程名称', trigger: 'blur' }],
    businessType: [{ required: true, message: '请选择业务类型', trigger: 'change' }]
  }))

  const baseItems = computed<FormItem[]>(() => [
    {
      label: '所属租户',
      key: 'tenantId',
      type: 'select',
      span: 24,
      hidden: !isPlatformSuper.value,
      help: form.data.id
        ? '流程归属租户不可变更；平台超级管理员正在进行跨租户维护。'
        : '流程只服务所选租户，同一流程编码可在不同租户独立配置。',
      api: fetchGetEnableTenantList,
      resultField: 'data',
      valueField: 'id',
      labelFn: (tenant) => `${tenant.tenantName}（${tenant.tenantCode}）`,
      props: {
        filterable: true,
        placeholder: '选择流程所属租户',
        disabled: Boolean(form.data.id),
        onChange: handleTenantChange
      }
    },
    {
      label: '流程编码',
      key: 'code',
      type: 'input',
      help: '发布后编码与业务类型不可随意变更。',
      props: {
        maxlength: 64,
        placeholder: '例如 waybill_cost_approval',
        disabled: identityLocked.value
      }
    },
    {
      label: '流程名称',
      key: 'name',
      type: 'input',
      props: { maxlength: 80, placeholder: '例如 运单费用审批' }
    },
    {
      label: '业务类型',
      key: 'businessType',
      type: 'select',
      props: {
        options: businessTypeOptions.value,
        placeholder: '选择可复用的业务场景',
        disabled: identityLocked.value,
        onChange: handleBusinessTypeChange
      }
    },
    {
      label: '版本说明',
      key: 'changeNote',
      type: 'input',
      props: { maxlength: 200, placeholder: '说明本次配置变更内容' }
    },
    {
      label: '流程说明',
      key: 'description',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 2, maxlength: 500, showWordLimit: true }
    },
    {
      label: '全条件未命中策略',
      key: 'config.allowAutoApprove',
      type: 'switch',
      span: 24,
      help: '默认阻断并报错，防止条件字段缺失导致业务单据被静默自动通过。仅明确需要“无节点命中即通过”时开启。',
      props: { activeText: '自动通过', inactiveText: '安全阻断', inlinePrompt: true }
    }
  ])

  const nodeItems = computed<FormItem[]>(() => {
    const assigneeType = selectedNode.value?.assignee.type
    const approvalMode = selectedNode.value?.approvalMode
    const conditionOperator = selectedNode.value?.condition.operator
    return [
      {
        label: '节点名称',
        key: 'name',
        type: 'input',
        span: 24,
        props: { maxlength: 80, placeholder: '例如 财务经理审批' }
      },
      {
        label: '审批方式',
        key: 'approvalMode',
        type: 'select',
        help:
          approvalMode === 'all'
            ? '所有审批人都通过才放行；任一驳回都会使全员通过条件无法达成。'
            : '或签满足一人通过；比例会签按实际审批人数向上取整计算。',
        props: { options: approvalModeOptions.value }
      },
      {
        label: '通过比例（%）',
        key: 'approvalThresholdPercent',
        type: 'number',
        hidden: approvalMode !== 'percentage',
        help: '例如 67% 且有 3 位审批人时，需要 3 人通过。',
        props: { min: 1, max: 100, precision: 0, controlsPosition: 'right', class: '!w-full' }
      },
      {
        label: '驳回策略',
        key: 'rejectVetoEnabled',
        type: 'switch',
        hidden: approvalMode === 'all',
        help: '关闭后，单次驳回不会立即结束；仅当剩余人数已无法达到通过条件时驳回。',
        props: {
          activeText: '一票否决',
          inactiveText: '容错计算',
          inlinePrompt: true
        }
      },
      {
        label: '审批时限（小时）',
        key: 'dueHours',
        type: 'number',
        props: { min: 1, max: 720, precision: 0, controlsPosition: 'right', class: '!w-full' }
      },
      {
        label: '时效提醒',
        key: 'reminderDivider',
        type: 'divider',
        span: 24
      },
      {
        label: '到期前提醒（分钟）',
        key: 'reminderBeforeMinutes',
        type: 'number',
        help: '设为 0 表示不发送到期前提醒。',
        props: { min: 0, max: 10080, precision: 0, controlsPosition: 'right', class: '!w-full' }
      },
      {
        label: '超时升级',
        key: 'escalationEnabled',
        type: 'switch',
        props: { activeText: '开启', inactiveText: '关闭', inlinePrompt: true }
      },
      {
        label: '升级管理员（超时小时）',
        key: 'escalateAfterHours',
        type: 'number',
        span: 24,
        hidden: !selectedNode.value?.escalationEnabled,
        help: '超时达到该时长后，通知当前租户的审批管理员介入。',
        props: { min: 1, max: 720, precision: 0, controlsPosition: 'right', class: '!w-full' }
      },
      {
        label: '审批人类型',
        key: 'assignee.type',
        type: 'select',
        span: 24,
        props: { options: assigneeTypeOptions.value },
        help: '角色会在流程启动时解析为当前租户内的有效用户。'
      },
      {
        label: '指定用户',
        key: 'assignee.userIds',
        type: 'userSelect',
        span: 24,
        hidden: assigneeType !== 'users',
        help: '仅显示流程所属租户内的启用用户，可按昵称、邮箱或用户名搜索。',
        api: fetchWorkflowUserOptions,
        immediate: false,
        beforeFetch: (params) => ({ ...params, tenantId: form.data.tenantId }),
        shouldFetch: () => !isPlatformSuper.value || Boolean(form.data.tenantId),
        resultField: 'data',
        valueField: 'id',
        labelFn: (option) =>
          String(option.nickName || option.userName || option.userEmail || option.id),
        props: { multiple: true, filterable: true, collapseTags: true, collapseTagsTooltip: true }
      },
      {
        label: '指定角色',
        key: 'assignee.roleCodes',
        type: 'select',
        span: 24,
        hidden: assigneeType !== 'roles',
        api: fetchWorkflowRoleOptions,
        immediate: false,
        beforeFetch: (params) => ({ ...params, tenantId: form.data.tenantId }),
        shouldFetch: () => !isPlatformSuper.value || Boolean(form.data.tenantId),
        resultField: 'data',
        labelField: 'roleName',
        valueField: 'roleCode',
        props: { multiple: true, filterable: true, collapseTags: true, collapseTagsTooltip: true }
      },
      {
        label: '允许发起人自审',
        key: 'allowSelfApproval',
        type: 'switch',
        span: 24,
        help: '企业级审批建议默认关闭，保持职责分离。',
        props: { activeText: '允许', inactiveText: '禁止', inlinePrompt: true }
      },
      { label: '进入条件', key: 'conditionDivider', type: 'divider', span: 24 },
      {
        label: '条件运算符',
        key: 'condition.operator',
        type: 'select',
        props: { options: conditionOperatorOptions.value }
      },
      {
        label: '上下文字段',
        key: 'condition.field',
        type: 'select',
        hidden: conditionOperator === 'always',
        help: '字段来自当前业务的受控上下文契约，运行时由服务端从业务原单生成。',
        props: { options: contextFieldOptions.value, filterable: true, placeholder: '选择业务字段' }
      },
      {
        label: '比较值',
        key: 'condition.value',
        type: 'input',
        span: 24,
        hidden: ['always', 'not_empty'].includes(String(conditionOperator)),
        props: { placeholder: '数字、文本；in 运算可用英文逗号分隔' }
      }
    ]
  })

  function normalizeNodeOrder(): void {
    form.data.config.nodes.forEach((node, index) => (node.order = index + 1))
    selectedIndex.value = Math.min(selectedIndex.value, form.data.config.nodes.length - 1)
  }

  async function reloadAssigneeOptions(): Promise<void> {
    await nextTick()
    await Promise.all([
      nodeFormRef.value?.reloadOptions('assignee.userIds'),
      nodeFormRef.value?.reloadOptions('assignee.roleCodes')
    ])
  }

  function handleTenantChange(): void {
    form.data.config.nodes.forEach((node) => {
      node.assignee.userIds = []
      node.assignee.roleCodes = []
    })
    void reloadAssigneeOptions()
  }

  function handleBusinessTypeChange(): void {
    const allowedFields = new Set(contextFields.value.map((field) => field.key))
    form.data.config.nodes.forEach((node) => {
      if (node.condition.field && !allowedFields.has(node.condition.field)) {
        node.condition = { operator: 'always' }
      }
    })
  }

  function addNode(): void {
    form.data.config.nodes.push(createNode(form.data.config.nodes.length))
    selectedIndex.value = form.data.config.nodes.length - 1
    normalizeNodeOrder()
  }

  function removeNode(index: number): void {
    form.data.config.nodes.splice(index, 1)
    selectedIndex.value = Math.max(
      0,
      Math.min(selectedIndex.value, form.data.config.nodes.length - 1)
    )
    normalizeNodeOrder()
  }

  function openSimulator(): void {
    void simulatorDialogRef.value?.handleOpen({
      businessType: form.data.businessType,
      businessTypeLabel: String(businessTypeLabel.value),
      config: cloneDeep(toRaw(form.data.config))
    })
  }

  function getAssigneeSummary(node: Api.Workflow.WorkflowNode): string {
    const count =
      node.assignee.type === 'users'
        ? node.assignee.userIds?.length
        : node.assignee.roleCodes?.length
    const assignee =
      node.assignee.type === 'initiator'
        ? '发起人'
        : count
          ? `${count} 个${node.assignee.type === 'users' ? '用户' : '角色'}`
          : '待配置审批人'
    const decision =
      node.approvalMode === 'all'
        ? '全员通过'
        : node.approvalMode === 'percentage'
          ? `${node.approvalThresholdPercent || 67}% 通过`
          : '一人通过'
    return `${assignee} · ${decision}`
  }

  function normalizePayload(): DesignerForm {
    const payload = cloneDeep(toRaw(form.data))
    payload.code = trim(payload.code)
    payload.name = trim(payload.name)
    payload.description = trim(payload.description || '') || null
    payload.changeNote = trim(payload.changeNote || '') || null
    payload.config.nodes.forEach((node, index) => {
      node.order = index + 1
      node.name = trim(node.name)
      node.approvalThresholdPercent =
        node.approvalMode === 'percentage' ? Number(node.approvalThresholdPercent || 67) : 100
      node.rejectVetoEnabled = node.approvalMode === 'all' ? true : (node.rejectVetoEnabled ?? true)
      node.dueHours = Number(node.dueHours || 24)
      node.reminderBeforeMinutes = Number(node.reminderBeforeMinutes ?? 60)
      node.escalationEnabled = node.escalationEnabled ?? true
      node.escalateAfterHours = Number(node.escalateAfterHours || 4)
      node.assignee.userIds = node.assignee.type === 'users' ? node.assignee.userIds || [] : []
      node.assignee.roleCodes = node.assignee.type === 'roles' ? node.assignee.roleCodes || [] : []
      if (node.condition.operator === 'always') {
        node.condition = { operator: 'always' }
      } else if (node.condition.operator === 'not_empty') {
        delete node.condition.value
      } else if (node.condition.operator === 'in') {
        node.condition.value = Array.isArray(node.condition.value)
          ? node.condition.value
          : String(node.condition.value ?? '')
              .split(',')
              .map((value) => value.trim())
              .filter(Boolean)
      } else {
        const field = contextFields.value.find((item) => item.key === node.condition.field)
        if (field?.valueType === 'number' && node.condition.value !== '') {
          node.condition.value = Number(node.condition.value)
        }
      }
    })
    return payload
  }

  function validateNodes(): boolean {
    if (!form.data.config.nodes.length) {
      ElMessage.warning('请至少添加一个审批节点')
      return false
    }
    const allowedFields = new Set(contextFields.value.map((field) => field.key))
    for (const [index, node] of form.data.config.nodes.entries()) {
      if (!trim(node.name)) {
        ElMessage.warning(`请填写第 ${index + 1} 个节点的名称`)
        selectedIndex.value = index
        return false
      }
      const assigneeCount =
        node.assignee.type === 'users'
          ? node.assignee.userIds?.length
          : node.assignee.roleCodes?.length
      if (node.assignee.type !== 'initiator' && !assigneeCount) {
        ElMessage.warning(`请配置“${node.name}”的审批人`)
        selectedIndex.value = index
        return false
      }
      if (node.assignee.type === 'initiator' && !node.allowSelfApproval) {
        ElMessage.warning(`“${node.name}”指定发起人审批时，必须允许发起人自审`)
        selectedIndex.value = index
        return false
      }
      if (
        node.approvalMode === 'percentage' &&
        (!Number.isInteger(Number(node.approvalThresholdPercent)) ||
          Number(node.approvalThresholdPercent) < 1 ||
          Number(node.approvalThresholdPercent) > 100)
      ) {
        ElMessage.warning(`请为“${node.name}”配置 1 到 100 的整数通过比例`)
        selectedIndex.value = index
        return false
      }
      if (node.condition.operator !== 'always' && !trim(node.condition.field || '')) {
        ElMessage.warning(`请配置“${node.name}”的条件字段`)
        selectedIndex.value = index
        return false
      }
      if (node.condition.field && !allowedFields.has(node.condition.field)) {
        ElMessage.warning(`“${node.name}”使用了当前业务不支持的条件字段`)
        selectedIndex.value = index
        return false
      }
      if (
        node.condition.operator === 'in' &&
        !String(node.condition.value ?? '')
          .split(',')
          .filter(Boolean).length
      ) {
        ElMessage.warning(`请为“${node.name}”填写至少一个匹配值`)
        selectedIndex.value = index
        return false
      }
    }
    return true
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await baseFormRef.value?.validate()
    } catch {
      return false
    }
    if (!validateNodes()) return false
    await saveWorkflowDefinition(normalizePayload())
    emit('success')
    return true
  }

  async function handleOpen(row?: Api.Workflow.WorkflowDefinitionRecord): Promise<void> {
    form.data = createInitialForm()
    selectedIndex.value = 0
    identityLocked.value = false
    await drawerRef.value?.handleOpen(row, {
      title: row ? '编辑审批流程' : '新建审批流程',
      contentHeight: 'calc(100vh - 142px)',
      confirmText: '保存草稿',
      onConfirm: handleSubmit
    })
    await nextTick()
    baseFormRef.value?.clearValidate()
    if (!row?.id) {
      if (!isPlatformSuper.value) await reloadAssigneeOptions()
      return
    }

    drawerRef.value?.setLoading(true)
    try {
      const response = await fetchWorkflowDefinitionDetail(row.id)
      const detail = response.data
      if (!detail) return
      identityLocked.value = Boolean(detail.currentVersionId)
      const versions = [...(detail.versions || [])].sort((a, b) => b.versionNo - a.versionNo)
      const editableVersion =
        versions.find((version) => version.status === 'draft') ||
        versions.find((version) => version.id === detail.currentVersionId) ||
        versions[0]
      form.data = {
        id: detail.id,
        tenantId: detail.tenantId,
        code: detail.code,
        name: detail.name,
        businessType: detail.businessType,
        description: detail.description || '',
        changeNote: editableVersion?.changeNote || '',
        config: cloneDeep(editableVersion?.config || { nodes: [], allowAutoApprove: false })
      }
      form.data.config.allowAutoApprove = form.data.config.allowAutoApprove ?? false
      form.data.config.nodes = form.data.config.nodes.map((node) => ({
        ...node,
        approvalThresholdPercent: node.approvalThresholdPercent ?? 67,
        rejectVetoEnabled: node.approvalMode === 'all' ? true : (node.rejectVetoEnabled ?? true),
        reminderBeforeMinutes: node.reminderBeforeMinutes ?? 60,
        escalationEnabled: node.escalationEnabled ?? true,
        escalateAfterHours: node.escalateAfterHours ?? 4
      }))
      normalizeNodeOrder()
      await reloadAssigneeOptions()
    } finally {
      drawerRef.value?.setLoading(false)
    }
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .workflow-designer__title {
    display: flex;
    gap: 12px;
    align-items: center;

    > span {
      display: grid;
      place-items: center;
      width: 38px;
      height: 38px;
      font-size: 20px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);
    }

    div {
      display: grid;
      gap: 2px;
    }

    strong {
      font-size: 16px;
      color: var(--art-gray-900);
    }

    small {
      font-size: 12px;
      color: var(--art-gray-500);
    }
  }

  .workflow-designer {
    display: grid;
    gap: 14px;
    padding: 2px;

    &__base,
    &__preview,
    &__canvas {
      padding: 18px;
    }

    &__section-header {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 16px;

      p {
        margin: 5px 0 0;
        font-size: 13px;
        color: var(--art-gray-500);
      }
    }

    &__preview-actions {
      display: flex;
      flex: 0 0 auto;
      gap: 10px;
      align-items: center;
    }

    &__canvas-actions {
      display: flex;
      flex: 0 0 auto;
      gap: 12px;
      align-items: center;

      > span {
        font-size: 12px;
        color: var(--art-gray-600);
        white-space: nowrap;
      }
    }

    &__workspace {
      display: grid;
      grid-template-columns: minmax(240px, 30%) minmax(0, 1fr);
      height: clamp(430px, 55vh, 560px);
      overflow: hidden;
      border: 1px solid var(--art-gray-200);
      border-radius: calc(var(--el-border-radius-base) + 2px);
    }

    &__nodes {
      display: grid;
      grid-template-rows: auto minmax(0, 1fr);
      min-height: 0;
      background: var(--art-gray-50);
      border-right: 1px solid var(--art-gray-200);
    }

    &__nodes-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 12px 14px;
      background: color-mix(in srgb, var(--theme-color) 4%, var(--el-bg-color));
      border-bottom: 1px solid var(--art-gray-200);

      span {
        font-size: 13px;
        font-weight: 600;
        color: var(--art-gray-800);
      }

      small {
        font-size: 12px;
        color: var(--art-gray-600);
      }
    }

    &__nodes-content {
      padding: 14px;
    }

    &__node {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 30px;
      gap: 4px;
      align-items: center;
      width: 100%;
      padding: 5px 6px 5px 0;
      margin-bottom: 9px;
      color: var(--art-gray-700);
      text-align: left;
      background: var(--art-main-bg-color);
      border: 1px solid var(--art-gray-200);
      border-radius: var(--el-border-radius-base);
      transition: 0.2s ease;

      &.is-active {
        background: var(--el-color-primary-light-9);
      }

      > .el-button {
        margin: 0;
      }
    }

    &__node-select {
      display: grid;
      grid-template-columns: 20px 28px minmax(0, 1fr);
      gap: 8px;
      align-items: center;
      min-width: 0;
      padding: 6px 4px 6px 8px;
      color: inherit;
      text-align: left;
      cursor: pointer;
      background: transparent;
      border: 0;

      &:focus-visible {
        outline: 0;
      }

      > i {
        display: grid;
        place-items: center;
        width: 26px;
        height: 26px;
        font-style: normal;
        color: #fff;
        background: var(--el-color-primary);
        border-radius: 50%;
      }

      > span:nth-child(3) {
        display: grid;
        gap: 3px;
        min-width: 0;
      }

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      small {
        font-size: 12px;
        color: var(--art-gray-600);
      }
    }

    &__drag {
      color: var(--art-gray-400);
      cursor: grab;
    }

    &__editor {
      min-width: 0;
      min-height: 0;
    }

    &__editor-content {
      padding: 20px;
    }

    &__editor-heading {
      display: flex;
      gap: 11px;
      align-items: center;
      padding-bottom: 15px;
      margin-bottom: 14px;
      border-bottom: 1px solid var(--art-gray-200);

      > span {
        display: grid;
        place-items: center;
        width: 36px;
        height: 36px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: 50%;
      }

      div {
        display: grid;
        gap: 2px;
      }

      strong {
        color: var(--art-gray-900);
      }

      small {
        font-size: 12px;
        color: var(--art-gray-600);
      }
    }

    :global([data-box-mode='border-mode']) &__node:hover,
    :global([data-box-mode='border-mode']) &__node:focus-within,
    :global([data-box-mode='border-mode']) &__node.is-active {
      border-color: var(--theme-color);
      box-shadow: var(--art-themed-action-active-shadow);
    }

    :global([data-box-mode='shadow-mode']) &__node:hover,
    :global([data-box-mode='shadow-mode']) &__node:focus-within,
    :global([data-box-mode='shadow-mode']) &__node.is-active {
      border-color: transparent;
      box-shadow: var(--art-themed-action-hover-shadow);
    }
  }

  @media (width <= 860px) {
    .workflow-designer__section-header {
      flex-wrap: wrap;
    }

    .workflow-designer__preview-actions {
      flex-wrap: wrap;
    }

    .workflow-designer__canvas-actions {
      flex-wrap: wrap;
    }

    .workflow-designer__workspace {
      grid-template-columns: 1fr;
    }

    .workflow-designer__nodes {
      max-height: 260px;
      border-right: 0;
      border-bottom: 1px solid var(--art-gray-200);
    }
  }
</style>
