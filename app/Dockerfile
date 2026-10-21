# Kwaku Online Store container image.
# Official NGINX image from Amazon ECR Public (no Docker Hub download limits).
ARG BASE_IMAGE=public.ecr.aws/nginx/nginx:stable-alpine
FROM ${BASE_IMAGE}

# Baked into the image at build time:  docker build --build-arg APP_VERSION=2.0 ...
ARG APP_VERSION=1.0
ENV APP_VERSION=${APP_VERSION}

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY 40-pod-info.sh /docker-entrypoint.d/40-pod-info.sh
RUN chmod +x /docker-entrypoint.d/40-pod-info.sh

EXPOSE 80
