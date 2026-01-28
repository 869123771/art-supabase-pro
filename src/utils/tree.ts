type ID = string | number

interface TreeNode {
  [key: string]: any
  // must include id and parent id fields but names are configurable
}

interface TreeUtilsOptions {
  idKey?: string
  parentKey?: string
  childrenKey?: string
  rootParentValues?: Array<any> // values considered "root", default [null, 0, '']
  deepClone?: boolean // default true for safety
}

export default class TreeUtils {
  idKey: string
  parentKey: string
  childrenKey: string
  rootParentValues: Array<any>
  deepClone: boolean

  constructor(opts: TreeUtilsOptions = {}) {
    this.idKey = opts.idKey ?? 'id'
    this.parentKey = opts.parentKey ?? 'parent_id'
    this.childrenKey = opts.childrenKey ?? 'children'
    this.rootParentValues = opts.rootParentValues ?? [null, 0, '']
    this.deepClone = opts.deepClone ?? true
  }

  // shallow or deep clone utility
  private clone<T>(obj: T): T {
    return this.deepClone ? JSON.parse(JSON.stringify(obj)) : Object.assign({}, obj)
  }

  // is value considered root parent
  private isRootParent(value: any) {
    return this.rootParentValues.includes(value) || value === undefined
  }

  /**
   * listToTree
   * Convert flat list -> tree (O(n))
   * - items: array of objects containing id & parent_id
   * - sortFn: optional sort function for children arrays
   * Returns array of root nodes (with children arrays)
   */
  listToTree(items: TreeNode[], sortFn?: (a: TreeNode, b: TreeNode) => number): TreeNode[] {
    if (!Array.isArray(items)) return []

    const map = new Map<ID, TreeNode>()
    const roots: TreeNode[] = []

    // 1) build map with cloned nodes and init children
    for (const raw of items) {
      const node = this.clone(raw)
      node[this.childrenKey] = node[this.childrenKey] ?? []
      map.set(node[this.idKey], node)
    }

    // 2) assemble
    for (const node of map.values()) {
      const parentId = node[this.parentKey]
      if (this.isRootParent(parentId) || !map.has(parentId)) {
        // treat as root when parent is rootValue or parent not in list
        roots.push(node)
      } else {
        const parent = map.get(parentId)!
        parent[this.childrenKey] = parent[this.childrenKey] ?? []
        parent[this.childrenKey].push(node)
      }
    }

    // 3) sort if sortFn provided
    if (sortFn) {
      const sortRecursively = (nodes: TreeNode[]) => {
        // Sort current level
        nodes.sort(sortFn)

        // Sort children recursively
        for (const node of nodes) {
          const children = node[this.childrenKey]
          if (Array.isArray(children) && children.length > 0) {
            sortRecursively(children)
          }
        }
      }

      sortRecursively(roots)
    }

    return roots
  }

  /**
   * treeToList
   * Flatten tree -> list (preorder)
   * - preserve parent relationship
   * - optionally include depth and parentChain
   */
  treeToList(
    tree: TreeNode[],
    opts?: { includeDepth?: boolean; includeParentChain?: boolean }
  ): TreeNode[] {
    const result: TreeNode[] = []
    const includeDepth = opts?.includeDepth ?? false
    const includeParentChain = opts?.includeParentChain ?? false

    const walk = (nodes: TreeNode[], depth = 0, parentChain: ID[] = []) => {
      for (const raw of nodes) {
        const node = this.clone(raw)
        // remove children when flattening (to avoid circular large objects)
        const children = node[this.childrenKey] ?? []
        delete node[this.childrenKey]

        if (includeDepth) node.__depth = depth
        if (includeParentChain) node.__parentChain = [...parentChain]

        result.push(node)

        if (Array.isArray(children) && children.length) {
          walk(children, depth + 1, [...parentChain, node[this.idKey]])
        }
      }
    }

    walk(tree, 0, [])
    return result
  }

  /**
   * findNode
   * Find node by id in tree (DFS)
   * Returns the node reference from the cloned tree (not original)
   */
  findNode(tree: TreeNode[], id: ID): TreeNode | null {
    const stack = [...tree]
    while (stack.length) {
      const node = stack.pop()!
      if (node[this.idKey] === id) return node
      const children = node[this.childrenKey]
      if (children && children.length) stack.push(...children)
    }
    return null
  }

