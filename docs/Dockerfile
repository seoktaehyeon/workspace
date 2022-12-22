FROM jekyll/jekyll:4 AS builder
COPY . .
RUN sed -i 's/# EXCLUDE_IN_DOCKER//' _config.yml \
    && sed -i '/# EXCLUDE_IN_GITEE_PAGES/d' _config.yml \
    && jekyll clean \
    && jekyll build \
    && mv _site /html

FROM nginx:1.16-alpine
COPY --from=builder /html /usr/share/nginx/html
EXPOSE 80