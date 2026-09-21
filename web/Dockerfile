# syntax=docker/dockerfile:1

FROM nginx:1.31-alpine

# The stock image's nginx.conf already does `include /etc/nginx/conf.d/*.conf`
# inside its http block, so the server block belongs in conf.d. Overwriting
# default.conf replaces the image's stock welcome-page server rather than
# leaving it behind to compete for port 80.
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Nginx's default web root, as configured by `root` in nginx.conf above.
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80

# Inherited from the base image, repeated here only to be explicit:
# "daemon off;" keeps nginx in the foreground as PID 1 so Docker can
# supervise it and see it exit.
CMD ["nginx", "-g", "daemon off;"]
