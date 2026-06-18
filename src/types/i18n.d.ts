import zhMessages from '@/locales/langs/zh.json'

type MessageSchema = typeof zhMessages

declare module 'vue-i18n' {
  export interface DefineLocaleMessage extends MessageSchema {}
}
