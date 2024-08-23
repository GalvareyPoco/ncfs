FROM ngrok/ngrok:alpine

USER root

# Install dependencies
RUN apk add --no-cache jq curl bash wget git shadow coreutils

# Download and install bore CLI prebuilt binary
RUN wget https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz \
    && tar -xzf bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz \
    && mv bore /usr/local/bin/bore \
    && chmod +x /usr/local/bin/bore \
    && rm bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz

# Create USER
RUN adduser --shell $(which bash) --disabled-password app

# Permission
RUN mkdir /app && chown -R app /app

# Copy necessary files
COPY ncfs.sh /app/ncfs.sh
COPY config.json /app/config.json
COPY config.schema.json /app/config.schema.json

# Setup
COPY runner.sh /app/runner.sh
RUN chmod 755 /app/runner.sh /app/ncfs.sh
RUN chown app:app /app/runner.sh /app/ncfs.sh /app/config.json /app/config.schema.json

# Change user
USER app
WORKDIR /app

EXPOSE 4040
ENTRYPOINT [ "/app/runner.sh" ]
