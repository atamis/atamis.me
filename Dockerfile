# Containerized hugo
FROM alpine:3.15 as hugo

ENV HUGO_VERSION 0.92.2
ENV HUGO_BINARY hugo_${HUGO_VERSION}_Linux-64bit.tar.gz

# Install Hugo
RUN set -x && \
  apk add --no-cache --update wget ca-certificates && \
  wget https://github.com/spf13/hugo/releases/download/v${HUGO_VERSION}/${HUGO_BINARY} && \
  tar xzf ${HUGO_BINARY} && \
  rm -r ${HUGO_BINARY} && \
  mv hugo /usr/bin && \
  apk del --no-cache wget ca-certificates

ENTRYPOINT ["/usr/bin/hugo"]

# Resume builder
FROM blang/latex:ubuntu as resume-builder

COPY ./cv/ /work

RUN cd /work && latexmk -pdf -pdflatex="pdflatex --file-line-error --shell-escape -interaction=nonstopmode"

# Site builder

FROM hugo as site-builder

COPY ./ /site

COPY --from=resume-builder /work/main.pdf /site/static/downloads/resume.pdf

RUN apk add --no-cache make curl && cd /site && make katex

RUN cd /site && /usr/bin/hugo --minify --config config.toml,ci/docker.toml

# Final NGINX container
FROM nginx:alpine

COPY --from=site-builder /site/public /usr/share/nginx/html

