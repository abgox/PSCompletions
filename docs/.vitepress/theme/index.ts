// https://vitepress.dev/guide/custom-theme
// import { h } from 'vue'
import type { Theme } from 'vitepress'
import DefaultTheme from 'vitepress/theme'
import './style.css'
import Layout from "./layout.vue"

export default {
  extends: DefaultTheme,
  // Layout: () => {
  //   return h(DefaultTheme.Layout, null, {
  //     // https://vitepress.dev/guide/extending-default-theme#layout-slots
  //   })
  // },
  Layout,
  enhanceApp() {
    try {
      const langs = ['en-US', 'zh-CN']
      let lang = navigator.language
      if (!langs.includes(lang)) {
        lang = langs[0]
      }
      if (/\/PSCompletions\/?$/.test(location.pathname)) {
        location.href += lang
      }
    } catch { }
  }
} satisfies Theme
