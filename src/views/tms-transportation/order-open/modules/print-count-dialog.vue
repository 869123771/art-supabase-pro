<template>
  <ArtDialog ref="dialogRef" width="560px">
    <div class="print-count-dialog">
      <div class="print-count-dialog__row">
        <span class="print-count-dialog__label">打印数量</span>
        <ElRadioGroup v-model="form.option">
          <ElRadio value="cargo_quantity">同货品数量</ElRadio>
          <ElRadio value="1">1张</ElRadio>
          <ElRadio value="2">2张</ElRadio>
          <ElRadio value="3">3张</ElRadio>
          <ElRadio value="custom">自定义</ElRadio>
        </ElRadioGroup>
      </div>

      <ElInputNumber
        v-if="form.option === 'custom'"
        v-model="form.customCount"
        :min="1"
        :precision="0"
        controls-position="right"
        class="print-count-dialog__custom"
        placeholder="请输入打印数量"
      />
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import { ElMessage } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'

  defineOptions({ name: 'TmsOrderPrintCountDialog' })

  type PrintKind = 'waybill' | 'label'
  type PrintCountOption = 'cargo_quantity' | '1' | '2' | '3' | 'custom'

  interface PrintOpenData {
    kind: PrintKind
    cargoQuantity: number
  }

  interface FormGroup {
    option: PrintCountOption
    customCount: number | null
  }

  const emit = defineEmits<{
    (event: 'confirm', kind: PrintKind, count: number): void
  }>()

  const dialogRef = ref<ArtDialogExpose<PrintOpenData>>()
  const form = reactive<FormGroup>({
    option: 'cargo_quantity',
    customCount: null
  })

  function resolveCount(data?: PrintOpenData): number {
    if (form.option === 'cargo_quantity') return Math.max(1, Math.floor(data?.cargoQuantity || 1))
    if (form.option === 'custom') return Math.max(0, Math.floor(form.customCount || 0))
    return Number(form.option)
  }

  async function handleOpen(data: PrintOpenData): Promise<void> {
    form.option = 'cargo_quantity'
    form.customCount = null

    await dialogRef.value?.handleOpen(data, {
      title: data.kind === 'waybill' ? '打印运单' : '打印标签',
      onConfirm: (openData) => {
        const count = resolveCount(openData)
        if (count < 1) {
          ElMessage.warning('请输入打印数量')
          return false
        }
        emit('confirm', data.kind, count)
        return true
      }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .print-count-dialog {
    padding: 6px 8px 18px;

    &__row {
      display: flex;
      gap: 12px;
      align-items: center;
      min-height: 40px;
    }

    &__label {
      flex: 0 0 72px;
      color: var(--art-text-gray-700);
    }

    &__custom {
      width: 320px;
      margin-top: 18px;
      margin-left: 84px;
    }
  }
</style>
