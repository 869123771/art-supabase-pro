<template>
  <ArtDialog ref="dialogRef">
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
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
  import { auditVehicleArchive } from '@/api/vehicle-mgt-sys'

  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
  type AuditStatus = Api.VehicleMgtSys.ArchiveManage.AuditStatus

  interface AuditForm {
    id: string
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

  const createInitialForm = (): AuditForm => ({
    id: '',
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
          options: [
            { label: '通过', value: 'approved' },
            { label: '未通过', value: 'rejected' }
          ]
        }
      },
      {
        label: '备注',
        key: 'auditRemark',
        type: 'input',
        props: {
          type: 'textarea',
          rows: 5,
          maxlength: 500,
          showWordLimit: true
        }
      }
    ]),
    rules: computed<FormRules<AuditForm>>(() => ({
      auditStatus: [{ required: true, message: '请选择审核状态', trigger: 'change' }]
    }))
  })

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      await auditVehicleArchive(form.value.data)
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row: VehicleArchive): Promise<void> => {
    if (!row.id) return

    form.value.data = {
      id: row.id,
      auditStatus: row.auditStatus === 'rejected' ? 'rejected' : 'approved',
      auditRemark: row.auditRemark ?? ''
    }

    await dialogRef.value?.handleOpen(row, {
      title: `审核车辆档案${row.plateNo ? `：${row.plateNo}` : ''}`,
      width: '620px',
      onConfirm: handleSubmit,
      onReset: () => {
        form.value.data = createInitialForm()
      }
    })
  }

  defineExpose({ handleOpen })
</script>
