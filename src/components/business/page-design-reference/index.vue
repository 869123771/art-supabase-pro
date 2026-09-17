<template>
  <div v-if="routeIdentity" class="page-design-reference">
    <ElButton
      v-if="state.loadError"
      class="page-design-reference__trigger"
      plain
      :loading="state.loading"
      aria-label="重新加载设计参考状态"
      title="设计参考状态加载失败，点击重试"
      @click="loadReference"
    >
      <ArtSvgIcon icon="ri:refresh-line" />
      <span>重试设计参考</span>
    </ElButton>

    <ElPopover
      v-else
      v-model:visible="state.popoverVisible"
      placement="bottom-end"
      trigger="click"
      :width="336"
    >
      <template #reference>
        <ElButton
          class="page-design-reference__trigger"
          :class="{ 'is-active': Boolean(state.reference) }"
          plain
          :loading="state.loading || state.saving"
          :aria-pressed="Boolean(state.reference)"
          :aria-label="state.reference ? '编辑本页设计参考' : '将本页作为设计参考'"
          @click="ensureReference"
        >
          <ArtSvgIcon
            :icon="state.reference ? 'ri:star-fill' : 'ri:star-line'"
            aria-hidden="true"
          />
          <span>{{ state.reference ? '已作为设计参考' : '作为设计参考' }}</span>
        </ElButton>
      </template>

      <div class="page-design-reference__panel" :aria-busy="state.saving">
        <div class="page-design-reference__heading">
          <div class="page-design-reference__heading-icon" aria-hidden="true">
            <ArtSvgIcon icon="ri:palette-line" />
          </div>
          <div>
            <strong>记录你喜欢这页的原因</strong>
            <p>AI 会优先复用选中的设计特征，不会机械复制整页。</p>
          </div>
        </div>

        <ElCheckboxGroup
          v-model="form.preferenceTags"
          class="page-design-reference__choices"
          :disabled="state.saving"
          aria-label="喜欢的设计特征"
        >
          <ElCheckboxButton
            v-for="option in preferenceOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </ElCheckboxButton>
        </ElCheckboxGroup>

        <ElInput
          v-model="form.note"
          type="textarea"
          :rows="3"
          resize="none"
          maxlength="500"
          show-word-limit
          :disabled="state.saving"
          aria-label="设计偏好补充说明"
          placeholder="可选，例如：喜欢头部概览，但不喜欢渐变背景"
        />

        <p v-if="state.saveError" class="page-design-reference__error" role="alert">
          {{ state.saveError }}
        </p>

        <div class="page-design-reference__footer">
          <ElButton
            v-if="state.reference"
            type="danger"
            text
            :disabled="state.saving"
            @click="removeReference"
          >
            取消参考
          </ElButton>
          <span v-else />
          <div class="page-design-reference__footer-actions">
            <ElButton :disabled="state.saving" @click="state.popoverVisible = false">
              关闭
            </ElButton>
            <ElButton type="primary" :loading="state.saving" @click="saveReference">
              保存偏好
            </ElButton>
          </div>
        </div>
      </div>
    </ElPopover>
  </div>
</template>

<script setup lang="ts">
  import { ElMessage } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import { useRoute } from 'vue-router'
  import {
    fetchUiDesignReference,
    removeUiDesignReference,
    saveUiDesignReference,
    type UiDesignReferenceRecord,
    type UiDesignReferenceStyleSnapshot,
    type UiDesignReferenceSurfaceKind
  } from '@/api/ui-design-reference'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { useUserStore } from '@/store/modules/user'
  import { StorageConfig } from '@/utils'

  defineOptions({ name: 'PageDesignReference' })

  const props = withDefaults(
    defineProps<{
      title: string
      surfaceKind?: UiDesignReferenceSurfaceKind
      styleSnapshot?: UiDesignReferenceStyleSnapshot
    }>(),
    {
      surfaceKind: 'other',
      styleSnapshot: () => ({})
    }
  )

  interface ReferenceState {
    reference: UiDesignReferenceRecord | null
    loading: boolean
    saving: boolean
    loadError: boolean
    saveError: string
    popoverVisible: boolean
  }

  interface ReferenceForm {
    preferenceTags: string[]
    note: string
  }

  const preferenceOptions = [
    { value: 'information-hierarchy', label: '信息层级' },
    { value: 'workspace-header', label: '工作区头部' },
    { value: 'compact-density', label: '紧凑密度' },
    { value: 'table-layout', label: '表格布局' },
    { value: 'status-expression', label: '状态表达' },
    { value: 'spacing-rhythm', label: '空间节奏' }
  ] as const

  const route = useRoute()
  const { isPlatformSuper } = storeToRefs(useUserStore())
  const routeIdentity = computed(() => {
    if (!isPlatformSuper.value) return null
    const name = typeof route.name === 'string' ? route.name.trim() : ''
    if (!name) return null
    const matchedPath = route.matched.at(-1)?.path?.trim()
    return {
      name,
      pathPattern: matchedPath || route.path
    }
  })

  const state = reactive<ReferenceState>({
    reference: null,
    loading: false,
    saving: false,
    loadError: false,
    saveError: '',
    popoverVisible: false
  })
  const form = reactive<ReferenceForm>({
    preferenceTags: [],
    note: ''
  })
  let loadSequence = 0

  function applyReference(reference: UiDesignReferenceRecord | null): void {
    state.reference = reference
    form.preferenceTags = [...(reference?.preferenceTags ?? [])]
    form.note = reference?.note ?? ''
  }

  async function loadReference(): Promise<void> {
    const identity = routeIdentity.value
    if (!identity) return
    const sequence = ++loadSequence
    state.loading = true
    state.loadError = false
    try {
      const reference = await fetchUiDesignReference(identity.name)
      if (sequence === loadSequence) applyReference(reference)
    } catch {
      if (sequence === loadSequence) state.loadError = true
    } finally {
      if (sequence === loadSequence) state.loading = false
    }
  }

  async function persistReference(showCreatedMessage = false): Promise<boolean> {
    if (!routeIdentity.value || state.saving) return false
    state.saving = true
    state.saveError = ''
    try {
      const reference = await saveUiDesignReference({
        id: state.reference?.id,
        routeName: routeIdentity.value.name,
        routePathPattern: routeIdentity.value.pathPattern,
        pageTitle: props.title,
        surfaceKind: props.surfaceKind,
        preferenceTags: form.preferenceTags,
        note: form.note,
        styleSnapshot: {
          schemaVersion: 1,
          ...props.styleSnapshot
        },
        sourceRevision: StorageConfig.CURRENT_VERSION
      })
      applyReference(reference)
      ElMessage.success(showCreatedMessage ? '已将本页设为设计参考' : '设计偏好已保存')
      return true
    } catch {
      state.saveError = '设计参考暂时无法保存，请检查网络后重试。'
      return false
    } finally {
      state.saving = false
    }
  }

  async function ensureReference(): Promise<void> {
    if (!state.reference) await persistReference(true)
  }

  async function saveReference(): Promise<void> {
    if (await persistReference(false)) state.popoverVisible = false
  }

  async function removeReference(): Promise<void> {
    const id = state.reference?.id
    if (!id || state.saving) return
    state.saving = true
    state.saveError = ''
    try {
      await removeUiDesignReference(id)
      applyReference(null)
      state.popoverVisible = false
      ElMessage.success('已取消本页设计参考')
    } catch {
      state.saveError = '暂时无法取消设计参考，请稍后重试。'
    } finally {
      state.saving = false
    }
  }

  watch(
    () => routeIdentity.value?.name,
    (routeName) => {
      if (!routeName) {
        loadSequence += 1
        applyReference(null)
        state.loading = false
        state.loadError = false
        return
      }
      applyReference(null)
      void loadReference()
    },
    { immediate: true }
  )
