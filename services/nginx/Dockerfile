FROM nginx:1.15.8

RUN rm /etc/nginx/conf.d/default.conf
#COPY conf.d/* /etc/nginx/conf.d/
COPY nginx.conf /etc/nginx/nginx.conf
COPY sites-enabled/* /etc/nginx/sites-enabled/
