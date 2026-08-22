<template>
  <ElDropdown
    v-if="applications.length > 1"
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
          v-for="application in applications"
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
  import { currentApplication, type ApplicationCode } from '@/config/application'

  defineOptions({ name: 'ArtApplicationSwitcher' })

  const applications = ref<AccessibleApplication[]>([])

  const iconByApplication: Partial<Record<ApplicationCode, string>> = {
    platform: 'ri:building-4-line',
    finance: 'ri:money-cny-circle-line',
    fms: 'ri:bank-card-line',
    hr: 'ri:team-line',
    smis: 'ri:shield-check-line',
    vms: 'ri:truck-line'
  }

  onMounted(async () => {
    const { data, error } = await fetchAccessibleApplications()
    if (!error) applications.value = data ?? []
  })

  function switchApplication(code: ApplicationCode): void {
    if (code === currentApplication.code) return

    const target = applications.value.find((application) => application.code === code)
    if (target?.baseUrl) window.location.assign(target.baseUrl)
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
