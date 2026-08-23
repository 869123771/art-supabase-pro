<template>
  <ElDropdown
    v-if="switcherEntries.length > 1"
    trigger="click"
    placement="bottom-end"
    @command="switchApplication"
  >
    <button class="application-switcher" type="button" aria-label="切换业务应用">
      <ArtSvgIcon icon="ri:apps-2-line" />
      <span>{{ currentApplication.code.toUpperCase() }}</span>
      <ArtSvgIcon class="application-switcher__arrow" icon="ri:arrow-down-s-line" />
    </button>

    <template #dropdown>
      <ElDropdownMenu class="application-switcher__menu">
        <ElDropdownItem
          v-for="application in switcherEntries"
          :key="application.code"
          :command="application.code"
          :disabled="application.code === currentApplication.code"
        >
          <span class="application-switcher__item-icon">
            <ArtSvgIcon :icon="iconByApplication[application.code] ?? 'ri:apps-line'" />
          </span>
          <span class="application-switcher__item-copy">
            <strong>{{ application.name }}</strong>
            <small>{{ application.description || '独立业务应用' }}</small>
          </span>
          <ArtSvgIcon
            v-if="application.code === currentApplication.code"
            icon="ri:check-line"
            class="application-switcher__check"
          />
        </ElDropdownItem>
      </ElDropdownMenu>
    </template>
  </ElDropdown>
</template>

<script setup lang="ts">
  import { fetchAccessibleApplications, type AccessibleApplication } from '@/api/system-manage'
  import {
    currentApplication,
    resolveApplicationBaseUrl,
    type ApplicationCode
  } from '@/config/application'
  import { WEB_LINKS } from '@/utils/constants'

  defineOptions({ name: 'ArtApplicationSwitcher' })

  type SwitcherEntryCode = ApplicationCode | 'docs'

  interface SwitcherEntry {
    code: SwitcherEntryCode
    name: string
    description: string | null
    baseUrl: string
  }

  const applications = ref<AccessibleApplication[]>([])
  const documentationEntry: SwitcherEntry = {
    code: 'docs',
    name: 'Art Supabase DOC',
    description: '官方文档、使用指南与技术支持',
    baseUrl: WEB_LINKS.DOCS
  }
  const switcherEntries = computed<SwitcherEntry[]>(() => [
    ...(applications.value.length
      ? applications.value
      : [
          {
            code: currentApplication.code,
            name: currentApplication.name,
            description: currentApplication.description,
            baseUrl: window.location.href
          }
        ]),
    documentationEntry
  ])

  const iconByApplication: Record<SwitcherEntryCode, string> = {
    platform: 'ri:building-4-line',
    fms: 'ri:bank-card-line',
    hr: 'ri:team-line',
    smis: 'ri:shield-check-line',
    tms: 'ri:apps-2-line',
    vms: 'ri:truck-line',
    docs: 'ri:book-open-line'
  }

  onMounted(async () => {
    const { data, error } = await fetchAccessibleApplications()
    if (!error) applications.value = data ?? []
  })

  function switchApplication(code: SwitcherEntryCode): void {
    if (code === 'docs') {
      window.open(WEB_LINKS.DOCS, '_blank', 'noopener,noreferrer')
      return
    }

    if (code === currentApplication.code) return

    const target = applications.value.find((application) => application.code === code)
    if (!target?.baseUrl) return

    const targetUrl = resolveApplicationBaseUrl(code, target.baseUrl, window.location)
    window.location.assign(targetUrl.toString())
  }
</script>

<style scoped lang="scss">
  .application-switcher {
    display: inline-flex;
    gap: 6px;
    align-items: center;
    min-height: 36px;
    padding: 0 10px;
    margin-right: 8px;
    color: var(--art-gray-700);
    cursor: pointer;
    background: var(--art-main-bg-color);
    border: 1px solid var(--art-card-border);
    border-radius: 8px;
    transition:
      border-color 0.2s ease,
      color 0.2s ease;

    &:hover,
    &:focus-visible {
      color: var(--main-color);
      outline: none;
      border-color: color-mix(in srgb, var(--main-color) 45%, transparent);
    }

    &__arrow {
      color: var(--art-gray-500);
    }
  }

  .application-switcher__menu {
    width: min(360px, calc(100vw - 24px));

    :deep(.el-dropdown-menu__item) {
      display: grid;
      grid-template-columns: 34px minmax(0, 1fr) 20px;
      gap: 10px;
      align-items: center;
      min-height: 60px;
    }
  }

  .application-switcher__item-icon {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    color: var(--main-color);
    background: color-mix(in srgb, var(--main-color) 10%, transparent);
    border-radius: 8px;
  }

  .application-switcher__item-copy {
    display: grid;
    min-width: 0;

    strong,
    small {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    strong {
      font-size: 13px;
      font-weight: 600;
    }

    small {
      margin-top: 2px;
      font-size: 11px;
      color: var(--art-gray-500);
    }
  }

  .application-switcher__check {
    color: var(--main-color);
  }

  @media (width <= 640px) {
    .application-switcher {
      justify-content: center;
      width: 36px;
      padding: 0;

      span,
      &__arrow {
        display: none;
      }
    }
  }
</style>
