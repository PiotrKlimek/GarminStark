FROM eclipse-temurin:17-jdk-jammy

RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    jq \
    openssl \
    libglib2.0-0 \
    libsm6 \
    libxrender1 \
    libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

ENV CIQ_HOME="/opt/connectiq-sdk"
ENV PATH="${CIQ_HOME}/bin:${PATH}"

WORKDIR /project

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
