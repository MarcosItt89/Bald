/**
 * Consola Operalia — punto de entrada. Usa los estilos y componentes del
 * paquete compartido; no aplica la marca de ninguna empresa (siempre Operalia).
 */
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '@operalia/compartido/styles/global.css'
import '@operalia/compartido/styles/components.css'
import './consola.css'
import App from './App.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
