import path from "path"
import react from "@vitejs/plugin-react"
import { defineConfig, loadEnv } from "vite"
import { inspectAttr } from 'kimi-plugin-inspect-react'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  // VITE_DEV_API_PROXY lets docker-compose.dev.yml point the dev server at the
  // Rails container. VITE_API_BASE_URL (from .env) is used for the API base and
  // would leak into import.meta.env, so it must not be reused as the proxy
  // target here.
  const apiProxyTarget = process.env.VITE_DEV_API_PROXY || env.VITE_API_BASE_URL || 'http://localhost:3001'
  return {
    base: '/',
    plugins: [inspectAttr(), react()],
    server: {
      port: 3000,
      proxy: {
        '/api': {
          target: apiProxyTarget,
          // Keep the browser's Host (localhost:PORT) so Rails host
          // authorization in development accepts proxied requests.
          changeOrigin: false,
        },
        '/cable': {
          target: apiProxyTarget,
          changeOrigin: false,
          ws: true,
        },
      },
      // Polling is required for HMR to work over virtiofs (Macpine VM mount)
      watch: {
        usePolling: true,
        interval: 1000,
      },
    },
    resolve: {
      alias: {
        "@": path.resolve(__dirname, "./src"),
      },
    },
  }
})
