<template>
  <section class="workflow-menu-filter" aria-label="审批业务菜单筛选">
    <header class="workflow-menu-filter__header">
      <div class="workflow-menu-filter__heading">
        <span class="workflow-menu-filter__brand" aria-hidden="true">
          <ArtSvgIcon icon="ri:node-tree" />
        </span>
        <div>
          <strong>业务导航</strong>
          <small>{{ menuPageCount }} 个功能页 · {{ contractCount }} 类审批</small>
        </div>
      </div>
      <ElTooltip content="刷新业务目录" placement="top">
        <ArtIconButton
          icon="ri:refresh-line"
          circle
          label="刷新业务目录"
          :loading="loading"
          @click="emit('refresh')"
        />
      </ElTooltip>
    </header>

    <div class="workflow-menu-filter__search">
      <ElInput
        v-model="keyword"
        clearable
        placeholder="搜索菜单或审批业务"
        aria-label="搜索菜单或审批业务"
      >
        <template #prefix><ArtSvgIcon icon="ri:search-line" /></template>
      </ElInput>
    </div>

    <nav class="workflow-menu-filter__quick" aria-label="全部审批业务">
      <button type="button" :class="{ 'is-active': !selectedMenuId }" @click="handleSelectAll">
        <span class="workflow-menu-filter__quick-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:apps-2-line" />
        </span>
        <span><strong>全部业务</strong><small>查看全部已接入审批的业务</small></span>
        <ElTag size="small" round>{{ contractCount }}</ElTag>
      </button>
    </nav>

    <div class="workflow-menu-filter__section-title">
      <span>业务菜单树</span><small>选择目录包含下级</small>
    </div>

    <div v-loading="loading" class="workflow-menu-filter__tree-area">
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
            <div class="workflow-menu-filter__node">
              <span class="workflow-menu-filter__node-icon" aria-hidden="true">
                <ArtSvgIcon :icon="resolveNodeIcon(data)" />
              </span>
              <span class="workflow-menu-filter__node-copy">
                <strong :title="resolveLabel(data)">{{ resolveLabel(data) }}</strong>
                <small>{{
                  data.directCount ? `${data.directCount} 类直接接入` : '业务目录'
                }}</small>
              </span>
              <span class="workflow-menu-filter__node-count">{{ data.businessTypes.length }}</span>
            </div>
          </template>
        </ElTree>
      </ElScrollbar>
      <ArtEmptyState v-else title="暂无已接入审批的菜单" size="compact" :visual-size="58" />
    </div>

    <footer class="workflow-menu-filter__footer">
      <div class="workflow-menu-filter__selection" aria-live="polite">
        <span aria-hidden="true"><ArtSvgIcon icon="ri:filter-3-line" /></span>
        <div
          ><small>当前范围</small><strong>{{ selectedLabel }}</strong></div
        >
        <ElTag
          class="workflow-menu-filter__count-tag"
          type="primary"
          effect="plain"
          size="small"
          round
        >
          {{ selectedCount }} 类
        </ElTag>
      </div>
    </footer>
  </section>
</template>

