<template>
  <ArtDrawer ref="drawerRef">
    <div class="ai-order-drawer">
      <AiOrderSourcePanel
        v-model="form.data"
        :analyzing="state.analyzing"
        :generating-example="state.generatingExample"
        @analyze="handleAnalyze"
        @generate-example="handleGenerateExample"
      />

      <template v-if="state.analysis">
        <AiOrderResultPanel :analysis="state.analysis" />
        <AiOrderReferencePanel :analysis="state.analysis" :references="state.references" />
        <AiOrderMasterDataPanel
          v-if="masterDataTasks.length"
          v-model:selected-keys="state.selectedMasterDataKeys"
          :tasks="masterDataTasks"
          :creating="state.creatingMasterData"
        />
      </template>
    </div>

    <template #footer="{ api, loading }">
      <ElButton @click="api.handleClose()">取消</ElButton>
      <ElButton
        v-if="masterDataTasks.length"
        type="primary"
        plain
        :loading="state.creatingMasterData"
        :disabled="!state.selectedMasterDataKeys.length || loading"
        @click="handleCreateMasterData(state.selectedMasterDataKeys)"
      >
        创建选中的 {{ state.selectedMasterDataKeys.length }} 项
      </ElButton>
      <ElButton
        type="primary"
        :loading="loading"
        :disabled="!state.analysis || state.creatingMasterData"
        @click="api.handleConfirm()"
      >
        填入当前订单
      </ElButton>
    </template>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import type { UnwrapNestedRefs } from 'vue'
  import { trim } from 'lodash-es'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import { analyzeOrderByAi, generateAiOrderExample } from '@/api/tms'
  import { getBuiltInOrderExample } from './ai-order-examples'
  import AiOrderMasterDataPanel from './ai-order-master-data-panel.vue'
  import AiOrderReferencePanel from './ai-order-reference-panel.vue'
  import AiOrderResultPanel from './ai-order-result-panel.vue'
  import AiOrderSourcePanel from './ai-order-source-panel.vue'
  import type {
    AiOrderApplyPayload,
    AiOrderDrawerOpenData,
    AiOrderInputModel,
    AiOrderReferenceMatches
  } from './ai-order-types'
  import { useAiOrderMasterData } from './use-ai-order-master-data'
  import { useAiOrderReferenceMatcher } from './use-ai-order-reference-matcher'

  defineOptions({ name: 'TmsAiOrderDrawer' })

  interface FormGroup {
    data: AiOrderInputModel
  }

  interface DrawerState {
    analyzing: boolean
    creatingMasterData: boolean
    generatingExample: boolean
    analysis: Api.Tms.Order.AiOrderAnalyzeResponse | null
    openData: AiOrderDrawerOpenData | null
    references: AiOrderReferenceMatches
    selectedMasterDataKeys: string[]
  }

  const emit = defineEmits<{
    apply: [payload: AiOrderApplyPayload]
  }>()

  const drawerRef = ref<ArtDrawerExpose<AiOrderDrawerOpenData>>()
  const { resolveReferences } = useAiOrderReferenceMatcher()
  const { buildTasks, createTasks } = useAiOrderMasterData()

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialInput()
  })

  const state: UnwrapNestedRefs<DrawerState> = reactive<DrawerState>({
    analyzing: false,
    creatingMasterData: false,
    generatingExample: false,
    analysis: null,
    openData: null,
    references: createEmptyReferences(),
    selectedMasterDataKeys: []
  })

  const masterDataTasks = computed(() => {
    if (!state.analysis) return []
    return buildTasks(state.analysis.order, state.references)
  })

  async function handleOpen(data: AiOrderDrawerOpenData): Promise<void> {
    resetState(data)
    await drawerRef.value?.handleOpen(data, {
      title: 'AI 智能填单',
      size: 'min(760px, 92vw)',
      contentHeight: 'calc(100vh - 132px)',
      onConfirm: handleApply,
      onReset: () => resetState(null),
      drawerProps: {
        appendToBody: true,
        closeOnClickModal: false,
        resizable: true
      }
    })
  }

  async function handleAnalyze(): Promise<void> {
    if (state.generatingExample || state.creatingMasterData) return

    const prompt = trim(form.data.prompt)
    const imageUrls = form.data.imageUrls.filter(Boolean)
    if (!prompt && !imageUrls.length) {
      ElMessage.warning('请粘贴订单内容或上传订单图片')
      return
    }

    state.analyzing = true
    state.analysis = null
    state.references = createEmptyReferences()
    state.selectedMasterDataKeys = []
    try {
      const { data, error } = await analyzeOrderByAi({
        prompt,
        imageUrls,
        options: state.openData?.options
      })
      if (error || !data?.order) {
        ElMessage.error(getErrorMessage(error))
        return
      }

      state.analysis = data
      state.references = await resolveReferences(data.order)
      ElMessage.success('识别完成，请确认结果后填入订单')
    } finally {
      state.analyzing = false
    }
  }

  async function handleGenerateExample(): Promise<void> {
    if (state.analyzing || state.creatingMasterData) return

    if (trim(form.data.prompt)) {
      try {
        await ElMessageBox.confirm('生成新示例会替换当前输入的文字，是否继续？', '替换当前内容', {
          type: 'warning',
          confirmButtonText: '继续生成',
          cancelButtonText: '取消'
        })
      } catch {
        return
      }
    }

    state.generatingExample = true
    try {
      const { data, error } = await generateAiOrderExample({
        options: state.openData?.options
      })

      form.data.prompt = data?.prompt || getBuiltInOrderExample()
      state.analysis = null
      state.references = createEmptyReferences()
      if (error || !data?.prompt) {
        ElMessage.warning('AI 示例暂时不可用，已为你填入内置示例')
        return
      }
      ElMessage.success('已生成一份完整示例，可直接修改后识别')
    } finally {
      state.generatingExample = false
    }
  }

  async function handleCreateMasterData(keys: string[]): Promise<void> {
    if (!state.analysis || !keys.length || state.creatingMasterData) return

    const selectedTasks = masterDataTasks.value.filter((task) => keys.includes(task.key))
    if (!selectedTasks.length) return

    try {
      await ElMessageBox.confirm(
        `将创建：${selectedTasks.map((task) => task.title).join('、')}。创建后仍需确认并保存订单，是否继续？`,
        '确认 AI 一键建档',
        {
          type: 'warning',
          confirmButtonText: '确认创建',
          cancelButtonText: '取消'
        }
      )
    } catch {
      return
    }

    state.creatingMasterData = true
    try {
      const createdCount = await createTasks(state.analysis.order, state.references, keys)
      state.references = await resolveReferences(state.analysis.order)
      ElMessage.success(`已创建 ${createdCount} 项基础资料，可继续填入订单`)
    } catch (error) {
      state.references = await resolveReferences(state.analysis.order)
      ElMessage.error(getErrorMessage(error, '建档未全部完成，已保留成功项，可检查后重试'))
    } finally {
      state.creatingMasterData = false
    }
  }

  function handleApply(): boolean {
    if (!state.analysis) {
      ElMessage.warning('请先完成智能识别')
      return false
    }

    emit('apply', {
      analysis: state.analysis,
      references: state.references
    })
    return true
  }

  function getErrorMessage(error: unknown, fallback = 'AI 识别失败，请稍后重试'): string {
    if (error instanceof Error && error.message) return error.message
    if (error && typeof error === 'object' && 'message' in error) {
      const message = (error as { message?: unknown }).message
      if (typeof message === 'string' && message) return message
    }
    return fallback
  }

  function createInitialInput(): AiOrderInputModel {
    return { prompt: '', imageUrls: [] }
  }

  function createEmptyReferences(): AiOrderReferenceMatches {
    return {
      originStation: { status: 'empty' },
      destinationStation: { status: 'empty' },
      transferStation: { status: 'empty' },
      shippingCustomer: { status: 'empty' },
      receivingCustomer: { status: 'empty' },
      shippingAddress: { status: 'empty' },
      receivingAddress: { status: 'empty' },
      cargoItems: []
    }
  }

  function resetState(data: AiOrderDrawerOpenData | null): void {
    Object.assign(form.data, createInitialInput())
    Object.assign(state, {
      analyzing: false,
      creatingMasterData: false,
      generatingExample: false,
      analysis: null,
      openData: data,
      references: createEmptyReferences(),
      selectedMasterDataKeys: []
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .ai-order-drawer {
    display: grid;
    gap: 14px;
  }
</style>
