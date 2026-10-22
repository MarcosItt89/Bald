/**
 * Punto de entrada de la aplicación (lo carga index.html).
 * Monta <App/> dentro de #root con los estilos globales.
 * StrictMode ayuda a detectar efectos mal escritos durante el desarrollo.
 */
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './styles/global.css'
import './styles/components.css'
import App from './app/App.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
