<template>
  <div class="platform-workbench art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="PLATFORM WORKSPACE"
      :title="`${greeting}，${userName}`"
      description="从统一工作台进入已授权的业务应用；账号、菜单、角色与数据权限由平台基座集中管理。"
      icon="ri:apps-2-ai-line"
      :tags="workspaceTags"
      :metrics="workspaceMetrics"
    />

    <section class="platform-workbench__section" aria-labelledby="application-heading">
      <header class="platform-workbench__section-header">
        <div>
          <span>APPLICATIONS</span>
          <h2 id="application-heading">我的应用</h2>
          <p>这里只展示当前租户和角色已获得菜单权限的应用。</p>
        </div>
      </header>

      <div v-if="applications.length" class="platform-workbench__application-grid">
        <button
          v-for="application in applications"
          :key="application.name"
          type="button"
          class="platform-workbench__application-card art-card-xs"
          @click="openApplication(application)"
        >
          <span class="platform-workbench__application-icon" aria-hidden="true">
            <ArtSvgIcon :icon="application.meta.icon || 'ri:apps-line'" />
          </span>
          <span class="platform-workbench__application-copy">
            <strong>{{ application.meta.title }}</strong>
            <small>{{ pageCount(application) }} 个可访问页面</small>
          </span>
          <ArtSvgIcon icon="ri:arrow-right-line" class="platform-workbench__application-arrow" />
        </button>
      </div>

      <ElEmpty v-else description="当前账号还没有可访问的业务应用，请联系管理员分配角色菜单。" />
    </section>

    <section class="platform-workbench__support-grid" aria-label="平台能力">
      <article class="platform-workbench__support-card art-card-xs">
        <span class="platform-workbench__support-icon is-primary">
          <ArtSvgIcon icon="ri:shield-user-line" />
        </span>
        <div>
          <h3>统一身份与权限</h3>
          <p>所有子应用复用平台登录、租户、用户、角色与按钮权限，无需重复维护认证代码。</p>
        </div>
      </article>
      <article class="platform-workbench__support-card art-card-xs">
        <span class="platform-workbench__support-icon is-success">
          <ArtSvgIcon icon="ri:database-2-line" />
        </span>
        <div>
          <h3>数据中心</h3>
          <p>字典、组织和跨模块数据通过稳定的公共契约共享，业务仓之间不直接复制实现。</p>
        </div>
      </article>
      <article class="platform-workbench__support-card art-card-xs">
        <span class="platform-workbench__support-icon is-warning">
          <ArtSvgIcon icon="ri:cloud-line" />
        </span>
        <div>
          <h3>独立运行与部署</h3>
          <p>每个应用拥有独立入口和构建产物，同时可由平台租户在主工程中统一访问。</p>
        </div>
      </article>
    </section>
  </div>
</template>

<script setup lang="ts">
  import { storeToRefs } from 'pinia'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric,
    type BusinessWorkspaceTag
  } from '@/components/business/business-workspace-header/index.vue'
  import { useMenuStore } from '@/store/modules/menu'
  import { useUserStore } from '@/store/modules/user'
  import type { AppRouteRecord } from '@/types/router'

  defineOptions({ name: 'Console' })

  const router = useRouter()
  const { menuList, buttonList } = storeToRefs(useMenuStore())
  const { info, language, isPlatformSuper } = storeToRefs(useUserStore())

  const flattenMenus = (items: AppRouteRecord[]): AppRouteRecord[] =>
    items.flatMap((item) => [item, ...flattenMenus(item.children ?? [])])

  const isApplication = (item: AppRouteRecord): boolean =>
    item.type === 'folder' &&
    item.path !== '/dashboard' &&
    (item.children ?? []).some((child) =>
      flattenMenus([child]).some((entry) => entry.type === 'menu')
    )

  const applications = computed(() => menuList.value.filter(isApplication))
  const allVisiblePages = computed(() =>
    flattenMenus(menuList.value).filter((item) => item.type === 'menu' && !item.meta.isHide)
  )
  const locale = computed(() =>
    String(language.value).toLowerCase().startsWith('en') ? 'en-US' : 'zh-CN'
  )
  const greeting = computed(() => {
    const hour = new Date().getHours()
    return hour < 12 ? '早上好' : hour < 18 ? '下午好' : '晚上好'
  })
  const userName = computed(() => {
    const candidates = [info.value?.nickName, info.value?.userName, info.value?.email]
    return candidates.find((value) => String(value ?? '').trim())?.trim() || '用户'
  })
  const dateText = computed(() =>
    new Intl.DateTimeFormat(locale.value, {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      weekday: 'long'
    }).format(new Date())
  )
  const workspaceTags = computed<BusinessWorkspaceTag[]>(() => [
    { label: dateText.value, type: 'info', effect: 'plain' },
    {
      label: isPlatformSuper.value ? '平台管理员' : '租户授权用户',
      type: isPlatformSuper.value ? 'primary' : 'success',
      effect: 'plain'
    }
  ])
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '已授权应用',
      value: applications.value.length,
      description: '当前账号可进入的业务模块',
      icon: 'ri:apps-line'
    },
    {
      label: '可访问页面',
      value: allVisiblePages.value.length,
      description: '由角色菜单动态授权',
      icon: 'ri:layout-grid-line',
      tone: 'success'
    },
    {
      label: '操作权限',
      value: buttonList.value.length,
      description: '按钮与业务动作权限',
      icon: 'ri:key-2-line',
      tone: 'warning'
    }
  ])

  const pageCount = (application: AppRouteRecord): number =>
    flattenMenus(application.children ?? []).filter(
      (item) => item.type === 'menu' && !item.meta.isHide
    ).length

  const firstPage = (application: AppRouteRecord): AppRouteRecord | undefined =>
    flattenMenus(application.children ?? []).find(
      (item) => item.type === 'menu' && !item.meta.isHide
    )

  const openApplication = (application: AppRouteRecord): void => {
    const target = firstPage(application)
    if (target?.name) void router.push({ name: target.name })
  }
