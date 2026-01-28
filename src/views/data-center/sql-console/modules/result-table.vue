<template>
  <div class="result-table-container h-full">
    <ArtTable
      table-layout="auto"
      ref="tableRef"
      :loading="loading"
      :data="tableData"
      :columns="tableColumns"
      :cell-class-name="cellClassName"
      border
      class="h-full"
      @cell-click="handleCellClick"
      @cell-contextmenu="handleCellContextMenu"
    />

    <!-- Context Menu -->
    <ArtMenuRight
      ref="menuRef"
      :menu-items="menuItems"
      :menu-width="180"
      :submenu-width="140"
      :border-radius="10"
      @select="handleMenuSelect"
    />

    <!-- Cell Content Drawer -->
    <CellContentView
      v-model="drawerVisible"
      :content="currentCellContent"
      :column-name="currentColumnName"
    />
  </div>
</template>

<script setup lang="ts">
  import { ref, computed, nextTick } from 'vue'
  import { isObject } from 'lodash-es'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtMenuRight, { MenuItemType } from '@/components/core/others/art-menu-right/index.vue'
  import CellContentView from './cell-content-view.vue'
  import { useClipboard } from '@vueuse/core'

  interface Props {
    loading?: boolean
    data?: any[]
    columns?: any[] // Metadata columns
  }

  const props = withDefaults(defineProps<Props>(), {
    loading: false,
    data: () => [],
    columns: () => []
  })

  const menuRef = ref()
  const tableRef = ref()
  const drawerVisible = ref(false)
  const currentCellContent = ref('')
  const currentColumnName = ref('')
  const { copy } = useClipboard()

  // Selected cell info
  const selectedCell = ref<{
    row: any
    column: any
    event: MouseEvent
  } | null>(null)

  // Compute table columns
  const tableColumns = computed(() => {
    if (!props.columns || props.columns.length === 0) {
      return []
    }

    return props.columns.map((column) => ({
      prop: column.name,
      label: column.name,
      minWidth: 120,
      formatter: (row: any) => {
        const value = row[column.name]
        if (isObject(value)) {
          return JSON.stringify(value)
        }
        return value
      }
    }))
  })

  const tableData = computed(() => props.data)

  // Menu Items
  const menuItems = computed((): MenuItemType[] => [
    {
      key: 'copy',
      label: '复制',
      icon: 'ri-file-copy-line'
    },
    {
      key: 'view',
      label: '查看',
      icon: 'ri-eye-line'
    }
  ])

  // Handle Cell Click (Left Click)
  const handleCellClick = (row: any, column: any, cell: any, event: MouseEvent) => {
    selectedCell.value = { row, column, event }
    currentColumnName.value = column.property
    const value = row[column.property]
    currentCellContent.value = isObject(value) ? JSON.stringify(value) : String(value ?? '')
  }

  // Handle Cell Context Menu (Right Click)
  const handleCellContextMenu = (row: any, column: any, cell: any, event: MouseEvent) => {
    // Prevent default browser menu
    event.preventDefault()

    // Update selected cell info
    selectedCell.value = { row, column, event }
    currentColumnName.value = column.property

    // Get content
    const value = row[column.property]
    currentCellContent.value = isObject(value) ? JSON.stringify(value) : String(value ?? '')

    // Show menu
    nextTick(() => {
      menuRef.value?.show(event)
    })
  }

  // Handle Menu Selection
  const handleMenuSelect = (item: any) => {
    if (!selectedCell.value) return

    if (item.key === 'copy') {
      copy(currentCellContent.value)
    } else if (item.key === 'view') {
      openDrawer()
    }
  }

  const openDrawer = () => {
    drawerVisible.value = true
  }

  const cellClassName = ({ row, column }: { row: any; column: any }) => {
    if (
      selectedCell.value &&
      selectedCell.value.row === row &&
      selectedCell.value.column.property === column.property
    ) {
      return 'selected-cell'
    }
    return ''
  }
</script>

<style scoped lang="scss">
  .result-table-container {
    :deep(.el-table) {
      height: 100%;

      // Add selection style if needed
      .el-table__cell {
        // cursor: default;
      }

      .selected-cell {
        box-shadow: inset 0 0 0 2px var(--el-color-primary);
        z-index: 1;
        position: relative;
      }
    }
  }
</style>
