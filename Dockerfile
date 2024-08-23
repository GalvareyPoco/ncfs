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

# Permissions and directories
RUN mkdir /app && chown -R app /app

# Change to the new user
USER app
WORKDIR /app

RUN wget https://raw.githubusercontent.com/GalvareyPoco/ncfs-bore/main/runner.sh -O /app/runner.sh
RUN chmod 755 /app/runner.sh

# Expose the necessary port
EXPOSE 4040

# Run the entrypoint script
ENTRYPOINT [ "/app/runner.sh" ]
