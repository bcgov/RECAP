FROM nginx:1.25-alpine

COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html
COPY startup.sh /startup.sh

RUN chmod +x /startup.sh

EXPOSE 80

CMD ["/startup.sh"]
