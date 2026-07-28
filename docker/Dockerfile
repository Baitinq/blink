# Build and smoke-test the Linux port without leaving macOS:
#   docker build -f docker/Dockerfile -t blink-linux .
#   docker run --rm blink-linux            # build + core self-test + overlay render
FROM swift:6.0-noble

RUN apt-get update && apt-get install -y --no-install-recommends \
        pkg-config \
        libx11-dev libxss-dev libxrandr-dev libcairo2-dev \
        xvfb x11-utils imagemagick fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY Package.swift ./
COPY Sources ./Sources
COPY docker/smoke.sh /usr/local/bin/smoke.sh
RUN chmod +x /usr/local/bin/smoke.sh && swift build -c release

CMD ["/usr/local/bin/smoke.sh"]
