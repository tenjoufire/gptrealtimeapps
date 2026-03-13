FROM node:22-bookworm-slim AS build
WORKDIR /app

COPY package.json package.json
RUN npm install

COPY tsconfig.json tsconfig.json
COPY src src

RUN npm run build

FROM node:22-bookworm-slim
WORKDIR /app

COPY package.json package.json
RUN npm install --omit=dev

COPY --from=build /app/dist dist

ENV PORT=8080
EXPOSE 8080

CMD ["node", "dist/server.js"]