<script setup lang="ts">
  import { ElTree, type TreeNodeData } from 'element-plus'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtEmptyState from '@/components/core/feedback/art-empty-state/index.vue'
  import type { AppRouteRecord } from '@/types/router'
  import TreeUtils from '@/utils/tree'
  import { workflowBusinessContracts } from '../../modules/workflow-business-contracts'

  interface WorkflowMenuNode extends AppRouteRecord {
    directCount: number
    businessTypes: string[]
    searchTerms: string[]
    children?: WorkflowMenuNode[]
  }

  const props = withDefaults(
    defineProps<{ data: AppRouteRecord[]; selectedMenuId?: string; loading?: boolean }>(),
    { selectedMenuId: '', loading: false }
  )
  const emit = defineEmits<{
    select: [menuId: string, businessTypes: string[], label: string]
    refresh: []
  }>()

  const treeUtils = new TreeUtils({ idKey: 'id', parentKey: 'parentId', childrenKey: 'children' })
  const treeRef = ref<InstanceType<typeof ElTree>>()
  const keyword = ref('')
  const contractsByMenuName = computed(() => {
    const result = new Map<string, typeof workflowBusinessContracts>()
    workflowBusinessContracts.forEach((contract) => {
      const contracts = result.get(contract.menuName) ?? []
      contracts.push(contract)
      result.set(contract.menuName, contracts)
    })
    return result
  })

  const toWorkflowNode = (menu: AppRouteRecord): WorkflowMenuNode | null => {
    const children = (menu.children ?? [])
      .map(toWorkflowNode)
      .filter((item): item is WorkflowMenuNode => Boolean(item))
    const directContracts = contractsByMenuName.value.get(String(menu.name ?? '')) ?? []
    const businessTypes = [
      ...directContracts.map((contract) => contract.businessType),
      ...children.flatMap((child) => child.businessTypes)
    ]
    if (!businessTypes.length) return null
    return {
      ...menu,
      directCount: directContracts.length,
      businessTypes,
      searchTerms: directContracts.flatMap((contract) => [contract.label, contract.businessType]),
      children
    }
  }

  const filterTree = computed<WorkflowMenuNode[]>(() =>
    props.data.map(toWorkflowNode).filter((item): item is WorkflowMenuNode => Boolean(item))
  )
  const flatTree = computed(() => treeUtils.treeToList<WorkflowMenuNode>(filterTree.value))
  const selectedNode = computed(() =>
    flatTree.value.find((item) => String(item.id) === props.selectedMenuId)
  )
  const contractCount = computed(() => workflowBusinessContracts.length)
  const menuPageCount = computed(() => flatTree.value.filter((item) => item.directCount > 0).length)
  const selectedLabel = computed(() =>
    selectedNode.value ? resolveLabel(selectedNode.value) : '全部业务'
  )
  const selectedCount = computed(
    () => selectedNode.value?.businessTypes.length ?? contractCount.value
  )
  const defaultExpandedKeys = computed(() =>
    filterTree.value.map((item) => item.id).filter((id): id is string => typeof id === 'string')
  )
  const treeProps = { children: 'children', label: (data: TreeNodeData) => resolveLabel(data) }

  function resolveLabel(menu: { meta?: { title?: unknown }; name?: unknown }): string {
    return String(menu.meta?.title || menu.name || '未命名菜单')
  }

  function resolveNodeIcon(menu: WorkflowMenuNode): string {
    if (menu.children?.length) return 'ri:folder-3-line'
    return String(menu.meta?.icon || 'ri:file-list-3-line')
  }

  function filterNode(value: string, data: TreeNodeData): boolean {
    const menu = data as WorkflowMenuNode
    const normalized = value.trim().toLocaleLowerCase('zh-CN')
    if (!normalized) return true
    return [resolveLabel(menu), menu.name, menu.path, ...menu.searchTerms].some((field) =>
      String(field ?? '')
        .toLocaleLowerCase('zh-CN')
        .includes(normalized)
    )
  }

  function handleSelectAll(): void {
    emit(
      'select',
      '',
      workflowBusinessContracts.map((contract) => contract.businessType),
      '全部业务'
    )
  }

  function handleNodeClick(menu: WorkflowMenuNode): void {
    if (menu.id) emit('select', String(menu.id), menu.businessTypes, resolveLabel(menu))
  }

  async function syncCurrentNode(): Promise<void> {
    await nextTick()
    treeRef.value?.setCurrentKey(props.selectedMenuId || undefined)
  }

  watch(keyword, (value) => treeRef.value?.filter(value))
  watch(() => props.selectedMenuId, syncCurrentNode, { immediate: true })
  watch(filterTree, async () => {
    await syncCurrentNode()
    treeRef.value?.filter(keyword.value)
  })
</script>

<style scoped lang="scss">
  .workflow-menu-filter {
    box-sizing: border-box;
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
      padding: 12px 12px 10px;
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
        font-size: 14px;
        color: var(--el-text-color-primary);
      }

      small {
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }
    }

    &__brand,
    &__quick-icon,
    &__node-icon {
      display: inline-flex;
      flex: none;
      align-items: center;
      justify-content: center;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--custom-radius);
    }

    &__brand {
      width: 32px;
      height: 32px;
      margin-right: 8px;
      border: 1px solid var(--el-color-primary-light-7);
    }

    &__search {
      flex: none;
      padding: 10px 10px 8px;
    }

    &__quick {
      flex: none;
      padding: 0 8px 8px;

      button {
        width: 100%;
        min-height: 48px;
        padding: 6px 8px;
        font: inherit;
        text-align: left;
        cursor: pointer;
        background: transparent;
        border: 1px solid transparent;
        border-radius: var(--el-border-radius-base);
        transition:
          color 160ms ease,
          background-color 160ms ease,
          border-color 160ms ease,
          box-shadow 160ms ease;

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

        &:focus-visible {
          outline: 2px solid var(--el-color-primary);
          outline-offset: 2px;
        }

        &.is-active {
          background: var(--el-color-primary-light-9);
          border-color: var(--el-color-primary-light-7);
          box-shadow: inset 3px 0 0 var(--el-color-primary);
        }
      }
    }

    &__quick-icon {
      width: 28px;
      height: 28px;
      margin-right: 7px;
    }

    &__section-title {
      display: flex;
      flex: none;
      align-items: center;
      justify-content: space-between;
      padding: 8px 12px 6px;
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
      display: flex;
      flex: 1 1 auto;
      flex-direction: column;
      min-height: 0;
      padding: 6px;
      overflow: hidden;

      :deep(.el-scrollbar) {
        flex: 1 1 auto;
        min-height: 0;
      }

      :deep(.el-tree) {
        background: transparent;
      }

      :deep(.el-tree-node__content) {
        height: 44px;
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
    }

    &__node-copy strong,
    &__node-copy small {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    &__node-copy strong {
      font-size: 12px;
      color: var(--el-text-color-primary);
    }

    &__node-copy small {
      font-size: 10px;
      color: var(--el-text-color-secondary);
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
      padding: 8px 10px 10px;
      background: var(--el-fill-color-lighter);
      border-top: 1px solid var(--el-border-color-lighter);
    }

    &__selection {
      gap: 9px;
      min-width: 0;
      padding: 6px 8px;
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
        color: var(--el-color-primary);
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
</style>
