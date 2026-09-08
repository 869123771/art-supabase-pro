<template>
  <div
    class="art-entity-summary"
    :class="{ 'art-entity-summary--compact': compact }"
    role="group"
    :aria-label="ariaLabel || title"
  >
    <span v-if="icon || $slots.icon" class="art-entity-summary__icon" aria-hidden="true">
      <slot name="icon">
        <ArtSvgIcon :icon="icon" />
      </slot>
    </span>

    <div class="art-entity-summary__content">
      <small v-if="eyebrow">{{ eyebrow }}</small>
      <strong>{{ title }}</strong>
      <p v-if="description">{{ description }}</p>
    </div>

    <div v-if="$slots.aside" class="art-entity-summary__aside">
      <slot name="aside" />
    </div>
  </div>
</template>

<script setup lang="ts">
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  defineOptions({ name: 'ArtEntitySummary' })

  withDefaults(
    defineProps<{
      title: string
      description?: string
      eyebrow?: string
      icon?: string
      ariaLabel?: string
      compact?: boolean
    }>(),
    {
      description: '',
      eyebrow: '',
      icon: '',
      ariaLabel: '',
      compact: false
    }
  )
</script>

<style scoped lang="scss">
  .art-entity-summary {
    display: grid;
    grid-template-columns: 44px minmax(0, 1fr) auto;
    gap: var(--art-space-3);
    align-items: center;
    min-width: 0;
    padding: var(--art-space-3) var(--art-space-4);
    background: color-mix(in srgb, var(--theme-color) 7%, var(--default-box-color));
    border: 1px solid color-mix(in srgb, var(--theme-color) 16%, var(--art-card-border));
    border-radius: var(--art-control-radius);

    &__icon {
      display: grid;
      place-items: center;
      width: 44px;
      height: 44px;
      font-size: 20px;
      color: var(--theme-color);
      background: var(--default-box-color);
      border: 1px solid color-mix(in srgb, var(--theme-color) 10%, var(--art-card-border));
      border-radius: var(--art-control-radius);
    }

    &__content {
      min-width: 0;

      small,
      strong,
      p {
        display: block;
        margin: 0;
      }

      small {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 10px;
        font-weight: 700;
        line-height: 16px;
        color: var(--theme-color);
        letter-spacing: 0.08em;
        white-space: nowrap;
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 14px;
        line-height: 22px;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }

      p {
        margin-top: 1px;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        line-height: 19px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }
    }

    &__aside {
      display: flex;
      align-items: center;
      justify-content: flex-end;
      min-width: 0;
    }

    &--compact {
      grid-template-columns: 38px minmax(0, 1fr) auto;
      padding: var(--art-space-2) var(--art-space-3);

      .art-entity-summary__icon {
        width: 38px;
        height: 38px;
        font-size: 18px;
      }
    }

    :global([data-box-mode='border-mode']) & {
      box-shadow: none;
    }

    :global([data-box-mode='shadow-mode']) & {
      border-color: transparent;
      box-shadow: var(--art-card-shadow-xs);
    }

    @media (width <= 720px) {
      grid-template-columns: 40px minmax(0, 1fr);

      &__icon {
        width: 40px;
        height: 40px;
      }

      &__aside {
        grid-column: 1 / -1;
        justify-content: flex-start;
      }

      &__content p {
        overflow-wrap: anywhere;
        white-space: normal;
      }
    }
  }
</style>
