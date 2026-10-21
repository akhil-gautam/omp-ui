import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

// Tauri serves the dev server on a fixed port and expects the build output in ../dist.
export default defineConfig({
	plugins: [react()],
	clearScreen: false,
	server: {
		port: 1420,
		strictPort: true,
		watch: { ignored: ["**/src-tauri/**", "**/vendor/**"] },
	},
	build: {
		target: "safari15",
		sourcemap: false,
		chunkSizeWarningLimit: 900,
	},
	test: {
		// The markdown pipeline sanitises through the DOM.
		environment: "jsdom",
		setupFiles: ["./src/test-setup.ts"],
	},
});