</script>

<style scoped lang="scss">
  .platform-workbench {
    gap: var(--art-space-3);
    min-width: 0;
    padding-bottom: var(--art-space-6);

    &__section {
      padding: clamp(18px, 2vw, 24px);
      background: var(--art-main-bg-color);
      border: 1px solid var(--art-card-border);
      border-radius: calc(var(--custom-radius) + 4px);
    }

    &__section-header {
      margin-bottom: 18px;

      span {
        font-size: 11px;
        font-weight: 700;
        color: var(--el-color-primary);
        letter-spacing: 0.13em;
      }

      h2 {
        margin: 4px 0;
        font-size: 20px;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 0;
        font-size: 13px;
        color: var(--art-text-gray-500);
      }
    }

    &__application-grid,
    &__support-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
    }

    &__application-card {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) auto;
      gap: 14px;
      align-items: center;
      min-width: 0;
      padding: 18px;
      color: inherit;
      text-align: left;
      cursor: pointer;
      background: color-mix(in srgb, var(--el-color-primary) 3%, var(--art-main-bg-color));
      border: 1px solid color-mix(in srgb, var(--el-color-primary) 10%, var(--art-card-border));
      transition:
        transform 160ms ease,
        border-color 160ms ease,
        box-shadow 160ms ease;

      &:hover,
      &:focus-visible {
        border-color: color-mix(in srgb, var(--el-color-primary) 42%, transparent);
        box-shadow: 0 12px 28px rgb(31 39 82 / 8%);
        transform: translateY(-2px);
      }

      &:focus-visible {
        outline: 2px solid var(--el-color-primary);
        outline-offset: 2px;
      }
    }

    &__application-icon,
    &__support-icon {
      display: grid;
      flex: 0 0 auto;
      place-items: center;
      width: 44px;
      height: 44px;
      font-size: 22px;
      color: var(--el-color-primary);
      background: color-mix(in srgb, var(--el-color-primary) 12%, transparent);
      border-radius: 14px;
    }

    &__application-copy {
      display: grid;
      gap: 5px;
      min-width: 0;

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        font-size: 15px;
        color: var(--art-text-gray-900);
      }

      small {
        font-size: 12px;
        color: var(--art-text-gray-500);
      }
    }

    &__application-arrow {
      font-size: 18px;
      color: var(--art-text-gray-400);
    }

    &__support-card {
      display: flex;
      gap: 14px;
      align-items: flex-start;
      padding: 18px;

      h3 {
        margin: 2px 0 7px;
        font-size: 15px;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 0;
        font-size: 13px;
        line-height: 1.65;
        color: var(--art-text-gray-500);
      }
    }

    &__support-icon.is-success {
      color: var(--el-color-success);
      background: color-mix(in srgb, var(--el-color-success) 12%, transparent);
    }

    &__support-icon.is-warning {
      color: var(--el-color-warning);
      background: color-mix(in srgb, var(--el-color-warning) 12%, transparent);
    }

    @media screen and (width <= 1100px) {
      &__application-grid,
      &__support-grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }

    @media screen and (width <= 720px) {
      &__application-grid,
      &__support-grid {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
