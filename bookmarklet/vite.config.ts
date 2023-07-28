import { defineConfig } from 'vite'

// https://vitejs.dev/config/
//
// Build a library that can be imported into a webpage via a <script> tag.
export default defineConfig({
    build: {
        lib: {
            entry: 'lib/bookmarklet.ts',
            fileName: 'bookmarklet',
            formats: ['iife'],
            name: 'bookmarklet',
        },
    },
})
