<template>
  <ArtDialog ref="dialogRef" size="md">
    <div class="posting-auxiliary-dialog">
      <ElAlert
        type="info"
        :closable="false"
        show-icon
        title="系统按业务实体 ID 匹配当前账套已同步的核算项目；未匹配时该事件会进入待配置。"
      />

      <div
        v-for="(binding, index) in bindings"
        :key="binding.key"
        class="posting-auxiliary-dialog__row"
      >
        <ElSelect
          v-model="binding.auxiliaryTypeId"
          filterable
          clearable
          placeholder="选择核算维度"
          aria-label="核算维度"
        >
          <ElOption
            v-for="item in auxiliaryTypeOptions"
            :key="item.value"
            :label="item.label"
            :value="item.value"
          />
        </ElSelect>
        <ElSelect
          v-model="binding.payloadKey"
          clearable
          placeholder="选择业务实体"
          aria-label="业务实体来源"
        >
          <ElOption
            v-for="item in payloadOptions"
            :key="String(item.value)"
            :label="item.label"
            :value="item.value"
          />
        </ElSelect>
        <ElButton type="danger" link aria-label="删除核算维度绑定" @click="removeBinding(index)">
          删除
        </ElButton>
      </div>

      <ElButton plain class="posting-auxiliary-dialog__add" @click="addBinding">
        <ArtSvgIcon icon="ri:add-line" />新增绑定
      </ElButton>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import { ElMessage } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  defineOptions({ name: 'FinancePostingLineAuxiliaryDialog' })

  interface SelectOption {
    label: string
    value: string
  }

  interface BindingRow {
    key: string
    auxiliaryTypeId: string
    payloadKey: string
  }

  const dialogRef = ref<ArtDialogExpose>()
  const bindings = ref<BindingRow[]>([])
  const auxiliaryTypeOptions = ref<SelectOption[]>([])
  const payloadOptions = ref<SelectOption[]>([])
  let saveHandler: ((value: Record<string, string>) => void) | undefined

  function addBinding(): void {
    bindings.value.push({ key: crypto.randomUUID(), auxiliaryTypeId: '', payloadKey: '' })
  }

  function removeBinding(index: number): void {
    bindings.value.splice(index, 1)
  }

  function handleSubmit(): boolean {
    const completed = bindings.value.filter((item) => item.auxiliaryTypeId || item.payloadKey)
    if (completed.some((item) => !item.auxiliaryTypeId || !item.payloadKey)) {
      ElMessage.warning('请完整选择核算维度和业务实体来源')
      return false
    }
    const typeIds = completed.map((item) => item.auxiliaryTypeId)
    if (new Set(typeIds).size !== typeIds.length) {
      ElMessage.warning('同一核算维度只能绑定一次')
      return false
    }
    saveHandler?.(
      Object.fromEntries(completed.map((item) => [item.auxiliaryTypeId, item.payloadKey]))
    )
    return true
  }

  async function handleOpen(
    value: Record<string, string>,
    auxiliaryTypes: Api.Fms.AuxiliaryTypeRecord[],
    sourceOptions: SelectOption[],
    onSave: (result: Record<string, string>) => void
  ): Promise<void> {
    auxiliaryTypeOptions.value = auxiliaryTypes
      .filter((item) => item.isEnabled)
      .map((item) => ({ label: `${item.typeName}（${item.typeCode}）`, value: item.id }))
    payloadOptions.value = sourceOptions
    bindings.value = Object.entries(value).map(([auxiliaryTypeId, payloadKey]) => ({
      key: crypto.randomUUID(),
      auxiliaryTypeId,
      payloadKey
    }))
    saveHandler = onSave
    await dialogRef.value?.handleOpen(undefined, {
      title: '核算维度自动绑定',
      subtitle: '将会计科目的核算维度映射到业务事件中的实体字段。',
      contentMaxHeight: '56vh',
      dialogProps: { closeOnClickModal: false },
      onConfirm: handleSubmit
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .posting-auxiliary-dialog {
    display: flex;
    flex-direction: column;
    gap: var(--art-space-3);

    &__row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) auto;
      gap: var(--art-space-3);
      align-items: center;
    }

    &__add {
      align-self: flex-start;
    }

    @media (width <= 640px) {
      &__row {
        grid-template-columns: 1fr auto;

        .el-select:nth-child(2) {
          grid-row: 2;
          grid-column: 1 / -1;
        }
      }
    }
  }
</style>
