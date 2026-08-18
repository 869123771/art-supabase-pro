<template>
  <section class="dashboard-hero art-card-xs" aria-labelledby="dashboard-heading">
    <div class="dashboard-hero__identity">
      <span class="dashboard-hero__brand" aria-hidden="true">
        <ArtSvgIcon icon="ri:dashboard-3-line" />
      </span>
      <div class="dashboard-hero__copy">
        <div class="dashboard-hero__eyebrow">
          <span><i />运营数据已同步</span>
          <b>TRANSPORT CONTROL</b>
        </div>
        <h1 id="dashboard-heading">{{ greeting }}，{{ userName }}</h1>
        <p>聚焦今日运力、调度进度与车辆风险，快速处理需要关注的运营事项。</p>
      </div>
    </div>

    <div class="dashboard-hero__aside">
      <div class="dashboard-hero__context" aria-label="当前工作台信息">
        <span>
          <ArtSvgIcon icon="ri:calendar-line" aria-hidden="true" />
          {{ dateText }}
        </span>
        <span v-if="userContext">
          <ArtSvgIcon icon="ri:building-4-line" aria-hidden="true" />
          {{ userContext }}
        </span>
      </div>
      <div class="dashboard-hero__actions">
        <ElButton :icon="RefreshRight" @click="emit('refresh')">刷新数据</ElButton>
        <ElButton :icon="Van" @click="emit('dispatch')">处理调度</ElButton>
        <ElButton type="primary" :icon="EditPen" @click="emit('create-order')"> 立即开单 </ElButton>
      </div>
    </div>
  </section>
</template>

<script setup lang="ts">
  import { EditPen, RefreshRight, Van } from '@element-plus/icons-vue'

  defineProps<{
    greeting: string
    userName: string
    userContext: string
    dateText: string
  }>()

  const emit = defineEmits<{
    'create-order': []
    dispatch: []
    refresh: []
  }>()
</script>

<style scoped lang="scss">
  .dashboard-hero {
    position: relative;
    display: flex;
    gap: 28px;
    align-items: center;
    justify-content: space-between;
    min-width: 0;
    min-height: 132px;
    padding: 22px 24px;
    overflow: hidden;
    background:
      radial-gradient(
        circle at 78% -30%,
        color-mix(in srgb, var(--theme-color) 13%, transparent),
        transparent 42%
      ),
      linear-gradient(
        112deg,
        color-mix(in srgb, var(--theme-color) 4%, var(--default-box-color)),
        var(--default-box-color) 56%
      );

    &::after {
      position: absolute;
      right: 5%;
      bottom: -64px;
      width: 190px;
      height: 110px;
      pointer-events: none;
      content: '';
      background: color-mix(in srgb, var(--el-color-success) 7%, transparent);
      border-radius: 50%;
      filter: blur(2px);
    }

    &__identity,
    &__aside,
    &__context,
    &__actions,
    &__eyebrow,
    &__eyebrow span,
    &__brand {
      display: flex;
      align-items: center;
    }

    &__identity,
    &__copy {
      min-width: 0;
    }

    &__brand {
      flex: 0 0 50px;
      justify-content: center;
      width: 50px;
      height: 50px;
      margin-right: 16px;
      font-size: 23px;
      color: var(--el-color-white);
      background: linear-gradient(145deg, var(--theme-color), var(--el-color-primary-dark-2));
      border-radius: var(--custom-radius);
      box-shadow: 0 12px 24px color-mix(in srgb, var(--theme-color) 24%, transparent);
    }

    &__copy {
      display: grid;
      gap: 4px;

      h1 {
        margin: 0;
        font-size: clamp(20px, 1.5vw, 24px);
        line-height: 1.32;
        color: var(--el-text-color-primary);
        text-wrap: balance;
      }

      > p {
        max-width: 620px;
        margin: 0;
        font-size: 13px;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
        overflow-wrap: anywhere;
      }
    }

    &__eyebrow {
      flex-wrap: wrap;
      gap: 9px;
      min-width: 0;
      margin-bottom: 1px;
      font-size: 10px;
      font-weight: 700;
      letter-spacing: 0.08em;

      span {
        gap: 6px;
        color: var(--el-color-success);
        letter-spacing: 0;

        i {
          width: 6px;
          height: 6px;
          background: currentcolor;
          border-radius: 50%;
          box-shadow: 0 0 0 4px color-mix(in srgb, currentcolor 12%, transparent);
        }
      }

      b {
        font-weight: 700;
        color: var(--theme-color);
      }
    }

    &__aside {
      position: relative;
      z-index: 1;
      flex: 0 0 auto;
      flex-direction: column;
      gap: 13px;
      align-items: flex-end;
    }

    &__context {
      flex-wrap: wrap;
      gap: 8px;
      justify-content: flex-end;

      span {
        display: inline-flex;
        gap: 6px;
        align-items: center;
        min-width: 0;
        padding: 5px 9px;
        font-size: 11px;
        color: var(--el-text-color-secondary);
        background: color-mix(in srgb, var(--el-fill-color-light) 82%, transparent);
        border: 1px solid color-mix(in srgb, var(--el-border-color-lighter) 78%, transparent);
        border-radius: 999px;
      }
    }

    &__actions {
      flex-wrap: wrap;
      gap: 8px;
      justify-content: flex-end;

      :deep(.el-button + .el-button) {
        margin-left: 0;
      }
    }

    @media screen and (width <= 980px) {
      flex-direction: column;
      gap: 18px;
      align-items: flex-start;

      &__aside {
        align-items: flex-start;
        width: 100%;
      }

      &__context,
      &__actions {
        justify-content: flex-start;
      }
    }

    @media screen and (width <= 560px) {
      min-height: 0;
      padding: 18px;

      &__identity {
        align-items: flex-start;
      }

      &__brand {
        flex-basis: 42px;
        width: 42px;
        height: 42px;
        margin-right: 12px;
        font-size: 20px;
      }

      &__actions {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        width: 100%;

        :deep(.el-button) {
          width: 100%;
        }

        :deep(.el-button--primary) {
          grid-column: 1 / -1;
        }
      }
    }

    @media (prefers-reduced-motion: reduce) {
      &__brand {
        box-shadow: none;
      }
    }
  }
</style>
