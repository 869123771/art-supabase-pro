<template>
  <section class="number-menu-filter" aria-label="编号规则功能菜单筛选">
    <header class="number-menu-filter__header">
      <div class="number-menu-filter__heading">
        <span class="number-menu-filter__brand" aria-hidden="true">
          <ArtSvgIcon icon="ri:node-tree" />
        </span>
        <div>
          <strong>功能导航</strong>
          <small>{{ menuPageCount }} 个功能页 · {{ sceneCount }} 项编号</small>
        </div>
      </div>

      <ElTooltip content="刷新菜单目录" placement="top">
        <ElButton
          class="number-menu-filter__refresh"
          :class="{ 'is-refreshing': loading }"
          text
          circle
          :disabled="loading"
          aria-label="刷新菜单目录"
          @click="emit('refresh')"
        >
          <ArtSvgIcon icon="ri:refresh-line" />
        </ElButton>
      </ElTooltip>
    </header>

    <div class="number-menu-filter__search">
      <ElInput
        v-model="keyword"
        clearable
        placeholder="搜索菜单或编号功能"
        aria-label="搜索菜单或编号功能"
      >
        <template #prefix>
          <ArtSvgIcon icon="ri:search-line" />
        </template>
      </ElInput>
    </div>

    <nav class="number-menu-filter__quick" aria-label="全部编号功能">
      <button type="button" :class="{ 'is-active': !selectedMenuId }" @click="handleSelect('')">
        <span class="number-menu-filter__quick-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:apps-2-line" />
        </span>
        <span>
          <strong>全部功能</strong>
          <small>查看当前权限范围内全部编号规则</small>
        </span>
        <ElTag size="small" round>{{ sceneCount }}</ElTag>
      </button>
    </nav>

    <div class="number-menu-filter__section-title">
      <span>业务菜单树</span>
      <small>点击目录包含下级</small>
    </div>

    <div v-loading="loading" class="number-menu-filter__tree-area">
      <ElScrollbar v-if="filterTree.length">
        <ElTree
          ref="treeRef"
          :data="filterTree"
          node-key="id"
          :props="treeProps"
          :default-expanded-keys="defaultExpandedKeys"
          :expand-on-click-node="false"
          highlight-current
          :filter-node-method="filterNode"
          @node-click="handleNodeClick"
        >
          <template #default="{ data }">
            <div class="number-menu-filter__node">
              <span class="number-menu-filter__node-icon" aria-hidden="true">
                <ArtSvgIcon :icon="resolveNodeIcon(data)" />
              </span>
              <span class="number-menu-filter__node-copy">
                <strong :title="resolveLabel(data)">{{ resolveLabel(data) }}</strong>
                <small>{{
                  data.directSceneCount ? `${data.directSceneCount} 项直接接入` : '业务目录'
                }}</small>
              </span>
              <span class="number-menu-filter__node-count">{{ data.sceneCount }}</span>
            </div>
          </template>
        </ElTree>
      </ElScrollbar>

      <ElEmpty v-else :image-size="58" description="暂无已接入编号的菜单" />
    </div>

    <footer class="number-menu-filter__footer">
      <div class="number-menu-filter__selection" aria-live="polite">
        <span aria-hidden="true"><ArtSvgIcon icon="ri:filter-3-line" /></span>
        <div>
          <small>当前筛选</small>
          <strong>{{ selectedLabel }}</strong>
        </div>
        <ElTag
          class="number-menu-filter__count-tag"
          type="primary"
          effect="plain"
          size="small"
          round
        >
          {{ selectedSceneCount }} 项
        </ElTag>
      </div>
    </footer>
  </section>
</template>

