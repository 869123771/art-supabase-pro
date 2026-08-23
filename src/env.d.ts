/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_APP_CODE?: 'platform' | 'fms' | 'hr' | 'smis' | 'tms' | 'vms'
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}

declare module 'nprogress'

declare module 'crypto-js'

declare module 'vue-img-cutter'

declare module 'file-saver'

declare module 'qrcode.vue' {
  export type Level = 'L' | 'M' | 'Q' | 'H'
  export type RenderAs = 'canvas' | 'svg'
  export type GradientType = 'linear' | 'radial'
  export interface ImageSettings {
    src: string
    height: number
    width: number
    excavate: boolean
  }
  export interface QRCodeProps {
    value: string
    size?: number
    level?: Level
    background?: string
    foreground?: string
    renderAs?: RenderAs
  }
  const QrcodeVue: import('vue').DefineComponent<QRCodeProps>
  export default QrcodeVue
}

// 全局变量声明
declare const __APP_VERSION__: string // 版本号
