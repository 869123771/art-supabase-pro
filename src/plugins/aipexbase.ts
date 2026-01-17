import { createClient } from 'aipexbase-js'

export default {
  install(app, options) {
    const client = createClient({
      baseUrl: options.baseUrl,
      apiKey: options.apiKey
    })

    app.config.globalProperties.$aipexbase = client
    app.provide('aipexbase', client)
  }
}
