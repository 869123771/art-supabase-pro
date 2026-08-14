<template>
  <div class="favorite-route-address-option">
    <div class="favorite-route-address-option__heading">
      <strong :title="ownerName">{{ ownerName }}</strong>
      <ElTag v-if="option.isDefault" size="small" type="primary" effect="light">默认</ElTag>
    </div>

    <div class="favorite-route-address-option__contact">
      <span>
        <ArtSvgIcon icon="ri:user-3-line" aria-hidden="true" />
        {{ option.contactName || '未维护联系人' }}
      </span>
      <span>
        <ArtSvgIcon icon="ri:phone-line" aria-hidden="true" />
        {{ option.contactPhone || '未维护联系电话' }}
      </span>
    </div>

    <p :title="fullAddress">
      <ArtSvgIcon icon="ri:map-pin-2-line" aria-hidden="true" />
      <span>{{ fullAddress }}</span>
    </p>
  </div>
</template>

<script setup lang="ts">
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  type CustomerAddress = Api.Tms.BasicData.CustomerAddress

  const props = defineProps<{
    option: CustomerAddress
  }>()

  const ownerName = computed(() => props.option.customer?.customerName || '公共地址')
  const fullAddress = computed(
    () =>
      [props.option.region, props.option.addressDetail].filter(Boolean).join(' ') ||
      '未维护详细地址'
  )
</script>

<style scoped lang="scss">
  .favorite-route-address-option {
    display: grid;
    gap: 6px;
    min-width: 0;
    padding: 10px 2px;

    &__heading {
      display: flex;
      gap: 8px;
      align-items: center;
      min-width: 0;

      strong {
        min-width: 0;
        overflow: hidden;
        font-size: 14px;
        color: var(--el-text-color-primary);
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .el-tag {
        flex: 0 0 auto;
      }
    }

    &__contact {
      display: flex;
      flex-wrap: wrap;
      gap: 6px 16px;
      min-width: 0;
      font-size: 12px;
      color: var(--el-text-color-secondary);

      span {
        display: inline-flex;
        gap: 5px;
        align-items: center;
        min-width: 0;
      }

      svg {
        flex: 0 0 auto;
      }
    }

    p {
      display: flex;
      gap: 6px;
      align-items: flex-start;
      min-width: 0;
      margin: 0;
      font-size: 12px;
      line-height: 18px;
      color: var(--el-text-color-regular);

      svg {
        flex: 0 0 auto;
        margin-top: 2px;
        color: var(--el-color-primary);
      }

      span {
        display: -webkit-box;
        overflow: hidden;
        overflow-wrap: anywhere;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 2;
      }
    }
  }
</style>
