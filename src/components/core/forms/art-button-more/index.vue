<!-- 更多按钮 -->
<template>
  <div>
    <ElDropdown v-if="hasAnyAuthItem">
      <ArtIconButton
        icon="ri:more-2-fill"
        label="更多操作"
        class="!size-8 bg-g-200 dark:bg-g-300/45 text-sm"
      />
      <template #dropdown>
        <ElDropdownMenu>
          <template v-for="item in dropdownList" :key="item.key">
            <ElDropdownItem
              v-if="isItemAuthorized(item)"
              :disabled="item.disabled"
              @click="handleClick(item)"
            >
              <div class="flex-c gap-2" :style="{ color: item.color }">
                <ArtSvgIcon v-if="item.icon" :icon="item.icon" />
                <span>{{ item.label }}</span>
              </div>
            </ElDropdownItem>
          </template>
        </ElDropdownMenu>
      </template>
    </ElDropdown>
  </div>
</template>

<script setup lang="ts">
  import { useRoute } from 'vue-router'
  import { useAuth } from '@/hooks/core/useAuth'
  import { resolveBusinessButtonPermission } from '@/utils/business-permission'

  defineOptions({ name: 'ArtButtonMore' })

  const { hasAuth } = useAuth()
  const route = useRoute()

  export interface ButtonMoreItem {
    /** 按钮标识，可用于点击事件 */
    key: string | number
    /** 按钮文本 */
    label: string
    /** 是否禁用 */
    disabled?: boolean
    /** 权限标识 */
    auth?: string
    /** 图标组件 */
    icon?: string
    /** 文本颜色 */
    color?: string
    /** 图标颜色（优先级高于 color） */
    iconColor?: string
  }

  interface Props {
    /** 下拉项列表 */
    list: ButtonMoreItem[] | (() => ButtonMoreItem[])
    /** 整体权限控制 */
    auth?: string
  }

  const props = withDefaults(defineProps<Props>(), {})

  const dropdownList = computed(() =>
    typeof props.list === 'function' ? props?.list() : props.list
  )

  const resolveItemPermission = (item: ButtonMoreItem): string | undefined =>
    resolveBusinessButtonPermission(route, item.key, item.auth)

  const isItemAuthorized = (item: ButtonMoreItem): boolean => {
    const permission = resolveItemPermission(item)
    return !permission || hasAuth(permission)
  }

  // 检查是否有任何有权限的 item
  const hasAnyAuthItem = computed(() => {
    if (props.auth && !hasAuth(props.auth)) return false
    return dropdownList.value.some(isItemAuthorized)
  })

  const emit = defineEmits<{
    (e: 'click', item: ButtonMoreItem): void
  }>()

  const handleClick = (item: ButtonMoreItem) => {
    emit('click', item)
  }
</script>