<script setup lang="ts">
  import { ElTree, type TreeNodeData } from 'element-plus'
  import type { AppRouteRecord } from '@/types/router'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  interface FilterMenuNode extends AppRouteRecord {
    directSceneCount: number
    sceneCount: number
    sceneNames: string[]
    children?: FilterMenuNode[]
  }

  const props = withDefaults(
    defineProps<{
      data: AppRouteRecord[]
      scenes: Api.SystemManage.DocumentNumberSceneItem[]
      selectedMenuId?: string
      loading?: boolean
    }>(),
    {
      selectedMenuId: '',
      loading: false
    }
  )

  const emit = defineEmits<{
    select: [menuId: string]
    refresh: []
  }>()

  const treeRef = ref<InstanceType<typeof ElTree>>()
  const keyword = ref('')
  const treeProps = {
    children: 'children',
    label: (data: TreeNodeData) => resolveLabel(data)
  }

  const sceneMap = computed(() => {
    const result = new Map<string, Api.SystemManage.DocumentNumberSceneItem[]>()
    props.scenes.forEach((scene) => {
      const items = result.get(scene.menuId) ?? []
      items.push(scene)
      result.set(scene.menuId, items)
    })
    return result
  })

  const toFilterNode = (menu: AppRouteRecord): FilterMenuNode | null => {
    const children = (menu.children ?? [])
      .map(toFilterNode)
      .filter((item): item is FilterMenuNode => Boolean(item))
    const directScenes = menu.id ? (sceneMap.value.get(menu.id) ?? []) : []
    const sceneCount =
      directScenes.length + children.reduce((total, item) => total + item.sceneCount, 0)

    if (!sceneCount) return null
    return {
      ...menu,
      directSceneCount: directScenes.length,
      sceneCount,
      sceneNames: directScenes.flatMap((scene) => [
        scene.ruleName,
        scene.fieldLabel,
        scene.ruleKey
      ]),
      children
    }
  }

  const filterTree = computed<FilterMenuNode[]>(() =>
    props.data.map(toFilterNode).filter((item): item is FilterMenuNode => Boolean(item))
  )
  const flatFilterTree = computed<FilterMenuNode[]>(() => {
    const result: FilterMenuNode[] = []
    const visit = (items: FilterMenuNode[]): void => {
      items.forEach((item) => {
        result.push(item)
        visit(item.children ?? [])
      })
    }
    visit(filterTree.value)
    return result
  })
  const sceneCount = computed(() => props.scenes.length)
  const menuPageCount = computed(
    () => flatFilterTree.value.filter((item) => item.directSceneCount > 0).length
  )
  const defaultExpandedKeys = computed(() =>
    filterTree.value.map((item) => item.id).filter((id): id is string => Boolean(id))
  )
  const selectedNode = computed(() =>
    flatFilterTree.value.find((item) => item.id === props.selectedMenuId)
  )
  const selectedLabel = computed(() =>
    selectedNode.value ? resolveLabel(selectedNode.value) : '全部功能'
  )
  const selectedSceneCount = computed(() => selectedNode.value?.sceneCount ?? sceneCount.value)

  function resolveLabel(menu: { meta?: { title?: unknown }; name?: unknown }): string {
    return String(menu.meta?.title || menu.name || '未命名菜单')
  }

  const resolveNodeIcon = (menu: FilterMenuNode): string => {
    if (menu.children?.length) return 'ri:folder-3-line'
    return String(menu.meta?.icon || 'ri:file-list-3-line')
  }

  const filterNode = (value: string, data: TreeNodeData): boolean => {
    const menu = data as FilterMenuNode
    const normalized = value.trim().toLocaleLowerCase('zh-CN')
    if (!normalized) return true
    return [resolveLabel(menu), menu.name, menu.path, ...menu.sceneNames].some((field) =>
      String(field ?? '')
        .toLocaleLowerCase('zh-CN')
        .includes(normalized)
    )
  }

  const syncCurrentNode = async (): Promise<void> => {
    await nextTick()
    treeRef.value?.setCurrentKey(props.selectedMenuId || undefined)
  }

  const handleSelect = (menuId: string): void => emit('select', menuId)
  const handleNodeClick = (menu: FilterMenuNode): void => {
    if (menu.id) handleSelect(menu.id)
  }

  watch(keyword, (value) => treeRef.value?.filter(value))
  watch(() => props.selectedMenuId, syncCurrentNode, { immediate: true })
  watch(filterTree, async () => {
    await syncCurrentNode()
    treeRef.value?.filter(keyword.value)
  })
</script>