</script>

<style scoped lang="scss">
  .page-design-reference {
    flex: none;

    &__trigger {
      gap: var(--art-space-1);
      min-height: 32px;
      color: var(--el-text-color-secondary);
      border-color: var(--el-border-color);
      transition:
        color var(--art-motion-duration-fast) ease,
        background-color var(--art-motion-duration-fast) ease,
        border-color var(--art-motion-duration-fast) ease,
        box-shadow var(--art-motion-duration-fast) ease;

      &:hover,
      &:focus-visible,
      &.is-active {
        color: var(--theme-color);
        background: color-mix(in srgb, var(--theme-color) 9%, var(--default-box-color));
        border-color: color-mix(in srgb, var(--theme-color) 34%, var(--el-border-color));
      }

      &:focus-visible {
        outline: none;
        box-shadow: var(--art-themed-action-focus-shadow);
      }

      &.is-active {
        font-weight: 600;
        box-shadow: var(--art-themed-action-active-shadow);
      }
    }

    &__panel {
      display: grid;
      gap: var(--art-space-3);
    }

    &__heading {
      display: flex;
      gap: var(--art-space-2);
      align-items: flex-start;

      strong {
        display: block;
        margin-bottom: var(--art-space-1);
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        font-size: var(--art-font-size-caption);
        line-height: var(--art-line-height-body);
        color: var(--el-text-color-secondary);
      }
    }

    &__heading-icon {
      display: inline-flex;
      flex: 0 0 34px;
      align-items: center;
      justify-content: center;
      width: 34px;
      height: 34px;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 10%, var(--default-box-color));
      border-radius: var(--el-border-radius-base);
    }

    &__choices {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: var(--art-space-2);

      :deep(.el-checkbox-button) {
        min-width: 0;
      }

      :deep(.el-checkbox-button__inner) {
        width: 100%;
        padding-inline: var(--art-space-2);
        overflow: hidden;
        text-overflow: ellipsis;
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);
        box-shadow: none;
      }

      :deep(.el-checkbox-button:first-child .el-checkbox-button__inner),
      :deep(.el-checkbox-button:last-child .el-checkbox-button__inner) {
        border-radius: var(--el-border-radius-base);
      }

      :deep(.el-checkbox-button.is-checked .el-checkbox-button__inner) {
        color: var(--theme-color);
        background: color-mix(in srgb, var(--theme-color) 10%, var(--default-box-color));
        border-color: color-mix(in srgb, var(--theme-color) 35%, var(--el-border-color));
        box-shadow: var(--art-themed-action-active-shadow);
      }
    }

    &__error {
      margin: 0;
      font-size: var(--art-font-size-caption);
      color: var(--el-color-danger);
    }

    &__footer,
    &__footer-actions {
      display: flex;
      gap: var(--art-space-2);
      align-items: center;
    }

    &__footer {
      justify-content: space-between;
      padding-top: var(--art-space-1);
      border-top: 1px solid var(--el-border-color-lighter);
    }

    @media (width <= 640px) {
      &__trigger {
        width: 32px;
        padding-inline: 0;

        span {
          display: none;
        }
      }
    }
  }
</style>
