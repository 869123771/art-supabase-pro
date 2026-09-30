import http from '@/utils/http'
import TreeUtils, { type TreeNode } from '@/utils/tree'

const regionTreeUtils = new TreeUtils({ childrenKey: 'children' })
const REGION_SOURCE_URL = `${import.meta.env.BASE_URL}data/pca-code.json`
let regionOptionsCache: RegionOption[] | null = null
let regionOptionsPromise: Promise<RegionOption[]> | null = null

export interface RegionOption extends TreeNode {
  name: string
  code?: string
  children?: RegionOption[]
}

export async function fetchRegionOptions(): Promise<RegionOption[]> {
  if (regionOptionsCache) return regionOptionsCache
  regionOptionsPromise ??= (async () => {
    try {
      const response = await http.get<unknown>({
        url: REGION_SOURCE_URL,
        skipAuth: true,
        skipResponseWrapper: true,
        showErrorMessage: false
      })
      regionOptionsCache = regionTreeUtils.normalizeTreeData<RegionOption>(response)
      return regionOptionsCache
    } catch (error) {
      throw new Error('行政区划数据加载失败，请稍后重试', { cause: error })
    } finally {
      regionOptionsPromise = null
    }
  })()
  return regionOptionsPromise
}
