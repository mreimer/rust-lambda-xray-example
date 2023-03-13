ARG base_image
FROM ${base_image} AS builder

FROM alpine AS runtime
RUN apk --update add ca-certificates
ARG log_level
RUN addgroup -S myuser && adduser -S myuser -G myuser
ENV RUST_LOG=${log_level}
# extension.zip generated from: aws lambda get-layer-version-by-arn --arn arn:aws:lambda:ca-central-1:901920570463:layer:aws-otel-collector-amd64-ver-0-70-0:4 | jq -r '.Content.Location' | xargs curl -o extension.zip
COPY extension.zip /opt
RUN unzip /opt/extension.zip -d /opt && rm /opt/extension.zip && ls -R /opt
COPY otel-config.yaml /etc
ENV OPENTELEMETRY_COLLECTOR_CONFIG_FILE=/etc/otel-config.yaml
RUN mkdir -p /opt/aws/aws-otel-collector/etc
COPY extracfg.txt /opt/aws/aws-otel-collector/etc

COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/handler /usr/local/bin/handler
USER myuser
CMD ["/usr/local/bin/handler"]