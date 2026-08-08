<template>
  <ArtDialog ref="dialogRef">
    <template #subtitle>
      {{
        isBatch
          ? '批量确认车辆档案的审核结论，所有选择将应用相同意见。'
          : '确认档案是否可进入车辆业务体系，并留下审核依据。'
      }}
    </template>

    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="24"
      :show-reset="false"
      :show-submit="false"
      label-width="100px"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { auditVehicleArchive, auditVehicleArchiveBatch } from '@/api/vehicle-manage-system'
  import { useUserStore } from '@/store/modules/user'

  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
  type AuditStatus = Api.VehicleMgtSys.ArchiveManage.AuditStatus

  interface AuditForm {
    ids: string[]
    auditStatus: Extract<AuditStatus, 'approved' | 'rejected'>
    auditRemark: string
  }

  interface FormGroup {
    data: AuditForm
    items: FormItem[]
    rules: FormRules<AuditForm>
  }

  interface FormExpose {
    validate: () => Promise<boolean>
  }

  const emit = defineEmits<{
    success: []
  }>()

  const dialogRef = ref<ArtDialogExpose<VehicleArchive>>()
  const formRef = ref<FormExpose>()
  const isBatch = ref(false)
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const auditStatusOptions = computed(() =>
    (getDictMap.value.vehicleAuditStatus ?? []).filter((item) =>
      ['approved', 'rejected'].includes(item.value)
    )
  )

  const createInitialForm = (): AuditForm => ({
    ids: [],
    auditStatus: 'approved',
    auditRemark: ''
  })

  const form: Ref<FormGroup> = ref({
    data: createInitialForm(),
    items: computed<FormItem[]>(() => [
      {
        label: '审核状态',
        key: 'auditStatus',
        type: 'radioGroup',
        props: {
          options: auditStatusOptions.value
        },
        description: '驳回后档案需要修改并重新提交审核。'
      },
      {
        label: '审核意见',
        key: 'auditRemark',
        type: 'input',
        props: {
          type: 'textarea',
          rows: 5,
          maxlength: 500,
          showWordLimit: true,
          placeholder: '通过时可填写补充说明；驳回时请说明需要修改的内容'
        }
      }
    ]),
    rules: computed<FormRules<AuditForm>>(() => ({
      auditStatus: [{ required: true, message: '请选择审核状态', trigger: 'change' }],
      auditRemark:
        form.value.data.auditStatus === 'rejected'
          ? [{ required: true, message: '驳回档案时请填写审核意见', trigger: 'blur' }]
          : []
    }))
  })

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      const { ids, auditStatus, auditRemark } = form.value.data
      if (isBatch.value) {
        await auditVehicleArchiveBatch({ ids, auditStatus, auditRemark })
      } else {
        await auditVehicleArchive({ id: ids[0], auditStatus, auditRemark })
      }
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row: VehicleArchive): Promise<void> => {
    if (!row.id) return

    await userStore.ensureDictLoaded('vehicleAuditStatus')
    isBatch.value = false
    form.value.data = {
      ids: [row.id],
      auditStatus: row.auditStatus === 'rejected' ? 'rejected' : 'approved',
      auditRemark: row.auditRemark ?? ''
    }

    await dialogRef.value?.handleOpen(row, {
      title: `审核车辆档案${row.plateNo ? `：${row.plateNo}` : ''}`,
      size: 'md',
      onConfirm: handleSubmit,
      onReset: () => {
        form.value.data = createInitialForm()
        isBatch.value = false
      }
    })
  }

  const handleBatchOpen = async (rows: VehicleArchive[]): Promise<void> => {
    const ids = rows
      .map((row) => row.id)
      .filter((id): id is string => typeof id === 'string' && id.length > 0)
    if (!ids.length) return

    await userStore.ensureDictLoaded('vehicleAuditStatus')
    isBatch.value = true
    form.value.data = {
      ids,
      auditStatus: 'approved',
      auditRemark: ''
    }

    await dialogRef.value?.handleOpen(rows[0], {
      title: `批量审核车辆档案（${ids.length}条）`,
      size: 'md',
      onConfirm: handleSubmit,
      onReset: () => {
        form.value.data = createInitialForm()
        isBatch.value = false
      }
    })
  }

  defineExpose({ handleOpen, handleBatchOpen })
</script>
