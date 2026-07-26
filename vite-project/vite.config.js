import path from "node:path";
import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd());

  return {
    base: "/Gujum.uz/",

    server: {
      host: true,
      port: 3002,
    },

    build: {
      target: "esnext",
      chunkSizeWarningLimit: 2048,
    },

    resolve: {
      alias: {
        "@": path.resolve(__dirname, "./src"),
      },
    },

    plugins: [react(), tailwindcss()],
  };
});