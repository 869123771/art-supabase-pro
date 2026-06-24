export const WEBSITE_CONFIG_DEFAULTS: Api.SystemManage.WebsiteConfigItem = {
  siteName: 'Art Supabase',
  siteShortName: 'Art Supabase Pro',
  siteDescription: '商业化中后台管理系统',
  logoUrl: '',
  faviconUrl: '',
  watermarkEnabled: true,
  watermarkContentType: 'username',
  watermarkCustomText: '',
  loginTitle: '欢迎使用 Art Supabase',
  loginSubtitle: '面向商业应用的高质量后台管理平台，让管理更高效，让业务更卓越',
  loginDescription: '面向商业应用的高质量后台管理平台，让管理更高效，让业务更卓越',
  defaultLanguage: 'zh',
  captchaEnabled: true,
  captchaType: 'turnstile',
  turnstileSiteKey: '0x4AAAAAADqOIVodNJNAZL57',
  turnstileSize: 'normal',
  turnstileTheme: 'auto',
  captchaMaxAttempts: 0,
  captchaLockMinutes: 10,
  registerEnabled: true,
  maintenanceEnabled: false,
  maintenanceMessage: '维护模式开启时建议填写，例如：系统今晚 23:00-24:00 升级维护',
  seoTitle: 'Art Design Pro',
  seoKeywords: '后台管理系统,企业管理平台,运营后台',
  seoDescription: '商业化中后台管理系统',
  contactEmail: '',
  contactPhone: '',
  contactAddress: '',
  copyrightText: 'Copyright © Art Design Pro',
  icpRecord: '',
  policeRecord: '',
  enabled: true
}

export const createWebsiteConfigDefaults = (): Api.SystemManage.WebsiteConfigItem => ({
  ...WEBSITE_CONFIG_DEFAULTS
})
