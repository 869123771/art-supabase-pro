<template>
  <ArtDrawer ref="drawerRef" :show-footer="false" show-fullscreen-button>
    <ArtAsyncState
      :loading="state.loading"
      :error="state.error"
      :empty="!state.data"
      loading-mode="skeleton"
      @retry="load"
    >
      <div v-if="state.data" class="safety-ai-advisor">
        <section class="safety-ai-advisor__hero art-card-xs">
          <span><ArtSvgIcon icon="ri:sparkling-2-line" /></span>
          <div
            ><small>AI SAFETY ADVISOR</small><h3>安全态势研判</h3
            ><p>{{ state.data.assessment.summary }}</p></div
          >
          <div class="safety-ai-advisor__score"
            ><strong>{{ state.data.assessment.riskScore }}</strong
            ><small>风险分</small></div
          >
        </section>
        <ElAlert title="只读研判，不自动修改业务数据" type="info" :closable="false" show-icon />
        <section class="safety-ai-advisor__section">
          <ArtSectionTitle :show-line="false">重点风险信号</ArtSectionTitle>
          <div class="safety-ai-advisor__signals">
            <article
              v-for="signal in state.data.assessment.signals"
              :key="signal.type"
              :class="`is-${signal.severity}`"
              class="art-card-xs"
            >
              <span>{{ signal.count }}</span
              ><div
                ><strong>{{ signal.title }}</strong
                ><p>{{ signal.detail }}</p></div
              >
            </article>
          </div>
        </section>
        <section class="safety-ai-advisor__section art-card-xs"
          ><ArtSectionTitle :show-line="false">建议行动</ArtSectionTitle
          ><ol
            ><li v-for="action in state.data.assessment.actions" :key="action">{{ action }}</li></ol
          ></section
        >
        <section class="safety-ai-advisor__limitations"
          ><strong>研判边界</strong
          ><p v-for="item in state.data.assessment.limitations" :key="item">{{ item }}</p></section
        >
        <footer
          >规则版本 {{ state.data.ruleVersion }} ·
          {{ formatWithDayjs(state.data.generatedAt) }}</footer
        >
      </div>
    </ArtAsyncState>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { analyzeSmisSafetyByAi } from '@/api/smis'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'SmisSafetyAiAdvisorDrawer' })
  const drawerRef = ref<ArtDrawerExpose>()
  const state = reactive<{
    loading: boolean
    error: Error | null
    data: Api.Smis.Dashboard.SafetyAdvisorResponse | null
  }>({ loading: false, error: null, data: null })
  const load = async (): Promise<void> => {
    state.loading = true
    state.error = null
    try {
      const result = await analyzeSmisSafetyByAi()
      if (result.error) throw result.error
      state.data = result.data
    } catch (error) {
      state.error = error instanceof Error ? error : new Error('AI安全研判失败')
    } finally {
      state.loading = false
    }
  }
  const handleOpen = async (): Promise<void> => {
    state.data = null
    await drawerRef.value?.handleOpen(undefined, {
      title: 'AI 安全态势研判',
      size: 'min(780px, 94vw)'
    })
    await load()
  }
  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .safety-ai-advisor {
    display: grid;
    gap: 14px;
    min-width: 0;
  }

  .safety-ai-advisor__hero {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr) auto;
    gap: 14px;
    align-items: center;
    padding: 20px;
    background: linear-gradient(
      135deg,
      color-mix(in srgb, var(--theme-color) 10%, var(--el-bg-color)),
      var(--el-bg-color)
    );
  }

  .safety-ai-advisor__hero > span {
    display: grid;
    place-items: center;
    width: 46px;
    height: 46px;
    font-size: 23px;
    color: #fff;
    background: var(--theme-color);
    border-radius: 13px;
  }

  .safety-ai-advisor__hero small,
  .safety-ai-advisor footer {
    color: var(--art-text-gray-600);
  }

  .safety-ai-advisor__hero h3 {
    margin: 3px 0;
    font-size: 20px;
  }

  .safety-ai-advisor__hero p,
  .safety-ai-advisor__signals p {
    margin: 0;
    line-height: 1.6;
  }

  .safety-ai-advisor__score {
    text-align: center;
  }

  .safety-ai-advisor__score strong {
    display: block;
    font-size: 30px;
    color: var(--el-color-danger);
  }

  .safety-ai-advisor__section {
    padding: 18px;
  }

  .safety-ai-advisor__signals {
    display: grid;
    gap: 10px;
    margin-top: 14px;
  }

  .safety-ai-advisor__signals article {
    display: flex;
    gap: 12px;
    align-items: flex-start;
    padding: 13px;
    border-left: 3px solid var(--el-color-info);
  }

  .safety-ai-advisor__signals article > span {
    display: grid;
    flex: 0 0 auto;
    place-items: center;
    min-width: 34px;
    height: 34px;
    font-weight: 700;
    background: var(--el-fill-color-light);
    border-radius: 9px;
  }

  .safety-ai-advisor__signals .is-warning {
    border-left-color: var(--el-color-warning);
  }

  .safety-ai-advisor__signals .is-danger {
    border-left-color: var(--el-color-danger);
  }

  .safety-ai-advisor ol {
    display: grid;
    gap: 9px;
    padding-left: 22px;
    margin: 14px 0 0;
    line-height: 1.6;
  }

  .safety-ai-advisor__limitations {
    padding: 16px;
    color: var(--art-text-gray-700);
    background: var(--el-fill-color-light);
    border-radius: 10px;
  }

  .safety-ai-advisor__limitations p {
    margin: 7px 0 0;
    font-size: 13px;
    line-height: 1.55;
  }

  .safety-ai-advisor footer {
    font-size: 12px;
    text-align: right;
  }

  @media (width <= 640px) {
    .safety-ai-advisor__hero {
      grid-template-columns: auto 1fr;
    }

    .safety-ai-advisor__score {
      grid-column: 1 / -1;
      text-align: left;
    }
  }
</style>