<style scoped lang="scss">
  .number-menu-filter {
    display: flex;
    flex-direction: column;
    min-width: 0;
    height: 100%;
    overflow: hidden;
    background: var(--el-bg-color);
    border: 1px solid var(--el-border-color-lighter);
    border-radius: var(--custom-radius);

    &__header,
    &__heading,
    &__node,
    &__selection,
    &__quick button {
      display: flex;
      align-items: center;
    }

    &__header {
      flex: none;
      justify-content: space-between;
      padding: 16px 16px 13px;
      background: linear-gradient(145deg, var(--el-color-primary-light-9), transparent 74%);
      border-bottom: 1px solid var(--el-border-color-lighter);
    }

    &__heading {
      min-width: 0;

      > div {
        display: grid;
        min-width: 0;
      }

      strong {
        font-size: 15px;
        color: var(--el-text-color-primary);
      }

      small {
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }
    }

    &__brand,
    &__quick-icon,
    &__node-icon,
    &__footer > span {
      display: inline-flex;
      flex: none;
      align-items: center;
      justify-content: center;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--custom-radius);
    }

    &__brand {
      width: 36px;
      height: 36px;
      margin-right: 10px;
      border: 1px solid var(--el-color-primary-light-7);
    }

    &__refresh.is-refreshing :deep(svg) {
      animation: number-menu-filter-spin 720ms linear infinite;
    }

    &__search {
      flex: none;
      padding: 14px 14px 10px;
    }

    &__quick {
      flex: none;
      padding: 0 10px 10px;

      button {
        width: 100%;
        min-height: 56px;
        padding: 8px 9px;
        font: inherit;
        text-align: left;
        cursor: pointer;
        background: transparent;
        border: 1px solid transparent;
        border-radius: var(--el-border-radius-base);
        transition: 160ms ease;

        > span:nth-child(2) {
          display: grid;
          flex: 1;
          min-width: 0;
        }

        strong {
          font-size: 13px;
          color: var(--el-text-color-primary);
        }

        small {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 10px;
          color: var(--el-text-color-secondary);
          white-space: nowrap;
        }

        &:hover {
          background: var(--el-fill-color-light);
        }

        &.is-active {
          background: var(--el-color-primary-light-9);
          border-color: var(--el-color-primary-light-7);
          box-shadow: inset 3px 0 0 var(--el-color-primary);
        }
      }
    }

    &__quick-icon {
      width: 32px;
      height: 32px;
      margin-right: 9px;
    }

    &__section-title {
      display: flex;
      flex: none;
      align-items: center;
      justify-content: space-between;
      padding: 10px 14px 8px;
      background: var(--el-fill-color-lighter);
      border-top: 1px solid var(--el-border-color-lighter);
      border-bottom: 1px solid var(--el-border-color-lighter);

      span {
        font-size: 12px;
        font-weight: 700;
      }

      small {
        font-size: 10px;
        color: var(--el-text-color-secondary);
      }
    }

    &__tree-area {
      flex: 1 1 auto;
      min-height: 120px;
      padding: 8px;
      overflow: hidden;

      :deep(.el-tree) {
        background: transparent;
      }

      :deep(.el-tree-node__content) {
        height: 48px;
        padding-right: 5px;
        margin-bottom: 2px;
        border-radius: var(--el-border-radius-base);
      }

      :deep(.el-tree-node__children) {
        padding-left: 6px;
        margin-left: 11px;
        border-left: 1px dashed var(--el-color-primary-light-6);
      }

      :deep(.el-tree-node.is-current > .el-tree-node__content) {
        background: var(--el-color-primary-light-9);
      }
    }

    &__node {
      flex: 1;
      min-width: 0;
      height: 100%;
    }

    &__node-icon {
      width: 28px;
      height: 28px;
      margin-right: 7px;
      border-radius: var(--el-border-radius-base);
    }

    &__node-copy {
      display: grid;
      flex: 1;
      min-width: 0;

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        font-size: 12px;
        color: var(--el-text-color-primary);
      }

      small {
        font-size: 10px;
        color: var(--el-text-color-secondary);
      }
    }

    &__node-count {
      flex: none;
      min-width: 23px;
      padding: 0 5px;
      margin-left: 6px;
      font-size: 10px;
      line-height: 20px;
      color: var(--el-text-color-secondary);
      text-align: center;
      background: var(--el-fill-color);
      border-radius: 999px;
    }

    &__footer {
      display: grid;
      flex: none;
      padding: 12px 14px 14px;
      background: var(--el-fill-color-lighter);
      border-top: 1px solid var(--el-border-color-lighter);
    }

    &__selection {
      gap: 9px;
      min-width: 0;
      padding: 9px 10px;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      > span {
        display: inline-flex;
        flex: 0 0 28px;
        align-items: center;
        justify-content: center;
        width: 28px;
        height: 28px;
      }

      > div {
        display: grid;
        flex: 1;
        min-width: 0;
      }

      small,
      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      small {
        font-size: 10px;
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 12px;
        color: var(--el-text-color-primary);
      }
    }

    &__count-tag.el-tag {
      flex: none;
      justify-content: center;
      min-width: 46px;
      padding-inline: 8px;
      white-space: nowrap;
      border-radius: 999px;
    }
  }

  @keyframes number-menu-filter-spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
