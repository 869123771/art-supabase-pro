<template>
  <ArtDialog ref="dialogRef" size="lg">
    <div class="workflow-delegation">
      <section class="workflow-delegation__intro">
        <span><ArtSvgIcon icon="ri:user-shared-line" /></span>
        <div>
          <strong>审批委托</strong>
          <p>请假或暂时离岗时，把时间段内的新待办和当前待办交给同租户同事处理。</p>
        </div>
      </section>

      <ArtSectionCard class="workflow-delegation__create" preserve-content-structure>
        <template #header>
          <div class="workflow-delegation__heading">
            <div>
              <ArtSectionTitle :show-line="false">新建委托</ArtSectionTitle>
              <p>委托不能重叠，最长 180 天；受托人不能再次代表你转委托。</p>
            </div>
            <ElTag type="warning" effect="plain" round>有审计记录</ElTag>
          </div>
        </template>
        <ArtForm
          ref="formRef"
          v-model="form.data"
          :items="form.items"
          :rules="form.rules"
          :show-reset="false"
          :show-submit="false"
          label-position="top"
        />
      </ArtSectionCard>

      <ArtSectionCard
        class="workflow-delegation__history"
        :loading="state.loading"
        loading-mode="mask"
        preserve-content-structure
      >
        <template #header>
          <div class="workflow-delegation__heading">
            <div>
              <ArtSectionTitle :show-line="false">委托记录</ArtSectionTitle>
              <p>我发出的委托可以撤销；收到的委托用于说明待办来源。</p>
            </div>
            <ElTooltip content="刷新委托记录" placement="top">
              <ArtIconButton
                icon="ri:refresh-line"
                circle
                label="刷新委托记录"
                :loading="state.loading"
                @click="loadData"
              />
            </ElTooltip>
          </div>
        </template>

        <ArtEmptyState
          v-if="!state.loading && !state.records.length"
          title="暂无委托记录"
          description="需要离岗时，可在上方创建审批委托。"
          icon="ri:user-shared-line"
        />
        <ElScrollbar v-else max-height="280px">
          <div class="workflow-delegation__list">
            <article v-for="record in state.records" :key="record.id">
              <div class="workflow-delegation__record-icon">
                <ArtSvgIcon
                  :icon="
                    record.delegatorUserId === state.userId
                      ? 'ri:share-forward-line'
                      : 'ri:inbox-unarchive-line'
                  "
                />
              </div>
              <div class="workflow-delegation__record-main">
                <div>
                  <strong>
                    {{ record.delegatorUserId === state.userId ? '委托给' : '来自' }}
                    {{ counterpartName(record) }}
                  </strong>
                  <ElTag :type="statusOf(record).type" size="small" effect="light" round>
                    {{ statusOf(record).label }}
                  </ElTag>
                </div>
                <span>{{ formatPeriod(record) }}</span>
                <p>{{ record.reason }}</p>
                <small v-if="record.revokeReason">撤销原因：{{ record.revokeReason }}</small>
              </div>
              <ElButton
                v-if="canRevoke(record)"
                type="danger"
                plain
                size="small"
                @click="handleRevoke(record)"
              >
                撤销
              </ElButton>
            </article>
          </div>
        </ElScrollbar>
      </ArtSectionCard>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import ArtSectionCard from '@/components/core/surfaces/art-section-card/index.vue'
  import dayjs from 'dayjs'
  import type { FormRules, TagProps } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import type { ArtUserSelectOption } from '@/components/core/forms/art-user-select/types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtSectionTitle from '@/components/core/surfaces/art-section-title/index.vue'
  import ArtEmptyState from '@/components/core/feedback/art-empty-state/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import {
    createWorkflowDelegation,
    fetchWorkflowDelegations,
    fetchWorkflowUserOptions,
    revokeWorkflowDelegation
  } from '@/api/workflow'

  defineOptions({ name: 'WorkflowDelegationDialog' })

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }
  interface DelegationFormData {
    delegateUserId: string
    period: string[]
    reason: string
  }

  const emit = defineEmits<{ (event: 'success'): void }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<FormExpose>()
  const { promptReason } = useArtFeedback()
  const state = reactive({
    userId: '',
    tenantId: '',
    loading: false,
    records: [] as Api.Workflow.WorkflowDelegationRecord[],
    users: [] as Api.Workflow.WorkflowUserOption[]
  })
  const form = reactive<{
    data: DelegationFormData
    items: FormItem[]
    rules: FormRules
  }>({
    data: { delegateUserId: '', period: [], reason: '' },
    items: [],
    rules: {
      delegateUserId: [{ required: true, message: '请选择受托人', trigger: 'change' }],
      period: [{ required: true, message: '请选择委托时间段', trigger: 'change' }],
      reason: [
        { required: true, message: '请填写委托原因', trigger: 'blur' },
        { min: 4, max: 300, message: '委托原因应为 4 至 300 个字符', trigger: 'blur' }
      ]
    }
  })

  function displayName(user?: Api.Workflow.WorkflowActorProfile | null): string {
    return user?.nickName || user?.userName || user?.userEmail || '--'
  }

  function toUserSelectOption(user: Api.Workflow.WorkflowUserOption): ArtUserSelectOption {
    return {
      value: user.id,
      label: displayName(user),
      avatar: user.avatar,
      userName: user.userName,
      nickName: user.nickName,
      userEmail: user.userEmail
    }
  }

  function rebuildItems(): void {
    form.items = [
      {
        label: '受托人',
        key: 'delegateUserId',
        type: 'userSelect',
        span: 12,
        props: {
          placeholder: '选择同租户在职同事',
          filterable: true,
          options: state.users.filter((user) => user.id !== state.userId).map(toUserSelectOption)
        }
      },
      {
        label: '委托时间',
        key: 'period',
        type: 'date',
        span: 12,
        props: {
          type: 'datetimerange',
          startPlaceholder: '开始时间',
          endPlaceholder: '结束时间',
          format: 'YYYY-MM-DD HH:mm',
          valueFormat: 'YYYY-MM-DD HH:mm:ss',
          defaultTime: [new Date(2000, 0, 1, 9), new Date(2000, 0, 1, 18)]
        }
      },
      {
        label: '委托原因',
        key: 'reason',
        type: 'input',
        span: 24,
        props: {
          type: 'textarea',
          rows: 3,
          maxlength: 300,
          showWordLimit: true,
          placeholder: '例如：8 月 10 日至 12 日休假，由李经理代为处理费用审批'
        }
      }
    ]
  }

  function statusOf(record: Api.Workflow.WorkflowDelegationRecord): {
    label: string
    type: TagProps['type']
  } {
    if (record.revokedAt) return { label: '已撤销', type: 'info' }
    if (dayjs(record.endsAt).isBefore(dayjs())) return { label: '已结束', type: 'info' }
    if (dayjs(record.startsAt).isAfter(dayjs())) return { label: '待生效', type: 'warning' }
    return { label: '生效中', type: 'success' }
  }

  function counterpartName(record: Api.Workflow.WorkflowDelegationRecord): string {
    return record.delegatorUserId === state.userId
      ? displayName(record.delegate)
      : displayName(record.delegator)
  }

  function formatPeriod(record: Api.Workflow.WorkflowDelegationRecord): string {
    return `${dayjs(record.startsAt).format('YYYY-MM-DD HH:mm')} 至 ${dayjs(record.endsAt).format('YYYY-MM-DD HH:mm')}`
  }

  function canRevoke(record: Api.Workflow.WorkflowDelegationRecord): boolean {
    return (
      record.delegatorUserId === state.userId &&
      !record.revokedAt &&
      dayjs(record.endsAt).isAfter(dayjs())
    )
  }

  async function loadData(): Promise<void> {
    if (!state.userId) return
    state.loading = true
    try {
      const [delegations, users] = await Promise.all([
        fetchWorkflowDelegations(state.userId),
        fetchWorkflowUserOptions({ tenantId: state.tenantId })
      ])
      state.records = delegations.data ?? []
      state.users = users.data ?? []
      rebuildItems()
    } finally {
      state.loading = false
    }
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    const [startsAt, endsAt] = form.data.period
    if (!startsAt || !endsAt) return false
    await createWorkflowDelegation({
      delegateUserId: form.data.delegateUserId,
      startsAt: dayjs(startsAt).toISOString(),
      endsAt: dayjs(endsAt).toISOString(),
      reason: form.data.reason.trim()
    })
    Object.assign(form.data, { delegateUserId: '', period: [], reason: '' })
    await loadData()
    emit('success')
    return true
  }

  async function handleRevoke(record: Api.Workflow.WorkflowDelegationRecord): Promise<void> {
    const reason = await promptReason(
      '撤销后，仍未处理且由该委托产生的待办会退回原审批人。',
      '撤销委托',
      { maxLength: 300 }
    )
    await revokeWorkflowDelegation(record.id, reason)
    await loadData()
    emit('success')
  }

  async function handleOpen(userId: string, tenantId: string): Promise<void> {
    state.userId = userId
    state.tenantId = tenantId
    Object.assign(form.data, { delegateUserId: '', period: [], reason: '' })
    await dialogRef.value?.handleOpen(undefined, {
      title: '审批委托与离岗安排',
      subtitle: '只改变审批席位的实际处理人，不改变流程规则和通过条件。',
      confirmText: '创建委托',
      contentMaxHeight: '60vh',
      onOpen: async () => {
        await nextTick()
        formRef.value?.clearValidate()
        await loadData()
      },
      onConfirm: handleSubmit
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .workflow-delegation {
    display: grid;
    gap: 14px;

    :deep(.el-date-editor--datetimerange) {
      width: 100%;
      min-width: 0;
    }

    &__intro {
      display: flex;
      gap: 12px;
      align-items: center;
      min-width: 0;
      padding: 14px 16px;
      background: linear-gradient(
        135deg,
        var(--el-color-primary-light-9),
        var(--default-box-color)
      );
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: var(--el-border-radius-base);

      > span {
        display: grid;
        flex: 0 0 auto;
        place-items: center;
        width: 42px;
        height: 42px;
        font-size: 21px;
        color: var(--el-color-primary);
        background: var(--default-box-color);
        border-radius: 50%;
      }

      div {
        display: grid;
        gap: 4px;
        min-width: 0;
      }

      strong {
        font-size: 15px;
        color: var(--art-gray-900);
      }

      p {
        margin: 0;
        font-size: 13px;
        line-height: 1.6;
        color: var(--art-gray-600);
      }
    }

    &__create,
    &__history {
      width: 100%;
      min-width: 0;
      padding: 16px;
    }

    &__heading {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 14px;

      > div {
        display: grid;
        gap: 4px;
      }

      p {
        margin: 0;
        font-size: 12px;
        line-height: 1.5;
        color: var(--art-gray-500);
      }
    }

    &__history {
      min-height: 190px;
    }

    &__list {
      display: grid;
      gap: 10px;
      padding-right: 8px;
    }

    &__list article {
      display: flex;
      gap: 12px;
      align-items: flex-start;
      padding: 12px;
      background: var(--art-gray-50);
      border: 1px solid var(--art-gray-200);
      border-radius: var(--el-border-radius-base);
    }

    &__record-icon {
      display: grid;
      flex: 0 0 auto;
      place-items: center;
      width: 34px;
      height: 34px;
      color: var(--el-color-primary);
      background: var(--default-box-color);
      border-radius: 50%;
    }

    &__record-main {
      display: grid;
      flex: 1;
      gap: 4px;
      min-width: 0;

      > div {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        align-items: center;
      }

      strong {
        color: var(--art-gray-900);
      }

      span,
      small {
        font-size: 12px;
        color: var(--art-gray-500);
      }

      p {
        margin: 2px 0 0;
        font-size: 13px;
        line-height: 1.5;
        color: var(--art-gray-700);
        overflow-wrap: anywhere;
      }
    }
  }

  @media only screen and (width <= 680px) {
    .workflow-delegation {
      :deep(.art-form .el-col-xs-12) {
        flex: 0 0 100%;
        max-width: 100%;
      }

      &__heading,
      &__list article {
        align-items: stretch;
      }

      &__list article {
        flex-wrap: wrap;
      }

      &__record-main {
        flex-basis: calc(100% - 48px);
      }
    }
  }
</style>
