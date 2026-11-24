FROM node:lts-bookworm-slim AS bootstrap

COPY --chmod=755 <<'SCRIPT' /usr/local/bin/scaffold
#!/bin/sh
set -eu
exec 3>&1 1>&2

cd /tmp
npx --yes create-vite@latest frontend --template react --no-interactive --no-immediate
cd frontend
npm install --package-lock-only --save-exact --no-audit --no-fund "react@$1" "react-dom@$1"

cat > vite.config.js <<'JS'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 5173,
    strictPort: true,
    proxy: {
      '/api': process.env.API_PROXY_TARGET ?? 'http://127.0.0.1:8000',
    },
  },
});
JS

cat > src/App.jsx <<'JSX'
import { useEffect, useState } from 'react';

const apiBaseUrl = (import.meta.env.VITE_API_BASE_URL ?? '/api').replace(/\/+$/, '');

export default function App() {
  const [status, setStatus] = useState('Checking the API…');

  useEffect(() => {
    const controller = new AbortController();

    fetch(`${apiBaseUrl}/health`, { signal: controller.signal })
      .then((response) => {
        if (!response.ok) throw new Error('API health check failed');
        return response.json();
      })
      .then(({ database }) => setStatus(database === 'connected' ? 'API and MySQL are ready.' : 'MySQL is unavailable.'))
      .catch(() => {
        if (!controller.signal.aborted) setStatus('Could not reach the API and MySQL.');
      });

    return () => controller.abort();
  }, []);

  return (
    <main>
      <h1>App Local</h1>
      <p role="status">{status}</p>
    </main>
  );
}
JSX

printf '%s\n' 'VITE_API_BASE_URL=/api' > .env.example

cat > .dockerignore <<'IGNORE'
.env*
.git
node_modules/
dist/
IGNORE

exec tar -cf - . >&3
SCRIPT

FROM node:lts-bookworm-slim AS runtime

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

CMD ["npm", "run", "dev"]
