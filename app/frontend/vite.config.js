// vite.config.js
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
    plugins: [react()],
    server: {
        host:   '0.0.0.0',  // exponer en todas las interfaces del EC2
        port:   5173,
        // Proxy en desarrollo: redirige /api al backend local
        // En producción usa VITE_API_URL directamente
        proxy: {
            '/api': {
                target:      'http://localhost:3001',
                changeOrigin: true
            }
        }
    },
    build: {
        outDir: 'dist',
        // El servidor web (Nginx) servirá esta carpeta en producción
        sourcemap: false
    },
    preview: {
        host: '0.0.0.0',
        port: 4173
    }
})
