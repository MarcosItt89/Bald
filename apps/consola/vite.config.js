// Consola Operalia (superadmins). Sin PWA: es una herramienta de escritorio.
// envDir: lee el .env de la raíz del repo (las mismas VITE_SUPABASE_* que la app de tiendas).
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  envDir: '../..',
  server: { port: 5174 },
  preview: { port: 4174 },
  // Marca el build como Consola (env.app en el paquete compartido).
  define: { 'import.meta.env.VITE_OPERALIA_APP': JSON.stringify('consola') },
  plugins: [react()],
})
