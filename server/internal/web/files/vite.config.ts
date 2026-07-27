import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import Components from 'unplugin-vue-components/vite'
import AutoImport from 'unplugin-auto-import/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'
import { fileURLToPath, URL } from 'node:url'

// 生产构建输出到 dist/，Go 端 //go:embed all:files/dist 会嵌入
// 开发模式 dev server 端口 5173，API 走 proxy 到本地 Go 服务
export default defineConfig({
  // 生产环境静态资源挂在 /web/static/ 下（见 web.go 的 r.StaticFS）
  // base 必须与 Go 路由前缀一致，否则 index.html 引用的 /assets/... 会 404
  base: '/web/static/',
  plugins: [
    vue(),
    AutoImport({
      imports: ['vue', 'vue-router', 'pinia'],
      resolvers: [ElementPlusResolver()],
      dts: 'src/auto-imports.d.ts',
    }),
    Components({
      resolvers: [ElementPlusResolver()],
      dts: 'src/components.d.ts',
    }),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:8090',
      '/sync': 'http://localhost:8090',
    },
  },
})