  /**
   * updateNode
   * Update a node by id with partial data.
   * - returns updated tree (cloned) and updated node reference
   */
  updateNode(
    tree: TreeNode[],
    id: ID,
    patch: Partial<TreeNode>
  ): { tree: TreeNode[]; updatedNode: TreeNode | null } {
    const t = this.clone(tree) as TreeNode[]
    const target = this.findNode(t, id)
    if (!target) return { tree: t, updatedNode: null }
    Object.assign(target, patch)
    return { tree: t, updatedNode: target }
  }

  /**
   * addNode
   * Add a new node (object must include id; parent may be rootParentValue)
   * - if parent not found and not root, will push to roots
   * - returns new tree (cloned)
   */
  addNode(tree: TreeNode[], node: TreeNode): TreeNode[] {
    const t = this.clone(tree) as TreeNode[]
    const newNode = this.clone(node)
    newNode[this.childrenKey] = newNode[this.childrenKey] ?? []

    // try to find parent
    const parentId = newNode[this.parentKey]
    if (this.isRootParent(parentId)) {
      t.push(newNode)
      return t
    }
    const parent = this.findNode(t, parentId)
    if (parent) {
      parent[this.childrenKey] = parent[this.childrenKey] ?? []
      parent[this.childrenKey].push(newNode)
    } else {
      // if parent not found, treat as root
      t.push(newNode)
    }
    return t
  }

  /**
   * removeNode
   * Remove node by id. Returns new tree and removed node (or null).
   * - This will remove the node and its entire subtree.
   */
  removeNode(tree: TreeNode[], id: ID): { tree: TreeNode[]; removed: TreeNode | null } {
    const t = this.clone(tree) as TreeNode[]
    let removed: TreeNode | null = null

    const walk = (nodes: TreeNode[]) => {
      for (let i = nodes.length - 1; i >= 0; i--) {
        const node = nodes[i]
        if (node[this.idKey] === id) {
          removed = nodes.splice(i, 1)[0]
          return true
        }
        const children = node[this.childrenKey]
        if (children && children.length) {
          const found = walk(children)
          if (found) return true
        }
      }
      return false
    }

    walk(t)
    return { tree: t, removed }
  }

  /**
   * mapTree
   * Map each node to new value (like Array.map) while preserving structure.
   */
  mapTree(tree: TreeNode[], mapper: (node: TreeNode) => TreeNode): TreeNode[] {
    const mapNode = (node: TreeNode): TreeNode => {
      const mapped = mapper(this.clone(node))
      const children = node[this.childrenKey] ?? []
      mapped[this.childrenKey] = children && children.length ? children.map(mapNode) : []
      return mapped
    }
    return tree.map(mapNode)
  }

  /**
   * traverse (preorder)
   * Execute callback on each node. If callback returns false, halt traversal.
   */
  traverse(
    tree: TreeNode[],
    callback: (node: TreeNode, depth: number, parentChain: ID[]) => boolean | void
  ) {
    const walk = (nodes: TreeNode[], depth = 0, parentChain: ID[] = []) => {
      for (const node of nodes) {
        const stop = callback(node, depth, parentChain)
        if (stop === false) return false
        const children = node[this.childrenKey] ?? []
        if (children && children.length) {
          const res = walk(children, depth + 1, [...parentChain, node[this.idKey]])
          if (res === false) return false
        }
      }
      return true
    }
    return walk(tree, 0, [])
  }

  /**
   * sortTree
   * Sort nodes in-place by compareFn; applies recursively to children.
   * - compareFn same as Array.prototype.sort
   * - returns sorted tree (cloned if deepClone true)
   */
  sortTree(tree: TreeNode[], compareFn: (a: TreeNode, b: TreeNode) => number): TreeNode[] {
    const t = this.clone(tree) as TreeNode[]
    const sortRec = (nodes: TreeNode[]) => {
      nodes.sort(compareFn)
      for (const n of nodes) {
        if (n[this.childrenKey] && n[this.childrenKey].length) sortRec(n[this.childrenKey])
      }
    }
    sortRec(t)
    return t
  }

