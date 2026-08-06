<template>
  <article class="order-flow art-card-xs">
    <header>
      <div><p>运输执行</p><h2>订单流转</h2></div>
      <button type="button" @click="emit('view-orders')"
        >订单列表 <ElIcon><ArrowRight /></ElIcon
      ></button>
    </header>
    <div class="order-flow__headline">
      <strong>{{ total }}</strong
      ><span>近 {{ days }} 天订单</span>
      <b>运输中 {{ inTransitCount }} 单</b>
    </div>
    <div class="order-flow__rail" :class="{ 'is-empty': activeStatusItems.length === 0 }"
      ><i
        v-for="item in activeStatusItems"
        :key="item.key"
        :style="{ flex: item.value || 0.16, background: item.color }"
    /></div>
    <div class="order-flow__list">
      <button
        v-for="item in statusItems"
        :key="item.key"
        type="button"
        @click="emit('view-orders')"
      >
        <span :style="{ background: item.color }" />
        <em>{{ item.label }}</em>
        <strong>{{ item.value }}</strong>
        <small>{{ item.percent }}%</small>
      </button>
    </div>
  </article>
</template>

<script setup lang="ts">
  import { ArrowRight } from '@element-plus/icons-vue'
  import type { DashboardStatusItem } from './types'

  const props = defineProps<{
    days: number
    total: number
    inTransitCount: number
    statusItems: DashboardStatusItem[]
  }>()
  const emit = defineEmits<{ 'view-orders': [] }>()
  const activeStatusItems = computed(() => props.statusItems.filter((item) => item.value > 0))
</script>

<style scoped lang="scss">
  .order-flow {
    position: relative;
    min-width: 0;
    padding: 24px 25px;
    overflow: hidden;
    background:
      radial-gradient(
        circle at 100% 0%,
        color-mix(in srgb, var(--el-color-primary) 12%, transparent),
        transparent 38%
      ),
      var(--default-box-color);

    header {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;

      button {
        display: inline-flex;
        gap: 2px;
        align-items: center;
        padding: 0;
        font-size: 12px;
        color: var(--el-color-primary);
        cursor: pointer;
        background: transparent;
        border: 0;
      }
    }

    p {
      margin: 0 0 5px;
      font-size: 11px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.8px;
    }

    h2 {
      margin: 0;
      font-size: 18px;
      color: var(--el-text-color-primary);
    }

    &__headline {
      display: grid;
      grid-template-columns: auto 1fr;
      gap: 2px 9px;
      align-items: end;
      margin-top: 27px;

      strong {
        font-size: 38px;
        line-height: 0.9;
        color: var(--el-text-color-primary);
        letter-spacing: -1px;
      }

      span {
        padding-bottom: 2px;
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }

      b {
        grid-column: 1 / -1;
        margin-top: 9px;
        font-size: 12px;
        font-weight: 650;
        color: var(--el-color-success);
      }
    }

    &__rail {
      display: flex;
      gap: 3px;
      height: 9px;
      margin: 19px 0 17px;
      overflow: hidden;
      background: var(--el-fill-color-light);
      border-radius: 999px;

      &.is-empty {
        background: repeating-linear-gradient(
          135deg,
          var(--el-fill-color-light) 0 8px,
          var(--el-fill-color) 8px 16px
        );
      }

      i {
        min-width: 7px;
        height: 100%;
        border-radius: inherit;
      }
    }

    &__list {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px 15px;

      button {
        display: grid;
        grid-template-columns: 7px minmax(0, 1fr) auto auto;
        gap: 7px;
        align-items: center;
        padding: 5px 0;
        text-align: left;
        cursor: pointer;
        background: transparent;
        border: 0;
      }

      span {
        width: 7px;
        height: 7px;
        border-radius: 50%;
      }

      em {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        font-style: normal;
        color: var(--el-text-color-regular);
        white-space: nowrap;
      }

      strong {
        font-size: 12px;
        color: var(--el-text-color-primary);
      }

      small {
        font-size: 10px;
        color: var(--el-text-color-placeholder);
      }
    }
  }
</style>
