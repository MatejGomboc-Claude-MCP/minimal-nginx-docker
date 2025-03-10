#!/bin/bash

# Step 1: Create a build container
docker run -d --name nginx-builder alpine:latest tail -f /dev/null

# Step 2: Install build dependencies and compile Nginx from source
docker exec nginx-builder apk add --no-cache gcc libc-dev make openssl-dev pcre-dev zlib-dev linux-headers wget

# Download and extract Nginx source
docker exec nginx-builder sh -c "cd /tmp && wget https://nginx.org/download/nginx-1.24.0.tar.gz && tar -zxf nginx-1.24.0.tar.gz"

# Configure and build Nginx with minimal modules using standard paths
docker exec nginx-builder sh -c "cd /tmp/nginx-1.24.0 && ./configure \
    --prefix=/var/www \
    --sbin-path=/usr/local/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --pid-path=/var/run/nginx.pid \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --with-pcre \
    --with-http_ssl_module \
    --with-http_v2_module \
    --without-http_scgi_module \
    --without-http_uwsgi_module \
    --without-http_fastcgi_module \
    --without-http_geo_module \
    --without-http_map_module \
    --without-http_split_clients_module \
    --without-http_referer_module \
    --without-http_rewrite_module \
    --without-http_proxy_module \
    --without-http_memcached_module \
    --without-mail_pop3_module \
    --without-mail_imap_module \
    --without-mail_smtp_module && make && make install"

# Step 3: Create a minimal filesystem structure with standard paths
docker exec nginx-builder sh -c "mkdir -p /nginx-minimal/etc/nginx && \
    mkdir -p /nginx-minimal/var/log/nginx && \
    mkdir -p /nginx-minimal/var/run && \
    mkdir -p /nginx-minimal/var/www && \
    mkdir -p /nginx-minimal/usr/local/sbin && \
    cp -r /etc/nginx/* /nginx-minimal/etc/nginx/ && \
    cp /usr/local/sbin/nginx /nginx-minimal/usr/local/sbin/"

# Create proper passwd and group files with nobody user and group
docker exec nginx-builder sh -c "mkdir -p /nginx-minimal/etc && \
    echo 'root:x:0:0:root:/root:/bin/sh' > /nginx-minimal/etc/passwd && \
    echo 'nobody:x:65534:65534:nobody:/:/sbin/nologin' >> /nginx-minimal/etc/passwd && \
    echo 'root:x:0:' > /nginx-minimal/etc/group && \
    echo 'nobody:x:65534:' >> /nginx-minimal/etc/group"

# Step 4: Find and copy all required shared libraries
docker exec nginx-builder sh -c "ldd /usr/local/sbin/nginx | grep '=> /' | awk '{print \$3}' | \
    xargs -I '{}' dirname '{}' | sort -u | \
    xargs -I '{}' mkdir -p '/nginx-minimal{}'"

docker exec nginx-builder sh -c "ldd /usr/local/sbin/nginx | grep '=> /' | awk '{print \$3}' | \
    xargs -I '{}' cp -v '{}' '/nginx-minimal{}'"

# Copy dynamic loader if needed
docker exec nginx-builder sh -c "if [ -f /lib/ld-musl-*.so.1 ]; then \
    mkdir -p /nginx-minimal/lib && \
    cp -v /lib/ld-musl-*.so.1 /nginx-minimal/lib/; \
fi"

# Step 5: Create a basic nginx configuration
docker exec nginx-builder sh -c "cat > /nginx-minimal/etc/nginx/nginx.conf << 'EOF'
user nobody;
worker_processes 1;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    # Log configuration
    access_log  /var/log/nginx/access.log;
    error_log   /var/log/nginx/error.log;

    server {
        listen       80;
        server_name  localhost;
        location / {
            root   /var/www;
            index  index.html index.htm;
        }
    }
}
EOF"

# Create a simple index.html file
docker exec nginx-builder sh -c "mkdir -p /nginx-minimal/var/www && \
    echo '<html><body><h1>Hello from minimal Nginx!</h1></body></html>' > \
    /nginx-minimal/var/www/index.html"

# Ensure log directory exists and has proper permissions
docker exec nginx-builder sh -c "chmod 755 /nginx-minimal/var/log/nginx && \
    touch /nginx-minimal/var/log/nginx/access.log /nginx-minimal/var/log/nginx/error.log && \
    chmod 644 /nginx-minimal/var/log/nginx/access.log /nginx-minimal/var/log/nginx/error.log"

# Step 6: Import the filesystem directly as a Docker image
docker exec nginx-builder sh -c "tar -C /nginx-minimal -cf - ." | \
    docker import - \
    --change 'EXPOSE 80' \
    --change 'VOLUME ["/etc/nginx", "/var/log/nginx", "/var/www"]' \
    --change 'CMD ["/usr/local/sbin/nginx", "-g", "daemon off;", "-c", "/etc/nginx/nginx.conf"]' \
    minimal-nginx

# Step 7: Clean up
docker stop nginx-builder
docker rm nginx-builder

# Show the image size
docker images minimal-nginx

echo ""
echo "Minimal Nginx Docker image created successfully!"
echo ""
echo "To run with default configuration:"
echo "docker run -d -p 8080:80 --name nginx-server minimal-nginx"
echo ""
echo "To run with custom configuration and persistent logs:"
echo "docker run -d -p 8080:80 -v \$(pwd)/nginx.conf:/etc/nginx/nginx.conf -v \$(pwd)/logs:/var/log/nginx -v \$(pwd)/www:/var/www --name nginx-server minimal-nginx"
echo ""