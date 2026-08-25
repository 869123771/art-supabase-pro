export interface PostLoginDataDependencies {
  loadDictionaries: () => Promise<void>
  loadUserProfile: () => Promise<boolean>
  onDictionaryError?: (error: unknown) => void
}

export interface PostLoginDataInitialization {
  dictionariesReady: Promise<void>
}

/**
 * 启动登录后的公共数据初始化。
 *
 * 用户资料决定是否允许进入系统，因此必须完成；字典是响应式辅助数据，
 * 可以与资料和动态菜单并行加载，不再阻塞同应用内的首屏跳转。
 */
export async function preparePostLoginData({
  loadDictionaries,
  loadUserProfile,
  onDictionaryError
}: PostLoginDataDependencies): Promise<PostLoginDataInitialization> {
  const dictionariesReady = loadDictionaries().catch((error: unknown) => {
    onDictionaryError?.(error)
  })
  const hasUserProfile = await loadUserProfile()

  if (!hasUserProfile) {
    throw new Error('当前账号缺少有效的业务用户资料')
  }

  return { dictionariesReady }
}
