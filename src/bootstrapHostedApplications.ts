import type { Component } from 'vue'
import { registerApplicationViewModules } from '@/router/core/ComponentLoader'
import { registerFmsRecognitionIntegration } from '@fms/integrations'

type HostedRouteComponentModule = { default: Component }

function registerHostedApplication(
  applicationCode: string,
  sourceRoot: string,
  sourceModules: Record<string, () => Promise<HostedRouteComponentModule>>
): void {
  registerApplicationViewModules(applicationCode, sourceRoot, sourceModules)
}

registerFmsRecognitionIntegration()
registerHostedApplication(
  'fms',
  '../modules/art-supabase-fms/src/views',
  import.meta.glob<HostedRouteComponentModule>([
    '../modules/art-supabase-fms/src/views/**/*.vue',
    '!../modules/art-supabase-fms/src/views/**/modules/**/*.vue',
    '!../modules/art-supabase-fms/src/views/**/components/**/*.vue'
  ])
)
registerHostedApplication(
  'hr',
  '../modules/art-supabase-hr/src/views',
  import.meta.glob<HostedRouteComponentModule>([
    '../modules/art-supabase-hr/src/views/**/*.vue',
    '!../modules/art-supabase-hr/src/views/**/modules/**/*.vue',
    '!../modules/art-supabase-hr/src/views/**/components/**/*.vue'
  ])
)
registerHostedApplication(
  'smis',
  '../modules/art-supabase-smis/src/views',
  import.meta.glob<HostedRouteComponentModule>([
    '../modules/art-supabase-smis/src/views/**/*.vue',
    '!../modules/art-supabase-smis/src/views/**/modules/**/*.vue',
    '!../modules/art-supabase-smis/src/views/**/components/**/*.vue'
  ])
)
registerHostedApplication(
  'tms',
  '../modules/art-supabase-tms/src/views',
  import.meta.glob<HostedRouteComponentModule>([
    '../modules/art-supabase-tms/src/views/**/*.vue',
    '!../modules/art-supabase-tms/src/views/**/modules/**/*.vue',
    '!../modules/art-supabase-tms/src/views/**/components/**/*.vue'
  ])
)
registerHostedApplication(
  'vms',
  '../modules/art-supabase-vms/src/views',
  import.meta.glob<HostedRouteComponentModule>([
    '../modules/art-supabase-vms/src/views/**/*.vue',
    '!../modules/art-supabase-vms/src/views/**/modules/**/*.vue',
    '!../modules/art-supabase-vms/src/views/**/components/**/*.vue'
  ])
)
