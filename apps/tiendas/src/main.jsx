/**
 * Punto de entrada de la aplicación (lo carga index.html).
 * Monta <App/> dentro de #root con los estilos globales.
 * StrictMode ayuda a detectar efectos mal escritos durante el desarrollo.
 * bootBrand() aplica el color de la última empresa usada en este dispositivo
 * antes de pintar nada (sin parpadeo del azul por defecto).
 */
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '@operalia/compartido/styles/global.css'
import '@operalia/compartido/styles/components.css'
import App from './app/App.jsx'
import { bootBrand } from '@operalia/compartido/theme/brand.js'

bootBrand()

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
