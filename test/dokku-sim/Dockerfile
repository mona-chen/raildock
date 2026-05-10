FROM alpine:3.20

RUN apk add --no-cache openssh bash docker-cli

# Create dokku user
RUN adduser -D -s /bin/bash dokku && \
    mkdir -p /home/dokku/.ssh && \
    chmod 700 /home/dokku/.ssh

# Install mock dokku script
COPY dokku /usr/local/bin/dokku
RUN chmod +x /usr/local/bin/dokku

# Setup SSH
RUN ssh-keygen -A && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