  /**
   * detectCycle
   * Detect cycles in flat list representation (useful before building tree)
   * Returns { hasCycle: boolean, cycles: Array<Array<ID>> }
   */
  detectCycle(items: TreeNode[]): { hasCycle: boolean; cycles: ID[][] } {
    // Build adjacency map id -> parentId
    const parentMap = new Map<ID, ID | null>()
    for (const it of items) parentMap.set(it[this.idKey], it[this.parentKey] ?? null)

    const visited = new Set<ID>()
    const stack = new Set<ID>()
    const cycles: ID[][] = []

    const visit = (nodeId: ID) => {
      if (!parentMap.has(nodeId)) return false
      if (stack.has(nodeId)) {
        // found a cycle -- reconstruct cycle
        const cycle = Array.from(stack).slice(Array.from(stack).indexOf(nodeId))
        cycles.push(cycle)
        return true
      }
      if (visited.has(nodeId)) return false

      visited.add(nodeId)
      stack.add(nodeId)
      const parent = parentMap.get(nodeId)
      if (parent !== null && parent !== undefined && parentMap.has(parent)) {
        visit(parent)
      }
      stack.delete(nodeId)
      return false
    }

    for (const id of parentMap.keys()) visit(id)

    return { hasCycle: cycles.length > 0, cycles }
  }

  /**
   * getPathToNode
   * Return array of nodes ids from root -> target (inclusive).
   * - Build using tree (not flat list)
   */
  getPathToNode(tree: TreeNode[], targetId: ID): ID[] | null {
    const path: ID[] = []
    const found = (nodes: TreeNode[]): boolean => {
      for (const n of nodes) {
        path.push(n[this.idKey])
        if (n[this.idKey] === targetId) return true
        const children = n[this.childrenKey] ?? []
        if (children && children.length) {
          if (found(children)) return true
        }
        path.pop()
      }
      return false
    }
    const ok = found(tree)
    return ok ? path : null
  }

  /**
   * getDescendants
   * Return flat list of descendants for given node id (including node if includeSelf)
   */
  getDescendants(tree: TreeNode[], id: ID, includeSelf = false): TreeNode[] {
    const node = this.findNode(tree, id)
    if (!node) return []
    const res: TreeNode[] = []
    const walk = (n: TreeNode) => {
      res.push(this.clone(n))
      const children = n[this.childrenKey] ?? []
      if (children && children.length) for (const c of children) walk(c)
    }
    if (includeSelf) walk(node)
    else {
      const children = node[this.childrenKey] ?? []
      for (const c of children) walk(c)
    }
    return res
  }

  /**
   * getAncestors
   * Requires the flattened list (or original items) to reconstruct ancestors
   * If you only have tree, you can use getPathToNode then lookup nodes by id.
   */
  getAncestors(tree: TreeNode[], targetId: ID): TreeNode[] {
    const path = this.getPathToNode(tree, targetId)
    if (!path) return []
    const res: TreeNode[] = []
    for (const id of path) {
      const n = this.findNode(tree, id)
      if (n) res.push(this.clone(n))
    }
    return res
  }

  /**
   * mergeTrees (merge node lists into a single tree)
   * - items can be mixed; result is tree roots array
   */
  mergeListToTree(...lists: TreeNode[][]): TreeNode[] {
    const merged = ([] as TreeNode[]).concat(...lists)
    return this.listToTree(merged)
  }

