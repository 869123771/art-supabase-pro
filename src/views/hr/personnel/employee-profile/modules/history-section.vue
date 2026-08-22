<template>
  <section class="hr-history-section">
    <header class="hr-history-section__header">
      <div class="hr-history-section__identity">
        <span aria-hidden="true"><ArtSvgIcon :icon="icon" /></span>
        <div>
          <h2>{{ title }}</h2>
          <p>{{ description }}</p>
        </div>
      </div>
      <ElButton v-if="!readonly" type="primary" plain @click="emit('add')">
        <ArtSvgIcon icon="ri:add-line" />
        {{ addLabel }}
      </ElButton>
    </header>

    <div v-if="count" class="hr-history-section__records"><slot /></div>
    <div v-else class="hr-history-section__empty">
      <span aria-hidden="true"><ArtSvgIcon :icon="icon" /></span>
      <strong>暂无{{ title }}</strong>
      <p>{{
        readonly
          ? '当前权限仅支持查看，无法维护此类履历。'
          : `点击“${addLabel}”补充员工的${title}。`
      }}</p>
      <ElButton v-if="!readonly" type="primary" @click="emit('add')">{{ addLabel }}</ElButton>
    </div>
  </section>
</template>

<script setup lang="ts">
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  defineOptions({ name: 'HrHistorySection' })
  defineProps<{
    title: string
    description: string
    addLabel: string
    icon: string
    count: number
    readonly?: boolean
  }>()
  const emit = defineEmits<{ (event: 'add'): void }>()
</script>

<style scoped lang="scss">
  .hr-history-section {
    min-width: 0;

    &__header,
    &__identity {
      display: flex;
      align-items: center;
    }

    &__header {
      gap: 16px;
      justify-content: space-between;
      padding: 4px 0 18px;
    }

    &__identity {
      min-width: 0;

      > span {
        display: inline-flex;
        flex: 0 0 42px;
        align-items: center;
        justify-content: center;
        width: 42px;
        height: 42px;
        margin-right: 12px;
        font-size: 21px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: 12px;
      }

      h2 {
        margin: 0;
        font-size: 17px;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 4px 0 0;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__records {
      display: grid;
      gap: 14px;
    }

    &__empty {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 250px;
      padding: 30px;
      text-align: center;
      background: color-mix(in srgb, var(--el-fill-color-light) 62%, transparent);
      border: 1px dashed var(--el-border-color);
      border-radius: var(--custom-radius);

      > span {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 54px;
        height: 54px;
        margin-bottom: 12px;
        font-size: 26px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: 16px;
      }

      strong {
        font-size: 15px;
      }

      p {
        margin: 7px 0 16px;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    @media (width <= 640px) {
      &__header {
        align-items: flex-start;
      }

      &__identity p {
        display: none;
      }
    }
  }
</style>
