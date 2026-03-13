FROM node:22-bookworm-slim AS build
WORKDIR /app

COPY package.json package.json
RUN npm install

COPY tsconfig.json tsconfig.json
COPY tsconfig.node.json tsconfig.node.json
COPY vite.config.ts vite.config.ts
COPY index.html index.html
COPY public public
COPY src src

RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY --from=build /app/public/runtime-config.template.js /usr/share/nginx/html/runtime-config.template.js
COPY docker/40-runtime-config.sh /docker-entrypoint.d/40-runtime-config.sh
RUN chmod +x /docker-entrypoint.d/40-runtime-config.sh
ENV VITE_AGENT_API_BASE_URL=http://localhost:8080
EXPOSE 80
