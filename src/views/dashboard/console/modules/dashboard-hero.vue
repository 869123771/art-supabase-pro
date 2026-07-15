<template>
  <section class="dashboard-hero art-card-xs">
    <div class="dashboard-hero__copy">
      <div class="dashboard-hero__meta">
        <span class="dashboard-hero__pulse" /> 运输运营中心 <i /> {{ dateText }}
      </div>
      <h1>{{ greeting }}，{{ userName }}</h1>
      <p
        >今天有
        <strong>{{ todayOrderCount }}</strong> 张订单进入运输链路，请关注待配载和异常提醒。</p
      >
      <div class="dashboard-hero__actions">
        <ElButton type="primary" :icon="EditPen" @click="emit('create-order')">立即开单</ElButton>
        <ElButton :icon="Van" @click="emit('dispatch')">处理配载</ElButton>
      </div>
    </div>

    <div class="dashboard-hero__live">
      <span>实时运输中</span>
      <strong>{{ inTransitCount }}</strong>
      <em>单运单</em>
      <button type="button" @click="emit('refresh')">
        <ElIcon><RefreshRight /></ElIcon> 刷新数据
      </button>
    </div>
  </section>
</template>

<script setup lang="ts">
  import { EditPen, RefreshRight, Van } from '@element-plus/icons-vue'

  defineProps<{
    greeting: string
    userName: string
    dateText: string
    todayOrderCount: number
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
    gap: 24px;
    align-items: center;
    justify-content: space-between;
    min-height: 150px;
    padding: 24px 30px;
    overflow: hidden;
    color: var(--el-color-white);
    background:
      radial-gradient(
        circle at 94% 0%,
        color-mix(in srgb, var(--el-color-primary-light-3) 60%, transparent),
        transparent 28%
      ),
      linear-gradient(110deg, var(--el-color-primary-dark-2), var(--el-color-primary));

    &::after {
      position: absolute;
      top: -130px;
      right: -74px;
      width: 310px;
      height: 310px;
      content: '';
      border: 1px solid color-mix(in srgb, var(--el-color-white) 14%, transparent);
      border-radius: 50%;
      box-shadow:
        0 0 0 38px color-mix(in srgb, var(--el-color-white) 4%, transparent),
        0 0 0 76px color-mix(in srgb, var(--el-color-white) 3%, transparent);
    }

    &__copy,
    &__live {
      position: relative;
      z-index: 1;
    }

    &__meta {
      display: flex;
      gap: 8px;
      align-items: center;
      font-size: 12px;
      font-weight: 600;
      letter-spacing: 0.7px;
      color: color-mix(in srgb, var(--el-color-white) 78%, transparent);
      text-transform: uppercase;

      i {
        width: 1px;
        height: 12px;
        background: color-mix(in srgb, var(--el-color-white) 34%, transparent);
      }
    }

    &__pulse {
      width: 7px;
      height: 7px;
      background: var(--el-color-success-light-3);
      border-radius: 50%;
      box-shadow: 0 0 0 5px color-mix(in srgb, var(--el-color-success-light-3) 18%, transparent);
    }

    h1 {
      margin: 11px 0 6px;
      font-size: 25px;
      line-height: 1.2;
      letter-spacing: 0.2px;
    }
    p {
      margin: 0;
      font-size: 13px;
      color: color-mix(in srgb, var(--el-color-white) 76%, transparent);
    }
    p strong {
      color: var(--el-color-white);
    }

    &__actions {
      display: flex;
      gap: 10px;
      margin-top: 17px;
    }
    &__actions :deep(.el-button) {
      height: 32px;
      font-weight: 600;
    }
    &__actions :deep(.el-button--primary) {
      color: var(--el-color-primary);
      background: var(--el-color-white);
      border-color: var(--el-color-white);
    }

    &__live {
      display: grid;
      grid-template-columns: auto auto;
      gap: 0 9px;
      align-items: end;
      min-width: 160px;
      padding: 4px 2px 4px 25px;
      border-left: 1px solid color-mix(in srgb, var(--el-color-white) 22%, transparent);
      text-align: right;

      > span {
        grid-column: 1 / -1;
        font-size: 12px;
        color: color-mix(in srgb, var(--el-color-white) 72%, transparent);
      }
      > strong {
        margin-top: 5px;
        font-size: 34px;
        line-height: 1;
      }
      > em {
        padding-bottom: 3px;
        font-size: 12px;
        font-style: normal;
        color: color-mix(in srgb, var(--el-color-white) 72%, transparent);
      }
      button {
        display: inline-flex;
        grid-column: 1 / -1;
        gap: 4px;
        align-items: center;
        justify-content: flex-end;
        padding: 0;
        margin-top: 11px;
        font-size: 12px;
        color: var(--el-color-white);
        cursor: pointer;
        background: transparent;
        border: 0;
      }
    }
  }

  @media screen and (max-width: 640px) {
    .dashboard-hero {
      min-height: 0;
      padding: 22px;
    }
    .dashboard-hero__live {
      display: none;
    }
  }
</style>
