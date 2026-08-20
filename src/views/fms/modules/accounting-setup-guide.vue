<template>
  <div v-if="!loading && !hasAccountSet" class="accounting-setup-guide">
    <span class="accounting-setup-guide__icon" aria-hidden="true">
      <ArtSvgIcon icon="ri:book-2-line" />
    </span>
    <div class="accounting-setup-guide__copy">
      <strong>需要先建立企业账套</strong>
      <p>
        {{
          canConfigure
            ? '账套会确定法人主体、会计准则、本位币和启用期间；创建完成后，本页操作会自动开放。'
            : '当前租户尚未建立可用账套，请联系管理员授予账套维护权限或完成财务初始化。'
        }}
      </p>
    </div>
    <ElButton v-if="canConfigure" type="primary" plain @click="emit('configure')">
      前往账套管理
      <ArtSvgIcon icon="ri:arrow-right-line" />
    </ElButton>
  </div>
</template>

<script setup lang="ts">
  defineOptions({ name: 'AccountingSetupGuide' })

  withDefaults(
    defineProps<{
      loading?: boolean
      hasAccountSet?: boolean
      canConfigure?: boolean
    }>(),
    {
      loading: false,
      hasAccountSet: false,
      canConfigure: false
    }
  )

  const emit = defineEmits<{ configure: [] }>()
</script>

<style scoped lang="scss">
  .accounting-setup-guide {
    display: grid;
    grid-template-columns: 36px minmax(0, 1fr) auto;
    gap: 12px;
    align-items: center;
    padding: 10px 14px;
    margin-top: 12px;
    color: var(--el-text-color-regular);
    background: color-mix(in srgb, var(--el-color-warning) 7%, var(--default-box-color));
    border: 1px solid color-mix(in srgb, var(--el-color-warning) 24%, var(--el-border-color));
    border-radius: var(--el-border-radius-base);

    &__icon {
      display: grid;
      place-items: center;
      width: 36px;
      height: 36px;
      font-size: 18px;
      color: var(--el-color-warning-dark-2);
      background: color-mix(in srgb, var(--el-color-warning) 14%, transparent);
      border-radius: var(--el-border-radius-base);
    }

    &__copy {
      min-width: 0;

      strong {
        display: block;
        margin-bottom: 1px;
        font-size: 13px;
        font-weight: 600;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        font-size: 12px;
        line-height: 18px;
        color: var(--el-text-color-secondary);
      }
    }

    @media (width <= 640px) {
      grid-template-columns: 36px minmax(0, 1fr);
      padding: 12px;

      &__icon {
        width: 36px;
        height: 36px;
      }

      :deep(.el-button) {
        grid-column: 1 / -1;
        width: 100%;
        margin-left: 0;
      }
    }
  }
</style>
