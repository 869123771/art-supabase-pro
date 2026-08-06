<template>
  <ArtDrawer ref="drawerRef">
    <div class="ai-order-drawer">
      <section class="ai-order-drawer__hero art-card-xs">
        <div class="ai-order-drawer__hero-icon">
          <ArtSvgIcon icon="ri:sparkling-2-line" />
        </div>
        <div class="ai-order-drawer__hero-copy">
          <span>AI ORDER COPILOT</span>
          <h2>把聊天和图片快速变成可开单资料</h2>
          <p>识别、核对、匹配、建档集中在一个工作区，最终仍由你确认并保存订单。</p>
        </div>
        <div class="ai-order-drawer__progress" aria-label="智能填单进度">
          <div class="is-complete"><strong>1</strong><span>提供资料</span></div>
          <div :class="{ 'is-complete': state.analysis }"
            ><strong>2</strong><span>识别核对</span></div
          >
          <div :class="{ 'is-complete': state.analysis && !masterDataTasks.length }">
            <strong>3</strong><span>建档填单</span>
          </div>
        </div>
      </section>

      <div v-if="!state.analysis" class="ai-order-drawer__start-grid">
        <AiOrderSourcePanel
          v-model="form.data"
          :analyzing="state.analyzing"
          :generating-example="state.generatingExample"
          @analyze="handleAnalyze"
          @generate-example="handleGenerateExample"
        />

        <section class="ai-order-drawer__guide art-card-xs">
          <ArtSectionTitle>三步完成智能填单</ArtSectionTitle>
          <div class="ai-order-drawer__guide-list">
            <div>
              <strong>01</strong>
              <span><b>提供原始资料</b><small>粘贴聊天、委托内容，或上传订单图片</small></span>
            </div>
            <div>
              <strong>02</strong>
              <span><b>核对识别结果</b><small>重点检查低可信字段和缺失信息</small></span>
            </div>
            <div>
              <strong>03</strong>
              <span><b>一键建档并回填</b><small>补齐前置档案，再生成订单草稿</small></span>
            </div>
          </div>
          <ElAlert
            title="AI 不会自动保存订单"
            description="识别和建档完成后，仍需在开单页确认全部字段并手动保存。"
            type="info"
            :closable="false"
            show-icon
          />
        </section>
      </div>

      <template v-else>
        <AiOrderSourcePanel
          v-if="state.sourceExpanded"
          v-model="form.data"
          :analyzing="state.analyzing"
          :generating-example="state.generatingExample"
          @analyze="handleAnalyze"
          @generate-example="handleGenerateExample"
        />

        <section v-else class="ai-order-drawer__source-summary art-card-xs">
          <div class="ai-order-drawer__source-summary-icon">
            <ArtSvgIcon icon="ri:file-list-3-line" />
          </div>
          <div>
            <span>已识别原始资料</span>
            <strong>{{ inputSummary }}</strong>
          </div>
          <div class="ai-order-drawer__source-summary-actions">
            <ElButton @click="state.sourceExpanded = true">
              <ArtSvgIcon icon="ri:edit-line" />
              编辑资料
            </ElButton>
            <ElButton type="primary" plain :loading="state.analyzing" @click="handleAnalyze">
              <ArtSvgIcon icon="ri:refresh-line" />
              重新识别
            </ElButton>
          </div>
        </section>

        <div class="ai-order-drawer__analysis-grid">
          <AiOrderResultPanel :analysis="state.analysis" />
          <div class="ai-order-drawer__master-column">
            <AiOrderReferencePanel :analysis="state.analysis" :references="state.references" />
            <AiOrderMasterDataPanel
              v-if="masterDataTasks.length"
              v-model:selected-keys="state.selectedMasterDataKeys"
              :tasks="masterDataTasks"
              :creating="state.creatingMasterData"
            />
            <ElAlert
              v-else
              title="前置资料已就绪，可直接填入当前订单"
              description="客户、地址、站点和货物均已匹配到有效档案。"
              type="success"
              :closable="false"
              show-icon
            />
          </div>
        </div>
      </template>
    </div>

    <template #footer="{ api, loading }">
      <ElButton @click="api.handleClose()">取消</ElButton>
      <ElButton
        v-if="masterDataTasks.length && canCreateMasterData"
        type="primary"
        plain
        :loading="state.creatingMasterData"
        :disabled="!state.selectedMasterDataKeys.length || loading"
        @click="handleCreateMasterData(state.selectedMasterDataKeys)"
      >
        一键建档 {{ state.selectedMasterDataKeys.length }} 项
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
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { UnwrapNestedRefs } from 'vue'
  import { trim } from 'lodash-es'
  import { ElMessage } from 'element-plus'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { analyzeOrderByAi, generateAiOrderExample } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
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

  const { confirmAction } = useArtFeedback()

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
    sourceExpanded: boolean
  }

  const emit = defineEmits<{
    apply: [payload: AiOrderApplyPayload]
  }>()

  const drawerRef = ref<ArtDrawerExpose<AiOrderDrawerOpenData>>()
  const { getUserInfo, isPlatformSuper } = storeToRefs(useUserStore())
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
    selectedMasterDataKeys: [],
    sourceExpanded: true
  })

  const masterDataTasks = computed(() => {
    if (!state.analysis) return []
    return buildTasks(state.analysis.order, state.references)
  })
  const canCreateMasterData = computed(
    () =>
      isPlatformSuper.value ||
      (getUserInfo.value.userRoles ?? []).some((role) =>
        ['R_ADMIN', 'YQ_ADMIN', 'R_REGISTER'].includes(role)
      )
  )
  const inputSummary = computed(() => {
    const characterCount = trim(form.data.prompt).length
    const imageCount = form.data.imageUrls.filter(Boolean).length
    const parts = [
      characterCount ? `${characterCount} 个字` : '',
      imageCount ? `${imageCount} 张图片` : ''
    ]
    return parts.filter(Boolean).join(' · ') || '已提供资料'
  })

  async function handleOpen(data: AiOrderDrawerOpenData): Promise<void> {
    resetState(data)
    await drawerRef.value?.handleOpen(data, {
      title: 'AI 智能填单',
      size: '96vw',
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
      state.sourceExpanded = false
      ElMessage.success('识别完成，请确认结果后填入订单')
    } finally {
      state.analyzing = false
    }
  }

  async function handleGenerateExample(): Promise<void> {
    if (state.analyzing || state.creatingMasterData) return

    if (trim(form.data.prompt)) {
      try {
        await confirmAction('生成新示例会替换当前输入的文字，是否继续？', '替换当前内容', {
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
      state.sourceExpanded = true
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
    if (!canCreateMasterData.value) {
      ElMessage.warning('当前角色无权维护开单基础资料')
      return
    }
    if (!state.analysis || !keys.length || state.creatingMasterData) return

    const selectedTasks = masterDataTasks.value.filter((task) => keys.includes(task.key))
    if (!selectedTasks.length) return

    try {
      await confirmAction(
        `将创建：${selectedTasks.map((task) => task.title).join('、')}。创建后仍需确认并保存订单，是否继续？`,
        '确认一键建档',
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
      ElMessage.error(getErrorMessage(error, '建档失败，本次未创建任何资料，请检查后重试'))
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
      selectedMasterDataKeys: [],
      sourceExpanded: true
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .ai-order-drawer {
    display: grid;
    gap: 16px;
    min-width: 0;

    &__hero {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) auto;
      gap: 16px;
      align-items: center;
      padding: 18px 20px;
      background:
        radial-gradient(
          circle at 92% 12%,
          color-mix(in srgb, var(--theme-color) 13%, transparent),
          transparent 32%
        ),
        var(--default-box-color);
    }

    &__hero-icon {
      display: grid;
      place-items: center;
      width: 48px;
      height: 48px;
      font-size: 24px;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 10%, var(--default-box-color));
      border: 1px solid color-mix(in srgb, var(--theme-color) 22%, transparent);
      border-radius: var(--el-border-radius-base);
    }

    &__hero-copy {
      min-width: 0;

      > span {
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.12em;
        color: var(--theme-color);
      }

      h2 {
        margin: 3px 0 5px;
        font-size: 20px;
        line-height: 1.35;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 0;
        color: var(--el-text-color-secondary);
      }
    }

    &__progress {
      display: flex;
      gap: 8px;

      div {
        display: flex;
        gap: 7px;
        align-items: center;
        padding: 8px 10px;
        color: var(--el-text-color-secondary);
        background: var(--art-main-bg-color);
        border-radius: var(--el-border-radius-base);

        strong {
          display: grid;
          place-items: center;
          width: 22px;
          height: 22px;
          font-size: 12px;
          background: var(--default-box-color);
          border: 1px solid var(--el-border-color);
          border-radius: 50%;
        }

        span {
          font-size: 12px;
          white-space: nowrap;
        }

        &.is-complete {
          color: var(--theme-color);
          background: color-mix(in srgb, var(--theme-color) 8%, var(--default-box-color));

          strong {
            color: #fff;
            background: var(--theme-color);
            border-color: var(--theme-color);
          }
        }
      }
    }

    &__start-grid {
      display: grid;
      grid-template-columns: minmax(0, 1.55fr) minmax(300px, 0.8fr);
      gap: 16px;
      align-items: start;
      min-width: 0;
    }

    &__analysis-grid {
      display: grid;
      grid-template-columns: minmax(460px, 1.08fr) minmax(360px, 0.92fr);
      gap: 16px;
      align-items: start;
      min-width: 0;
    }

    &__master-column {
      display: grid;
      gap: 16px;
      min-width: 0;
    }

    &__source-summary {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) auto;
      gap: 12px;
      align-items: center;
      padding: 12px 16px;

      &-icon {
        display: grid;
        place-items: center;
        width: 38px;
        height: 38px;
        font-size: 18px;
        color: var(--theme-color);
        background: color-mix(in srgb, var(--theme-color) 9%, var(--default-box-color));
        border-radius: var(--el-border-radius-base);
      }

      > div:nth-child(2) {
        min-width: 0;

        span,
        strong {
          display: block;
        }

        span {
          margin-bottom: 2px;
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }

        strong {
          overflow: hidden;
          font-weight: 600;
          color: var(--el-text-color-primary);
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }

      &-actions {
        display: flex;
        gap: 8px;
      }
    }

    &__guide {
      padding: 18px;
    }

    &__guide-list {
      display: grid;
      gap: 10px;
      margin: 16px 0;

      > div {
        display: flex;
        gap: 12px;
        align-items: center;
        padding: 12px;
        background: var(--art-main-bg-color);
        border-radius: var(--el-border-radius-base);

        > strong {
          font-size: 16px;
          color: color-mix(in srgb, var(--theme-color) 78%, transparent);
        }

        span,
        b,
        small {
          display: block;
          min-width: 0;
        }

        b {
          margin-bottom: 3px;
          font-weight: 600;
          color: var(--el-text-color-primary);
        }

        small {
          line-height: 1.45;
          color: var(--el-text-color-secondary);
        }
      }
    }

    @media (width <= 900px) {
      &__hero {
        grid-template-columns: auto minmax(0, 1fr);
      }

      &__progress {
        grid-column: 1 / -1;
      }

      &__start-grid,
      &__analysis-grid {
        grid-template-columns: 1fr;
      }
    }

    @media (width <= 640px) {
      &__hero {
        grid-template-columns: 1fr;
        padding: 16px;
      }

      &__hero-icon {
        display: none;
      }

      &__progress {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));

        div {
          justify-content: center;
          padding: 7px 4px;

          span {
            display: none;
          }
        }
      }

      &__source-summary {
        grid-template-columns: auto minmax(0, 1fr);

        &-actions {
          grid-column: 1 / -1;

          .el-button {
            flex: 1;
          }
        }
      }
    }
  }
</style>
