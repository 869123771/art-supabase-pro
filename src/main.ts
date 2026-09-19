import { bootstrapPlatformApp } from './bootstrap'

bootstrapPlatformApp({
  loadHostedApplications: () => import('./bootstrapHostedApplications')
})
