<template>
  <ArtDialog ref="dialogRef" size="lg">
    <div class="execution-dialog">
      <section class="execution-dialog__summary art-card-xs">
        <span class="execution-dialog__icon" :class="`is-${action}`">
          <ArtSvgIcon :icon="actionMeta.icon" />
        </span>
        <div>
          <small>{{ actionMeta.eyebrow }}</small>
          <strong>{{ currentRow?.orderNo || '运输运单' }}</strong>
          <p>{{ actionMeta.description }}</p>
        </div>
        <ElTag effect="light" round>{{ actionMeta.tag }}</ElTag>
      </section>

      <ElAlert
        class="execution-dialog__alert"
        :title="flowAlert"
        :type="
          context?.needsReturnCompletion && currentRow?.waybillStatus === 'completed'
            ? 'warning'
            : 'info'
        "
        :closable="false"
        show-icon
      />

      <ArtForm
        ref="formRef"
        v-model="form.data"
        :items="form.items"
        :rules="form.rules"
        :span="12"
        :gutter="20"
        label-position="top"
        :show-reset="false"
        :show-submit="false"
        class="execution-dialog__form art-card-xs"
      >
        <template #photoUrls>
          <ArtUploadImage
            v-model="form.data.photoUrls"
            :title="action === 'completion' ? '收车照片' : '发车照片'"
            :size="92"
            :limit="5"
            multiple
          />
        </template>
        <template #receiptUrls>
          <ArtUploadImage
            v-model="form.data.receiptUrls"
            title="签收回单"
            :size="92"
            :limit="5"
            multiple
          />
        </template>
        <template #signatureUrls>
          <ArtUploadImage
            v-model="form.data.signatureUrls"
            title="签字确认照片"
            :size="92"
            :limit="3"
            multiple
          />
        </template>
      </ArtForm>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { ComputedRef } from 'vue'
  import type { FormRules } from 'element-plus'
  import { ElMessage } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import {
    completeWaybillExecution,
    fetchWaybillExecutionContext,
    recordWaybillDeparture,
    signWaybill
  } from '@/api/tms'
  import type { WaybillRecord } from './waybill-shared'

  defineOptions({ name: 'TmsWaybillExecutionOperationDialog' })

  type ExecutionAction = Api.Tms.Waybill.ExecutionAction

  interface OpenData {
    row: WaybillRecord
    action: ExecutionAction
  }

  interface ExecutionForm {
    occurredAt: string
    odometerKm: number | null
    signerName: string
    photoUrls: string[]
    receiptUrls: string[]
    signatureUrls: string[]
    remark: string
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: ExecutionForm
    items: ComputedRef<FormItem[]>
    rules: FormRules<ExecutionForm>
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<OpenData>>()
  const formRef = ref<FormExpose>()
  const currentRow = shallowRef<WaybillRecord>()
  const action = ref<ExecutionAction>('departure')
  const context = shallowRef<Api.Tms.Waybill.ExecutionContext>()

  const actionMetaMap = {
    departure: {
      title: '确认发车',
      eyebrow: 'DEPARTURE RECORD',
      tag: '装货后发车',
      icon: 'ri:send-plane-line',
      description: '记录实际发车时间、出车里程与车辆现场照片。',
      alert: '发车时间必须晚于装货完成时间；出车里程将用于最终核算本次行驶里程。'
    },
    signature: {
      title: '签收',
      eyebrow: 'DELIVERY SIGNATURE',
      tag: '独立签收节点',
      icon: 'ri:signature-line',
      description: '上传回单与签字确认照片，PC 和手机端实时同步。',
      alert: '签收后运单进入“已签收”，仍需确认收车时间和里程后才会完成。'
    },
    completion: {
      title: '确认完成运单',
      eyebrow: 'RETURN & CLOSE',
      tag: '运输闭环',
      icon: 'ri:checkbox-circle-line',
      description: '记录收车时间、收车里程与车辆照片，完成运输闭环。',
      alert: '收车里程不能小于出车里程；提交后将同步生成该车辆的运单里程记录。'
    }
  } as const

  const actionMeta = computed(() => actionMetaMap[action.value])
  const flowAlert = computed(() => {
    if (
      action.value === 'completion' &&
      context.value?.needsReturnCompletion &&
      currentRow.value?.waybillStatus === 'completed'
    ) {
      return '检测到历史完成状态缺少回场档案。本次提交将补齐回场时间、里程、照片和车辆里程记录。'
    }
    if (action.value === 'completion' && context.value?.record?.departureOdometerKm != null) {
      return `${actionMeta.value.alert} 本次出车里程为 ${context.value.record.departureOdometerKm} 公里。`
    }
    return actionMeta.value.alert
  })

  const createInitialForm = (): ExecutionForm => ({
    occurredAt: dayjs().format('YYYY-MM-DD HH:mm:ss'),
    odometerKm: null,
    signerName: '',
    photoUrls: [],
    receiptUrls: [],
    signatureUrls: [],
    remark: ''
  })

  const form = reactive<FormGroup>({
    data: createInitialForm(),
    rules: {
      occurredAt: [{ required: true, message: '请选择业务时间', trigger: 'change' }],
      odometerKm: [
        { required: true, message: '请输入车辆里程', trigger: 'blur' },
        { type: 'number', min: 0, message: '车辆里程不能小于 0', trigger: 'blur' }
      ],
      signerName: [{ required: true, message: '请填写签收人', trigger: 'blur' }],
      photoUrls: [{ type: 'array', required: true, min: 1, message: '请至少上传 1 张照片' }],
      receiptUrls: [{ type: 'array', required: true, min: 1, message: '请至少上传 1 张回单' }],
      signatureUrls: [
        { type: 'array', required: true, min: 1, message: '请至少上传 1 张签字确认照片' }
      ]
    },
    items: computed<FormItem[]>(() => {
      const commonTime: FormItem = {
        label:
          action.value === 'departure'
            ? '实际发车时间'
            : action.value === 'signature'
              ? '签收时间'
              : '收车时间',
        key: 'occurredAt',
        type: 'date',
        props: {
          type: 'datetime',
          valueFormat: 'YYYY-MM-DD HH:mm:ss',
          class: '!w-full',
          placeholder: '请选择时间'
        }
      }
      const remark: FormItem = {
        label: '备注',
        key: 'remark',
        type: 'textarea',
        span: 24,
        props: { rows: 3, maxlength: 300, showWordLimit: true, placeholder: '可填写现场说明' }
      }

      if (action.value === 'signature') {
        return [
          { label: '签收信息', key: 'section', type: 'divider', span: 24 },
          commonTime,
          {
            label: '签收人',
            key: 'signerName',
            type: 'input',
            props: { maxlength: 50, placeholder: '请输入实际签收人' }
          },
          { label: '签收回单', key: 'receiptUrls', span: 24 },
          { label: '签字确认照片', key: 'signatureUrls', span: 24 },
          remark
        ]
      }

      return [
        {
          label: action.value === 'departure' ? '发车信息' : '收车信息',
          key: 'section',
          type: 'divider',
          span: 24
        },
        commonTime,
        {
          label: action.value === 'departure' ? '出车里程（公里）' : '收车里程（公里）',
          key: 'odometerKm',
          type: 'number',
          props: { min: 0, precision: 1, step: 1, controlsPosition: 'right', class: '!w-full' }
        },
        {
          label: action.value === 'departure' ? '发车照片' : '收车照片',
          key: 'photoUrls',
          span: 24
        },
        remark
      ]
    })
  })

  async function loadContext(): Promise<void> {
    const waybillId = currentRow.value?.driverWaybillId
    if (!waybillId) throw new Error('该订单尚未生成司机运单')
    const result = await fetchWaybillExecutionContext(waybillId)
    context.value = result.data ?? undefined
    const record = result.data?.record
    Object.assign(form.data, createInitialForm(), {
      occurredAt:
        action.value === 'departure' && record?.departureTime
          ? dayjs(record.departureTime).format('YYYY-MM-DD HH:mm:ss')
          : action.value === 'signature' && record?.signedAt
            ? dayjs(record.signedAt).format('YYYY-MM-DD HH:mm:ss')
            : action.value === 'completion' && record?.returnTime
              ? dayjs(record.returnTime).format('YYYY-MM-DD HH:mm:ss')
              : dayjs().format('YYYY-MM-DD HH:mm:ss'),
      odometerKm:
        action.value === 'departure'
          ? (record?.departureOdometerKm ?? null)
          : (record?.returnOdometerKm ?? null),
      signerName: record?.signerName ?? currentRow.value?.receivingContactName ?? '',
      photoUrls:
        action.value === 'departure'
          ? (record?.departurePhotoUrls ?? [])
          : (record?.returnPhotoUrls ?? []),
      receiptUrls: record?.receiptUrls ?? [],
      signatureUrls: record?.signatureUrls ?? [],
      remark:
        action.value === 'departure'
          ? (record?.departureRemark ?? '')
          : action.value === 'signature'
            ? (record?.signatureRemark ?? '')
            : (record?.completionRemark ?? '')
    })
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    const waybillId = currentRow.value?.driverWaybillId
    if (!waybillId) return false

    const occurredAt = dayjs(form.data.occurredAt)
    if (!occurredAt.isValid()) {
      ElMessage.warning('业务时间格式无效，请重新选择')
      return false
    }
    const occurredAtIso = occurredAt.toISOString()

    if (action.value === 'completion') {
      const departureOdometer = Number(context.value?.record?.departureOdometerKm ?? 0)
      if (Number(form.data.odometerKm) < departureOdometer) {
        ElMessage.warning(`收车里程不能小于出车里程 ${departureOdometer} 公里`)
        return false
      }
      const signedAt = context.value?.record?.signedAt
      if (signedAt && occurredAt.isBefore(dayjs(signedAt))) {
        ElMessage.warning('收车时间不能早于签收时间')
        return false
      }
    }

    if (action.value === 'departure') {
      await recordWaybillDeparture({
        waybillId,
        departureTime: occurredAtIso,
        odometerKm: Number(form.data.odometerKm),
        photoUrls: [...form.data.photoUrls],
        remark: form.data.remark.trim() || null
      })
    } else if (action.value === 'signature') {
      await signWaybill({
        waybillId,
        signedAt: occurredAtIso,
        signerName: form.data.signerName.trim(),
        receiptUrls: [...form.data.receiptUrls],
        signatureUrls: [...form.data.signatureUrls],
        remark: form.data.remark.trim() || null
      })
    } else {
      await completeWaybillExecution({
        waybillId,
        returnTime: occurredAtIso,
        returnOdometerKm: Number(form.data.odometerKm),
        photoUrls: [...form.data.photoUrls],
        remark: form.data.remark.trim() || null
      })
    }
    emit('success')
    return true
  }

  async function resetForm(): Promise<void> {
    currentRow.value = undefined
    context.value = undefined
    Object.assign(form.data, createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function handleOpen(data: OpenData): Promise<void> {
    await resetForm()
    currentRow.value = data.row
    action.value = data.action
    await dialogRef.value?.handleOpen(data, {
      title: actionMeta.value.title,
      subtitle: actionMeta.value.description,
      confirmText: action.value === 'completion' ? '确认回场并完成' : '确认提交',
      contentMaxHeight: '78vh',
      loading: true,
      onOpen: async (_data, api) => {
        try {
          await loadContext()
        } finally {
          api.setLoading(false)
        }
      },
      onConfirm: handleSubmit,
      onReset: () => void resetForm(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .execution-dialog {
    display: flex;
    flex-direction: column;
    gap: var(--art-space-3);
    min-width: 0;

    &__summary {
      display: grid;
      grid-template-columns: 52px minmax(0, 1fr) auto;
      gap: var(--art-space-3);
      align-items: center;
      padding: var(--art-space-4);

      small,
      strong,
      p {
        display: block;
      }

      small {
        font-size: 11px;
        font-weight: 700;
        color: var(--el-color-primary);
        letter-spacing: 0.08em;
      }

      strong {
        margin-top: 3px;
        font-size: 17px;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 4px 0 0;
        color: var(--art-text-gray-600);
      }
    }

    &__icon {
      display: grid;
      place-items: center;
      width: 52px;
      height: 52px;
      font-size: 24px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: 16px;

      &.is-signature {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      &.is-completion {
        color: var(--el-color-warning);
        background: var(--el-color-warning-light-9);
      }
    }

    &__form {
      padding: var(--art-space-4);
    }
  }

  @media (width <= 640px) {
    .execution-dialog__summary {
      grid-template-columns: 48px minmax(0, 1fr);

      :deep(.el-tag) {
        grid-column: 2;
        justify-self: start;
      }
    }
  }
</style>
