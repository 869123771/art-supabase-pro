<template>
  <section class="dashboard-hero art-card-xs">
    <div class="dashboard-hero__identity">
      <span class="dashboard-hero__eyebrow">
        <i aria-hidden="true" />
        运输运营中心
      </span>

      <div class="dashboard-hero__heading">
        <h1>{{ greeting }}，{{ userName }}</h1>
        <span>{{ dateText }}</span>
      </div>

      <p>
        今日开单 <strong>{{ todayOrderCount }}</strong> 单，待调度
        <strong>{{ pendingDispatchCount }}</strong> 单，运输中
        <strong>{{ inTransitCount }}</strong> 单。优先处理调度任务与车辆风险。
      </p>

      <div class="dashboard-hero__context">
        <span v-if="userContext">
          <ArtSvgIcon icon="ri:building-4-line" />
          {{ userContext }}
        </span>
        <span><i aria-hidden="true" />运营数据已同步</span>
      </div>
    </div>

    <div class="dashboard-hero__actions" aria-label="工作台快捷操作">
      <ElButton :icon="RefreshRight" @click="emit('refresh')">刷新数据</ElButton>
      <ElButton :icon="Van" @click="emit('dispatch')">处理调度</ElButton>
      <ElButton type="primary" :icon="EditPen" @click="emit('create-order')">立即开单</ElButton>
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
    todayOrderCount: number
    pendingDispatchCount: number
    inTransitCount: number
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
    gap: var(--art-space-6);
    align-items: center;
    justify-content: space-between;
    min-height: 132px;
    padding: 22px 24px;
    overflow: hidden;
    background: var(--default-box-color);

    &::before {
      position: absolute;
      top: 0;
      bottom: 0;
      left: 0;
      width: 4px;
      content: '';
      background: var(--theme-color);
    }

    &__identity {
      min-width: 0;
    }

    &__eyebrow {
      display: inline-flex;
      gap: 7px;
      align-items: center;
      font-size: 11px;
      font-weight: 700;
      color: var(--theme-color);
      letter-spacing: 0.08em;

      i {
        width: 7px;
        height: 7px;
        background: var(--el-color-success);
        border-radius: 50%;
        box-shadow: 0 0 0 4px color-mix(in srgb, var(--el-color-success) 12%, transparent);
      }
    }

    &__heading {
      display: flex;
      gap: 14px;
      align-items: baseline;
      margin-top: 7px;

      h1 {
        min-width: 0;
        margin: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: clamp(22px, 1.6vw, 28px);
        line-height: 1.3;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }

      > span {
        flex: none;
        font-size: 12px;
        color: var(--el-text-color-placeholder);
      }
    }

    p {
      margin: 5px 0 0;
      font-size: 13px;
      line-height: 1.6;
      color: var(--el-text-color-secondary);

      strong {
        color: var(--el-text-color-primary);
      }
    }

    &__context {
      display: flex;
      flex-wrap: wrap;
      gap: 14px;
      align-items: center;
      margin-top: 10px;

      span {
        display: inline-flex;
        gap: 5px;
        align-items: center;
        font-size: 11px;
        color: var(--el-text-color-placeholder);
      }

      span > i {
        width: 6px;
        height: 6px;
        background: var(--el-color-success);
        border-radius: 50%;
      }
    }

    &__actions {
      display: flex;
      flex: none;
      gap: 8px;

      :deep(.el-button) {
        height: 36px;
        margin-left: 0;
      }
    }

    @media screen and (width <= 900px) {
      align-items: flex-start;

      &__actions {
        flex-direction: column-reverse;
        align-items: stretch;
      }
    }

    @media screen and (width <= 680px) {
      flex-direction: column;
      gap: var(--art-space-4);
      padding: 20px;

      &__heading {
        display: block;

        > span {
          display: block;
          margin-top: 3px;
        }
      }

      &__actions {
        flex-direction: row;
        flex-wrap: wrap;
        width: 100%;

        :deep(.el-button) {
          flex: 1;
          min-width: 104px;
        }
      }
    }
  }
</style>
