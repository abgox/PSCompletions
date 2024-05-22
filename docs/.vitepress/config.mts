import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  base: "/PSCompletions",
  title: "PSCompletions(psc)",
  locales: {
    "en-US": {
      label: "en-US (English)",
      description: "The document of PSCompletions module.",
      link: "/en-US"
    },
    "zh-CN": {
      label: "zh-CN (简体中文)",
      description: "PSCompletions 模块的文档说明",
      link: "/zh-CN"
    }
  },
  themeConfig: {
    socialLinks: [
      { icon: 'github', link: 'https://github.com/abgox/PSCompletions' }
    ]
  }
})
