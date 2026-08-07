<template>
  <ArtDialog ref="dialogRef" size="sm">
    <div :class="['workflow-action', `is-${state.action}`]">
      <div class="workflow-action__summary">
        <span
          ><ArtSvgIcon
            :icon="state.action === 'approve' ? 'ri:check-double-line' : 'ri:close-circle-line'"
        /></span>
        <div>
          <strong>
            {{
              state.platformOverride
                ? state.action === 'approve'
                  ? '代为通过审批'
                  : '代为驳回申请'
                : state.action === 'approve'
                  ? '通过审批'
                  : '驳回申请'
            }}
          </strong>
          <small>
            {{ state.task?.instance?.businessTitle || '--' }}
            <template v-if="state.platformOverride && state.task?.tenant?.tenantName">
              · {{ state.task.tenant.tenantName }}
            </template>
          </small>
        </div>
      </div>
      <div v-if="state.platformOverride" class="workflow-action__override-warning">
        <ArtSvgIcon icon="ri:shield-user-line" />
        <div>
          <strong>平台超管代审批</strong>
          <span>
            您将代替“{{
              state.task?.assigneeNameSnapshot || '原审批人'
            }}”作出本次决定；实际操作人、原审批人和干预原因都会写入审计轨迹。
          </span>
        </div>
      </div>
      <ArtForm
        ref="formRef"
        v-model="form"
        :items="formItems"
        :rules="formRules"
        :show-reset="false"
        :show-submit="false"
        label-position="top"
      />
      <div class="workflow-action__notice">
        <ArtSvgIcon icon="ri:information-line" />
        <span>{{ actionNotice }}</span>
      </div>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { actWorkflowTask } from '@/api/workflow'

  defineOptions({ name: 'WorkflowActionDialog' })

  type WorkflowAction = 'approve' | 'reject'
  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ (event: 'success', action: WorkflowAction): void }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<FormExpose>()
  const state = reactive<{
    task?: Api.Workflow.WorkflowTaskRecord
    action: WorkflowAction
    platformOverride: boolean
  }>({
    task: undefined,
    action: 'approve',
    platformOverride: false
  })
  const form = reactive({ comment: '' })

  const formItems = computed<FormItem[]>(() => [
    {
      label: state.platformOverride
        ? '代审批干预原因'
        : state.action === 'approve'
          ? '审批意见（选填）'
          : '驳回原因',
      key: 'comment',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 4,
        maxlength: 500,
        showWordLimit: true,
        placeholder: state.platformOverride
          ? '请说明为什么需要由平台超级管理员代为处理（至少4个字符）'
          : state.action === 'approve'
            ? '可补充本次审批意见'
            : '请清晰说明驳回原因，便于发起人调整'
      }
    }
  ])
  const formRules = computed<FormRules>(() => ({
    comment: state.platformOverride
      ? [
          { required: true, message: '请填写代审批干预原因', trigger: 'blur' },
          { min: 4, message: '干预原因至少填写4个字符', trigger: 'blur' }
        ]
      : state.action === 'reject'
        ? [{ required: true, message: '请填写驳回原因', trigger: 'blur' }]
        : []
  }))
  const decisionRuleText = computed(() => {
    const task = state.task
    if (!task) return '当前节点规则'
    if (task.approvalMode === 'all') return '全员通过'
    if (task.approvalMode === 'percentage') {
      return `${task.approvalThresholdPercent}% 比例会签`
    }
    return '或签（一人通过）'
  })
  const actionNotice = computed(() => {
    if (state.platformOverride) {
      return `本次只代替当前审批席位作出决定，仍严格遵循${decisionRuleText.value}和原有否决规则，不会强制结束整条流程。`
    }
    if (state.action === 'approve') {
      return `本节点采用${decisionRuleText.value}；达到通过条件后进入下一节点，最后节点通过时同步业务单据。`
    }
    return state.task?.rejectVetoEnabled
      ? '本节点已开启一票否决；确认驳回后流程立即结束，并同步业务单据为驳回状态。'
      : '本节点采用容错计算；本次驳回会保留审计记录，仅在剩余审批人已无法达到通过条件时结束流程。'
  })

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    if (!state.task) return false
    await actWorkflowTask({
      taskId: state.task.id,
      action: state.action,
      comment: form.comment.trim() || null
    })
    emit('success', state.action)
    return true
  }

  async function handleOpen(
    task: Api.Workflow.WorkflowTaskRecord,
    action: WorkflowAction,
    options: { platformOverride?: boolean } = {}
  ): Promise<void> {
    state.task = task
    state.action = action
    state.platformOverride = Boolean(options.platformOverride)
    form.comment = ''
    await dialogRef.value?.handleOpen(undefined, {
      title: state.platformOverride
        ? action === 'approve'
          ? '代为通过审批'
          : '代为驳回申请'
        : action === 'approve'
          ? '通过审批'
          : '驳回申请',
      confirmText: state.platformOverride
        ? action === 'approve'
          ? '确认代为通过'
          : '确认代为驳回'
        : action === 'approve'
          ? '确认通过'
          : '确认驳回',
      onConfirm: handleSubmit
    })
    await nextTick()
    formRef.value?.clearValidate()
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .workflow-action {
    display: grid;
    gap: 16px;

    &__summary {
      display: flex;
      gap: 12px;
      align-items: center;
      padding: 14px;
      background: var(--el-color-success-light-9);
      border: 1px solid var(--el-color-success-light-7);
      border-radius: var(--el-border-radius-base);

      > span {
        display: grid;
        width: 38px;
        height: 38px;
        color: var(--el-color-success);
        background: var(--default-box-color);
        border-radius: 50%;
        place-items: center;
        font-size: 20px;
      }
      div {
        display: grid;
        min-width: 0;
        gap: 3px;
      }
      strong {
        color: var(--art-gray-900);
      }
      small {
        overflow: hidden;
        color: var(--art-gray-500);
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &.is-reject &__summary {
      background: var(--el-color-danger-light-9);
      border-color: var(--el-color-danger-light-7);
    }
    &.is-reject &__summary > span {
      color: var(--el-color-danger);
    }

    &__override-warning {
      display: flex;
      gap: 10px;
      align-items: flex-start;
      padding: 12px 14px;
      color: var(--el-color-warning-dark-2);
      background: var(--el-color-warning-light-9);
      border: 1px solid var(--el-color-warning-light-7);
      border-radius: var(--el-border-radius-base);

      > svg {
        flex: 0 0 auto;
        margin-top: 2px;
        font-size: 18px;
      }
      > div {
        display: grid;
        gap: 4px;
      }
      strong {
        color: var(--art-gray-900);
        font-size: 13px;
      }
      span {
        font-size: 12px;
        line-height: 1.55;
      }
    }

    &__notice {
      display: flex;
      gap: 7px;
      align-items: flex-start;
      padding: 10px 12px;
      color: var(--art-gray-500);
      font-size: 12px;
      line-height: 1.55;
      background: var(--art-gray-50);
      border-radius: var(--el-border-radius-base);

      svg {
        flex: 0 0 auto;
        margin-top: 2px;
        color: var(--el-color-primary);
      }
    }
  }
</style>
