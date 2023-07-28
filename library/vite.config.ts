import { defineConfig } from 'vite'
import dts from 'vite-plugin-dts'

// https://vitejs.dev/config/
export default defineConfig({
    build: {
        lib: {
            entry: 'lib/recording.ts',
            name: 'Recording',
            formats: ['es', 'cjs'],
        },
        emptyOutDir: true,
    },
    plugins: [dts({
        insertTypesEntry: true,
    })]
})
