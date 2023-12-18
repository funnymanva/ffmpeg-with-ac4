FROM ubuntu:22.04 AS build

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update \
    && apt-get -y --no-install-recommends install build-essential curl ca-certificates libva-dev python3 tcl meson gperf m4 \
    && apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* \
    && update-ca-certificates

WORKDIR /app
COPY ./build-ffmpeg /app/build-ffmpeg
COPY ./ffmpeg_ac4.patch /app/ffmpeg_ac4.patch

RUN SKIPINSTALL=yes /app/build-ffmpeg --build --enable-gpl-and-non-free

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND noninteractive

# install va-driver
RUN apt-get update && \
    apt-get -y dist-upgrade && \
    apt-get -y install curl ca-certificates libva-drm2 && \
    apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* && \
    update-ca-certificates

# Copy ffmpeg
COPY --from=build /app/workspace/bin/ffmpeg /usr/bin/ffmpeg
COPY --from=build /app/workspace/bin/ffprobe /usr/bin/ffprobe
COPY --from=build /app/workspace/bin/ffplay /usr/bin/ffplay

# Check shared library
RUN ldd /usr/bin/ffmpeg
RUN ldd /usr/bin/ffprobe
RUN ldd /usr/bin/ffplay

CMD         ["--help"]
ENTRYPOINT  ["/usr/bin/ffmpeg"]
