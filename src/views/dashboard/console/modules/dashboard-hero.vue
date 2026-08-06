<template>
  <section class="dashboard-hero art-card-xs">
    <div class="dashboard-hero__mesh" aria-hidden="true" />
    <div class="dashboard-hero__copy">
      <div class="dashboard-hero__meta">
        <span class="dashboard-hero__pulse" /> 运输运营中心 <i />
        <span>{{ dateText }}</span>
      </div>
      <h1
        >{{ greeting }}，<strong>{{ userName }}</strong></h1
      >
      <p
        >今天有
        <strong>{{ todayOrderCount }}</strong>
        张订单进入运输链路，关键任务已汇总，准备开始高效调度。</p
      >
      <div class="dashboard-hero__actions">
        <ElButton type="primary" :icon="EditPen" @click="emit('create-order')">立即开单</ElButton>
        <ElButton :icon="Van" @click="emit('dispatch')">处理配载</ElButton>
      </div>
    </div>

    <div class="dashboard-hero__live">
      <header>
        <span><i /> LIVE COMMAND</span>
        <button type="button" aria-label="刷新工作台数据" @click="emit('refresh')">
          <ElIcon><RefreshRight /></ElIcon>
        </button>
      </header>
      <div class="dashboard-hero__live-metric">
        <div
          ><strong>{{ inTransitCount }}</strong
          ><em>单</em></div
        >
        <span>实时运输中</span>
      </div>
      <div class="dashboard-hero__route" aria-hidden="true">
        <i class="is-start" /><span /><b><Van /></b><span /><i class="is-end" />
      </div>
      <footer>
        <span>运力网络在线</span>
        <strong>状态正常</strong>
      </footer>
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
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(260px, 0.36fr);
    gap: clamp(32px, 5vw, 84px);
    align-items: stretch;
    justify-content: space-between;
    min-height: 224px;
    padding: 30px 34px;
    overflow: hidden;
    color: var(--el-color-white);
    background:
      radial-gradient(circle at 70% -20%, rgb(55 229 255 / 34%), transparent 31%),
      linear-gradient(116deg, #25206f 0%, #4f46e5 48%, var(--el-color-primary) 78%, #087bff 120%);
    border: 0;
    box-shadow: 0 18px 42px color-mix(in srgb, var(--el-color-primary) 24%, transparent);

    &::after {
      position: absolute;
      top: -198px;
      right: -96px;
      width: 420px;
      height: 420px;
      content: '';
      border: 1px solid color-mix(in srgb, var(--el-color-white) 14%, transparent);
      border-radius: 50%;
      box-shadow:
        0 0 0 54px color-mix(in srgb, var(--el-color-white) 4%, transparent),
        0 0 0 108px color-mix(in srgb, var(--el-color-white) 2.5%, transparent);
    }

    &__mesh {
      position: absolute;
      inset: 0;
      pointer-events: none;
      background-image:
        linear-gradient(rgb(255 255 255 / 16%) 1px, transparent 1px),
        linear-gradient(90deg, rgb(255 255 255 / 16%) 1px, transparent 1px);
      background-size: 46px 46px;
      opacity: 0.16;
      mask-image: linear-gradient(90deg, #000, transparent 73%);
    }

    &__copy,
    &__live {
      position: relative;
      z-index: 1;
    }

    &__copy {
      align-self: center;
      min-width: 0;
    }

    &__meta {
      display: flex;
      gap: 8px;
      align-items: center;
      font-size: 12px;
      font-weight: 700;
      color: color-mix(in srgb, var(--el-color-white) 72%, transparent);
      text-transform: uppercase;
      letter-spacing: 1px;

      i {
        width: 1px;
        height: 12px;
        background: color-mix(in srgb, var(--el-color-white) 34%, transparent);
      }
    }

    &__pulse {
      width: 8px;
      height: 8px;
      background: #4df3c4;
      border-radius: 50%;
      box-shadow: 0 0 0 6px rgb(77 243 196 / 14%);
    }

    h1 {
      margin: 19px 0 9px;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: clamp(28px, 2.1vw, 40px);
      font-weight: 500;
      line-height: 1.15;
      letter-spacing: -0.7px;
      white-space: nowrap;

      strong {
        font-weight: 800;
      }
    }

    p {
      margin: 0;
      font-size: 14px;
      line-height: 1.7;
      color: color-mix(in srgb, var(--el-color-white) 68%, transparent);
    }

    p strong {
      color: #87f5ff;
    }

    &__actions {
      display: flex;
      gap: 10px;
      margin-top: 23px;
    }

    &__actions :deep(.el-button) {
      height: 38px;
      padding: 0 17px;
      font-weight: 600;
      border-color: rgb(255 255 255 / 20%);
    }

    &__actions :deep(.el-button--primary) {
      color: #3730a3;
      background: var(--el-color-white);
      border-color: var(--el-color-white);
      box-shadow: 0 10px 24px rgb(16 23 73 / 24%);
    }

    &__actions :deep(.el-button:not(.el-button--primary)) {
      color: #fff;
      background: rgb(255 255 255 / 10%);
    }

    &__live {
      align-self: stretch;
      min-width: 0;
      padding: 18px 20px;
      background: linear-gradient(145deg, rgb(255 255 255 / 17%), rgb(255 255 255 / 8%));
      border: 1px solid rgb(255 255 255 / 18%);
      border-radius: var(--art-feature-radius);
      box-shadow: inset 0 1px 0 rgb(255 255 255 / 12%);
      backdrop-filter: blur(18px);

      header,
      footer {
        display: flex;
        align-items: center;
        justify-content: space-between;
      }

      header > span {
        display: inline-flex;
        gap: 6px;
        align-items: center;
        font-size: 9px;
        font-weight: 800;
        color: #72f0d2;
        letter-spacing: 1px;

        i {
          width: 6px;
          height: 6px;
          background: currentcolor;
          border-radius: 50%;
          box-shadow: 0 0 10px currentcolor;
        }
      }

      header button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 28px;
        height: 28px;
        padding: 0;
        color: rgb(255 255 255 / 70%);
        cursor: pointer;
        background: rgb(255 255 255 / 10%);
        border: 0;
        border-radius: 50%;
      }

      footer {
        padding-top: 13px;
        margin-top: 14px;
        font-size: 10px;
        color: rgb(255 255 255 / 50%);
        border-top: 1px solid rgb(255 255 255 / 10%);

        strong {
          font-size: 10px;
          color: #6ef1ce;
        }
      }
    }

    &__live-metric {
      display: flex;
      align-items: end;
      justify-content: space-between;
      margin-top: 15px;

      > div {
        display: flex;
        gap: 5px;
        align-items: end;
      }

      strong {
        font-size: 40px;
        line-height: 1;
        letter-spacing: -1.5px;
      }

      em,
      span {
        padding-bottom: 4px;
        font-size: 10px;
        font-style: normal;
        color: rgb(255 255 255 / 55%);
      }
    }

    &__route {
      display: grid;
      grid-template-columns: 7px 1fr 22px 1fr 7px;
      align-items: center;
      margin-top: 19px;

      > i {
        width: 7px;
        height: 7px;
        border: 2px solid #fff;
        border-radius: 50%;

        &.is-end {
          border-color: #ffbf5a;
          box-shadow: 0 0 0 5px rgb(255 191 90 / 13%);
        }
      }

      > span {
        height: 1px;
        background: linear-gradient(90deg, rgb(255 255 255 / 65%), #70e8ff);
      }

      > b {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 22px;
        height: 22px;
        color: #302b8d;
        background: #70e8ff;
        border-radius: 50%;
        box-shadow: 0 3px 10px rgb(26 22 100 / 20%);

        > svg {
          width: 9px;
          height: 9px;
        }
      }
    }
  }

  @media screen and (width <= 860px) {
    .dashboard-hero {
      grid-template-columns: 1fr;
      min-height: 0;
      padding: 26px;

      &__live {
        display: none;
      }
    }
  }

  @media screen and (width <= 560px) {
    .dashboard-hero {
      padding: 23px 20px;

      h1 {
        font-size: 27px;
      }

      &__meta > span:last-child {
        display: none;
      }

      &__actions {
        flex-wrap: wrap;
      }
    }
  }
</style>
