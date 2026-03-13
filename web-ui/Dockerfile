FROM node:22-bookworm-slim AS build
WORKDIR /app

COPY package.json package.json
RUN npm install

COPY tsconfig.json tsconfig.json
COPY tsconfig.node.json tsconfig.node.json
COPY vite.config.ts vite.config.ts
COPY index.html index.html
COPY src src

ARG VITE_AGENT_API_BASE_URL=http://localhost:8080
ENV VITE_AGENT_API_BASE_URL=$VITE_AGENT_API_BASE_URL

RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