  /**
   * sortTreeByField
   * 对树按照指定字段进行排序，支持多层嵌套排序
   * - field: 排序字段名，支持点号表示法如 'meta.title'
   * - order: 排序顺序，'asc' 升序，'desc' 降序
   * - sortFn: 自定义排序函数，优先级高于 field 和 order
   */
  sortTreeByField(
    tree: TreeNode[],
    field: string,
    order: 'asc' | 'desc' = 'asc',
    sortFn?: (a: TreeNode, b: TreeNode) => number
  ): TreeNode[] {
    const t = this.clone(tree) as TreeNode[]

    // 获取嵌套字段的值
    const getFieldValue = (node: TreeNode, fieldPath: string): any => {
      const parts = fieldPath.split('.')
      let value: any = node

      for (const part of parts) {
        if (value && typeof value === 'object' && part in value) {
          value = value[part]
        } else {
          return undefined
        }
      }

      return value
    }

    // 默认排序函数
    const defaultSortFn = (a: TreeNode, b: TreeNode): number => {
      const aValue = getFieldValue(a, field)
      const bValue = getFieldValue(b, field)

      // 处理 undefined 和 null
      if (aValue === undefined || aValue === null) return 1
      if (bValue === undefined || bValue === null) return -1

      // 根据类型比较
      if (typeof aValue === 'number' && typeof bValue === 'number') {
        return order === 'asc' ? aValue - bValue : bValue - aValue
      }

      // 字符串比较
      const aStr = String(aValue)
      const bStr = String(bValue)
      return order === 'asc' ? aStr.localeCompare(bStr) : bStr.localeCompare(aStr)
    }

    // 使用提供的排序函数或默认排序函数
    const compareFn = sortFn || defaultSortFn

    // 递归排序
    const sortRecursively = (nodes: TreeNode[]) => {
      nodes.sort(compareFn)
      for (const node of nodes) {
        const children = node[this.childrenKey]
        if (Array.isArray(children) && children.length > 0) {
          sortRecursively(children)
        }
      }
    }

    sortRecursively(t)
    return t
  }

  /**
   * removeNodesByCondition
   * 根据条件函数删除节点
   * - condition: 条件函数，返回 true 的节点将被删除（包括其子节点）
   * - 返回新树和删除的节点数组
   */
  removeNodesByCondition(
    tree: TreeNode[],
    condition: (node: TreeNode) => boolean
  ): { tree: TreeNode[]; removed: TreeNode[] } {
    const t = this.clone(tree) as TreeNode[]
    const removed: TreeNode[] = []

    const removeRecursively = (nodes: TreeNode[]): TreeNode[] => {
      const result: TreeNode[] = []

      for (const node of nodes) {
        // 检查当前节点是否满足删除条件
        if (condition(node)) {
          removed.push(this.clone(node))
          // 跳过当前节点及其子节点（不添加到结果中）
          continue
        }

        // 保留当前节点
        const newNode = { ...node }

        // 递归处理子节点
        const children = node[this.childrenKey]
        if (Array.isArray(children) && children.length > 0) {
          newNode[this.childrenKey] = removeRecursively(children)
        }

        result.push(newNode)
      }

      return result
    }

    const filteredTree = removeRecursively(t)
    return { tree: filteredTree, removed }
  }
}

/*
// 假设 items 来自后端
const items = [
  { id: 1, parent_id: null, name: 'root1' },
  { id: 2, parent_id: 1, name: 'child1' },
  { id: 3, parent_id: 1, name: 'child2' },
  { id: 4, parent_id: 2, name: 'grandchild' },
];

const utils = new TreeUtils({ idKey: 'id', parentKey: 'parent_id', childrenKey: 'children', deepClone: true });

// list -> tree
const tree = utils.listToTree(items);

// flatten with depth
const flat = utils.treeToList(tree, { includeDepth: true, includeParentChain: true });

// find
const node = utils.findNode(tree, 2);

// update
const { tree: updatedTree } = utils.updateNode(tree, 2, { name: 'child1-updated' });

// add node
const newTree = utils.addNode(tree, { id: 5, parent_id: 1, name: 'child3' });

// remove node
const { tree: afterRemove, removed } = utils.removeNode(tree, 4);

// detect cycles
const cycleInfo = utils.detectCycle(items);

// get path
const path = utils.getPathToNode(tree, 4); // [1,2,4]

// get descendants
const descendants = utils.getDescendants(tree, 1, false);

// merge lists
const mergedTree = utils.mergeListToTree(items, moreItems)

// 按嵌套字段排序（如 meta.title）
const sortedTree3 = utils.sortTreeByField(tree, 'meta.title', 'asc')

// 也可以删除多个条件的节点
const { tree: filteredTree2 } = utils.removeNodesByCondition(
  tree,
  (node) => node.meta?.menuType === 'button' || node.hidden === true
)
*/
