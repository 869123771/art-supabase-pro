import { financeRouteNames } from '@/router/business-paths'
import { useArtFeedback } from '@/hooks/core/useArtFeedback'
import { fetchAccountingReadiness } from '@/api/fms'

interface FinanceAccountSetPrerequisiteOptions {
  actionLabel: string
  activeRequired?: boolean
  accountSetId?: string
  available: boolean
  foundationRequired?: boolean
  fundAccountRequired?: boolean
}

function isMessageBoxDismissed(error: unknown): boolean {
  return error === 'cancel' || error === 'close'
}

/**
 * Gives disabled-looking finance entry points an actionable next step while
 * preserving the database-enforced account-set lifecycle requirements.
 */
export function useFinanceAccountSetPrerequisite() {
  const router = useRouter()
  const { confirmAction } = useArtFeedback()

  async function confirmAndNavigate(
    message: string,
    title: string,
    confirmButtonText: string,
    routeName: string
  ): Promise<void> {
    try {
      await confirmAction(message, title, {
        type: 'info',
        confirmButtonText,
        cancelButtonText: '暂不处理'
      })
      await router.push({ name: routeName })
    } catch (error) {
      if (!isMessageBoxDismissed(error)) throw error
    }
  }

  async function ensureAccountSet({
    actionLabel,
    activeRequired = false,
    accountSetId,
    available,
    foundationRequired = false,
    fundAccountRequired = false
  }: FinanceAccountSetPrerequisiteOptions): Promise<boolean> {
    if (available) {
      if (!foundationRequired || !accountSetId) return true
      const { data } = await fetchAccountingReadiness(accountSetId)
      if (!data?.foundationReady) {
        await confirmAndNavigate(
          `“${actionLabel}”需要先补齐核心科目、自动制证规则和财务报表映射。初始化只新增缺失项，不覆盖已有配置。`,
          '核算基础尚未就绪',
          '前往会计科目',
          financeRouteNames.accountingSubject
        )
        return false
      }
      if (fundAccountRequired && !data?.fundAccountCount) {
        await confirmAndNavigate(
          `“${actionLabel}”需要至少一个已启用的资金账户。请先维护银行账户、现金账户或第三方支付账户。`,
          '需要配置资金账户',
          '前往资金账户',
          financeRouteNames.fundAccount
        )
        return false
      }
      return true
    }

    const stateText = activeRequired ? '已启用的账套' : '企业账套'
    const nextStepText = activeRequired
      ? '请前往账套管理完成创建并启用，再返回继续。'
      : '请前往账套管理完成创建，再返回继续。'
    await confirmAndNavigate(
      `“${actionLabel}”需要先配置${stateText}。${nextStepText}`,
      '需要完善财务基础配置',
      '前往账套管理',
      financeRouteNames.accountSet
    )
    return false
  }

  async function ensureLeafSubjects(available: boolean, actionLabel: string): Promise<boolean> {
    if (available) return true
    await confirmAndNavigate(
      `“${actionLabel}”需要至少一个末级会计科目。请先维护当前账套的科目体系。`,
      '需要完善会计科目',
      '前往会计科目',
      financeRouteNames.accountingSubject
    )
    return false
  }

  async function runWithAccountSet(
    options: FinanceAccountSetPrerequisiteOptions,
    action: () => void | Promise<void>
  ): Promise<boolean> {
    if (!(await ensureAccountSet(options))) return false
    await action()
    return true
  }

  function goToAccountSet(): void {
    void router.push({ name: financeRouteNames.accountSet })
  }

  return { ensureAccountSet, ensureLeafSubjects, goToAccountSet, runWithAccountSet }
}
