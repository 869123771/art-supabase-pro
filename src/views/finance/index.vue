<template>
  <ArtPageShell class="finance-application-home">
    <section class="finance-application-home__hero">
      <span class="finance-application-home__eyebrow">INDEPENDENT APPLICATION</span>
      <h1>Finance 财务应用</h1>
      <p>
        独立代码仓、独立构建与独立部署入口已经就绪。当前业务页面仍为空，后续财务能力会通过明确的数据契约接入。
      </p>
      <ElTag effect="plain" type="success">应用基座已连接</ElTag>
    </section>

    <div class="finance-application-home__grid">
      <ArtPageSection title="统一身份" subtitle="Supabase Auth 与租户上下文由平台基座提供">
        <div class="finance-application-home__capability">
          <ArtSvgIcon icon="ri:shield-user-line" />
          <div><strong>租户安全</strong><span>所有查询均强制租户范围与 RLS</span></div>
        </div>
      </ArtPageSection>
      <ArtPageSection title="统一权限" subtitle="菜单和按钮权限继续由平台 RBAC 管理">
        <div class="finance-application-home__capability">
          <ArtSvgIcon icon="ri:key-2-line" />
          <div><strong>按角色授权</strong><span>普通租户仅能看到被分配的 Finance 菜单</span></div>
        </div>
      </ArtPageSection>
      <ArtPageSection title="契约集成" subtitle="跨模块数据只通过稳定 RPC / Read Model 读取">
        <div class="finance-application-home__capability">
          <ArtSvgIcon icon="ri:git-merge-line" />
          <div><strong>松耦合交互</strong><span>不引用其他业务仓的源码和数据表写入口</span></div>
        </div>
      </ArtPageSection>
    </div>
  </ArtPageShell>
</template>

<script setup lang="ts">
  defineOptions({ name: 'FinanceApplicationHome' })
</script>

<style scoped lang="scss">
  .finance-application-home {
    &__hero {
      padding: clamp(24px, 4vw, 48px);
      overflow: hidden;
      background:
        radial-gradient(circle at 92% 8%, rgb(99 102 241 / 18%), transparent 36%),
        var(--art-main-bg-color);
      border: 1px solid var(--art-card-border);
      border-radius: 14px;

      h1 {
        margin: 8px 0 10px;
        font-size: clamp(28px, 4vw, 42px);
        line-height: 1.2;
        color: var(--art-gray-900);
      }

      p {
        max-width: 720px;
        margin: 0 0 18px;
        line-height: 1.8;
        color: var(--art-gray-600);
      }
    }

    &__eyebrow {
      font-size: 12px;
      font-weight: 700;
      color: var(--main-color);
      letter-spacing: 0.14em;
    }

    &__grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 16px;
      margin-top: 16px;
    }

    &__capability {
      display: flex;
      gap: 12px;
      align-items: center;
      min-height: 72px;

      > svg {
        flex: 0 0 auto;
        width: 38px;
        height: 38px;
        padding: 9px;
        color: var(--main-color);
        background: color-mix(in srgb, var(--main-color) 10%, transparent);
        border-radius: 10px;
      }

      div {
        display: grid;
        gap: 5px;
        min-width: 0;
      }

      strong {
        font-size: 14px;
        color: var(--art-gray-800);
      }

      span {
        font-size: 12px;
        line-height: 1.5;
        color: var(--art-gray-500);
      }
    }
  }

  @media (width <= 960px) {
    .finance-application-home__grid {
      grid-template-columns: 1fr;
    }
  }
</style>
