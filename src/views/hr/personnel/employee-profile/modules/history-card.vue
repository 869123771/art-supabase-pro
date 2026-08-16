<template>
  <article class="hr-history-card">
    <header>
      <div>
        <strong>{{ title }}</strong>
        <span>{{ subtitle || '待完善' }}</span>
      </div>
      <ElButton type="danger" text aria-label="删除本条记录" @click="emit('remove')">
        <ArtSvgIcon icon="ri:delete-bin-6-line" />
        删除
      </ElButton>
    </header>
    <div class="hr-history-card__content"><slot /></div>
  </article>
</template>

<script setup lang="ts">
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  defineOptions({ name: 'HrHistoryCard' })
  defineProps<{ title: string; subtitle?: string | null }>()
  const emit = defineEmits<{ (event: 'remove'): void }>()
</script>

<style scoped lang="scss">
  .hr-history-card {
    min-width: 0;
    overflow: hidden;
    background: var(--el-bg-color);
    border: 1px solid var(--el-border-color-lighter);
    border-radius: var(--custom-radius);
    box-shadow: 0 8px 24px rgb(15 23 42 / 4%);

    > header {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      padding: 13px 16px;
      background: color-mix(in srgb, var(--el-color-primary-light-9) 52%, var(--el-bg-color));
      border-bottom: 1px solid var(--el-border-color-lighter);

      > div {
        display: flex;
        gap: 10px;
        align-items: center;
        min-width: 0;
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 14px;
        white-space: nowrap;
      }

      span {
        flex: none;
        padding: 3px 8px;
        font-size: 11px;
        color: var(--el-color-primary);
        background: var(--el-bg-color);
        border: 1px solid var(--el-color-primary-light-7);
        border-radius: 999px;
      }
    }

    &__content {
      padding: 18px 18px 0;
    }
  }
</style>
