<template>
  <ArtDialog ref="dialogRef" size="xl">
    <div class="workflow-catalog">
      <section class="workflow-catalog__summary">
        <div>
          <span><ArtSvgIcon icon="ri:apps-2-line" /></span>
          <div>
            <strong>{{ workflowBusinessContracts.length }} 类核心业务已接入统一审批</strong>
            <p>每类业务均使用服务端真实数据做条件判断，并在审批时提供业务决策快照。</p>
          </div>
        </div>
        <ElTag class="workflow-catalog__coverage" type="success" effect="plain" round>
          <ArtSvgIcon icon="ri:shield-check-line" />
          核心范围 {{ workflowBusinessContracts.length }} / {{ workflowBusinessContracts.length }}
        </ElTag>
      </section>

      <section class="workflow-catalog__grid" aria-label="审批业务覆盖矩阵">
        <article v-for="contract in workflowBusinessContracts" :key="contract.businessType">
          <header>
            <span><ArtSvgIcon :icon="domainIcon(contract.domain)" /></span>
            <div>
              <strong>{{ contract.label }}</strong>
              <small>{{ contract.businessType }}</small>
            </div>
            <ElTag
              class="workflow-catalog__risk"
              :type="contract.riskLevel === 'high' ? 'danger' : 'warning'"
              effect="plain"
              size="small"
              round
            >
              <ArtSvgIcon
                :icon="
                  contract.riskLevel === 'high' ? 'ri:alarm-warning-line' : 'ri:error-warning-line'
                "
              />
              {{ contract.riskLevel === 'high' ? '高风险' : '中风险' }}
            </ElTag>
          </header>
          <dl>
            <div
              ><dt>业务归口</dt><dd>{{ contract.owner }}</dd></div
            >
            <div
              ><dt>条件字段</dt><dd>{{ contract.fields.length }} 个</dd></div
            >
            <div
              ><dt>可信上下文</dt
              ><dd><ArtSvgIcon icon="ri:checkbox-circle-fill" />服务端生成</dd></div
            >
            <div
              ><dt>状态防绕过</dt
              ><dd><ArtSvgIcon icon="ri:checkbox-circle-fill" />数据库守卫</dd></div
            >
          </dl>
          <footer>
            <small>决策字段</small>
            <div>
              <span v-for="field in contract.fields.slice(0, 4)" :key="field.key">
                {{ field.label }}
              </span>
              <span v-if="contract.fields.length > 4" class="is-more">
                +{{ contract.fields.length - 4 }}
              </span>
            </div>
          </footer>
        </article>
      </section>

      <section class="workflow-catalog__boundary art-card-xs">
        <span><ArtSvgIcon icon="ri:flow-chart" /></span>
        <div>
          <strong>当前流程图采用“企业审批流”模型</strong>
          <p>
            已覆盖顺序节点、条件跳过、或签、全员会签、比例会签、否决策略、SLA、委托和转交。
            只有出现并行网关、子流程、补偿事件或跨系统长事务时，才需要升级为完整 BPMN 引擎。
          </p>
        </div>
      </section>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { workflowBusinessContracts } from '../../modules/workflow-business-contracts'

  defineOptions({ name: 'WorkflowBusinessCatalogDialog' })

  const dialogRef = ref<ArtDialogExpose>()

  function domainIcon(domain: 'transport' | 'finance' | 'master_data'): string {
    return {
      transport: 'ri:truck-line',
      finance: 'ri:money-cny-circle-line',
      master_data: 'ri:database-2-line'
    }[domain]
  }

  async function handleOpen(): Promise<void> {
    await dialogRef.value?.handleOpen(undefined, {
      title: '审批业务覆盖与风险矩阵',
      subtitle: '用于确认哪些业务必须走审批、由谁负责、以哪些可信字段作出决策。',
      contentMaxHeight: '78vh',
      showFooter: false
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .workflow-catalog {
    display: grid;
    gap: 16px;
    min-width: 0;

    &__summary,
    &__summary > div {
      display: flex;
      gap: 14px;
      align-items: center;
    }

    &__summary {
      justify-content: space-between;
      min-width: 0;
      padding: 16px 18px;
      background: linear-gradient(
        135deg,
        var(--el-color-success-light-9),
        var(--default-box-color)
      );
      border: 1px solid var(--el-color-success-light-7);
      border-radius: var(--el-border-radius-base);

      > div > span {
        display: grid;
        flex: 0 0 auto;
        place-items: center;
        width: 42px;
        height: 42px;
        font-size: 20px;
        color: var(--el-color-success);
        background: var(--default-box-color);
        border-radius: 50%;
      }

      > div > div {
        display: grid;
        gap: 4px;
        min-width: 0;
      }

      strong {
        font-size: 15px;
        color: var(--art-gray-900);
      }

      p {
        margin: 0;
        font-size: 12px;
        line-height: 1.55;
        color: var(--art-gray-600);
      }
    }

    &__coverage,
    &__risk {
      flex: 0 0 auto;

      :deep(.el-tag__content) {
        display: inline-flex;
        gap: 5px;
        align-items: center;
        white-space: nowrap;
      }

      svg {
        font-size: 13px;
      }
    }

    &__grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
    }

    &__grid article {
      display: flex;
      flex-direction: column;
      gap: 11px;
      min-width: 0;
      min-height: 214px;
      padding: 15px;
      background: var(--default-box-color);
      border: 1px solid var(--art-gray-200);
      border-radius: var(--el-border-radius-base);
    }

    &__grid header {
      display: grid;
      grid-template-columns: 38px minmax(0, 1fr) auto;
      gap: 11px;
      align-items: center;

      > span {
        display: grid;
        place-items: center;
        width: 38px;
        height: 38px;
        color: var(--theme-color);
        background: color-mix(in srgb, var(--theme-color) 10%, var(--el-bg-color));
        border-radius: var(--el-border-radius-base);
      }

      > div {
        display: grid;
        gap: 2px;
        min-width: 0;
      }

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        font-size: 14px;
        color: var(--art-gray-900);
      }

      small {
        font-size: 11px;
        color: var(--art-gray-500);
      }
    }

    &__risk {
      justify-self: end;
      min-width: 68px;
      max-width: 100%;
    }

    &__grid dl {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 6px;
      margin: 0;

      > div {
        display: grid;
        gap: 3px;
        min-width: 0;
        padding: 7px 9px;
        background: color-mix(in srgb, var(--art-gray-50) 78%, transparent);
        border: 1px solid color-mix(in srgb, var(--art-gray-200) 70%, transparent);
        border-radius: var(--el-border-radius-small);
      }

      dt {
        font-size: 11px;
        color: var(--art-gray-500);
      }

      dd {
        display: flex;
        gap: 4px;
        align-items: center;
        min-width: 0;
        margin: 0;
        font-size: 12px;
        font-weight: 600;
        color: var(--art-gray-800);
        overflow-wrap: anywhere;
      }

      svg {
        color: var(--el-color-success);
      }
    }

    &__grid footer {
      display: grid;
      gap: 6px;
      margin-top: auto;

      > small {
        font-size: 11px;
        color: var(--art-gray-500);
      }

      > div {
        display: flex;
        flex-wrap: wrap;
        gap: 5px;
        min-width: 0;
      }

      span {
        max-width: 100%;
        padding: 3px 8px;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 11px;
        color: var(--art-gray-600);
        white-space: nowrap;
        background: var(--art-gray-50);
        border: 1px solid var(--art-gray-200);
        border-radius: 999px;

        &.is-more {
          flex: 0 0 auto;
          font-weight: 600;
          color: var(--theme-color);
          background: color-mix(in srgb, var(--theme-color) 8%, var(--el-bg-color));
          border-color: color-mix(in srgb, var(--theme-color) 22%, var(--el-border-color));
        }
      }
    }

    &__boundary {
      display: flex;
      gap: 12px;
      align-items: flex-start;
      padding: 14px;

      > span {
        display: grid;
        flex: 0 0 auto;
        place-items: center;
        width: 34px;
        height: 34px;
        color: var(--el-color-warning);
        background: var(--el-color-warning-light-9);
        border-radius: 50%;
      }

      > div {
        display: grid;
        gap: 4px;
        min-width: 0;
      }

      strong {
        color: var(--art-gray-900);
      }

      p {
        margin: 0;
        font-size: 12px;
        line-height: 1.65;
        color: var(--art-gray-600);
      }
    }
  }

  @media only screen and (width <= 1080px) {
    .workflow-catalog {
      &__grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }
  }

  @media only screen and (width <= 680px) {
    .workflow-catalog {
      &__grid {
        grid-template-columns: 1fr;
      }

      &__summary {
        flex-direction: column;
        align-items: flex-start;

        > div {
          align-items: flex-start;
        }
      }
    }
  }
</style>
