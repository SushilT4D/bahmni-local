FROM nginx:1.27-alpine

# Create expected dirs (certs mounted at /etc/tls)
RUN mkdir -p /etc/tls /var/cache/nginx /usr/share/nginx/html

# Expose HTTPS and HTTP
EXPOSE 443 80

# Note: Mount TLS certs at runtime:
#   -v /path/to/tls:/etc/tls:ro

# Healthcheck (optional)
HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD wget -qO- http://localhost || exit 1

# Copy nginx config
COPY ./htdocs/ /usr/share/nginx/html
RUN chown -R 1000:1000 /usr/share/nginx/html
COPY ./bahmni-nginx.conf /etc/nginx/nginx.conf

CMD ["nginx", "-g", "daemon off;"]
