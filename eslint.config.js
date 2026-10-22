/**
 * Configuración de ESLint (npm run lint).
 * - Reglas recomendadas de JS + React Hooks (v7, incluye reglas del React Compiler)
 * - react-refresh: avisa si un archivo .jsx exporta cosas que no son componentes
 */
import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import { defineConfig, globalIgnores } from 'eslint/config'

export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{js,jsx}'],
    extends: [
      js.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      globals: globals.browser,
      parserOptions: { ecmaFeatures: { jsx: true } },
    },
    rules: {
      // Permite `const { campoDeVista, ...fila } = obj` para descartar columnas
      // y parámetros/variables con prefijo "_" que se ignoran a propósito.
      'no-unused-vars': ['error', { ignoreRestSiblings: true, argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
    },
  },
])
