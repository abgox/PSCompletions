import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  base: "/PSCompletions/",
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
    ],
    search: {
      provider: 'local',
      options: {
        locales: {
          "zh-CN": {
            translations: {
              button: {
                buttonText: '搜索文档',
                buttonAriaLabel: '搜索文档'
              },
              modal: {
                displayDetails: "显示详细列表",
                noResultsText: '无法找到相关结果',
                resetButtonTitle: '清除查询条件',
                footer: {
                  selectText: '选择',
                  navigateText: '切换',
                  closeText: "关闭"
                }
              }
            }
          }
        }
      }
    },
    outline: "deep",
    footer: {
      message: 'Released under the <a href="https://github.com/abgox/PSCompletions/blob/main/LICENSE">MIT License</a>.',
      copyright: 'Copyright © 2023-present <a href="https://github.com/abgox">abgox</a>'
    }
  },
})
