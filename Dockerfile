# Builds fully static (musl) Linux FFmpeg binaries with the AC-4 decoder.
#
# Extract just the binaries (see ./build-linux):
#   container build --arch arm64 --target export -o type=local,dest=dist/linux-arm64 .
#   docker buildx build --platform linux/amd64 --target export -o type=local,dest=dist/linux-amd64 .
#
# Or build a runnable image (default target):
#   container build -t ffmpeg-ac4 .

ARG ALPINE_VERSION=3.24

FROM alpine:${ALPINE_VERSION} AS build

RUN apk add --no-cache \
      bash build-base linux-headers curl ca-certificates perl python3 \
      cmake meson samurai git tar xz bzip2 patch file gperf m4 diffutils coreutils

# Options passed to build-ffmpeg
ARG BUILD_OPTIONS="--enable-gpl-and-non-free --full-static"
# Parallel jobs; empty = auto. build-linux sets this from the host's real RAM,
# because /proc/meminfo inside a container can report the whole host.
ARG NUMJOBS=""

WORKDIR /app
COPY ./build-ffmpeg ./ffmpeg_ac4.patch /app/

RUN NUMJOBS="${NUMJOBS}" SKIPINSTALL=yes ./build-ffmpeg --build ${BUILD_OPTIONS} \
    && mkdir -p /out \
    && cp workspace/bin/ffmpeg workspace/bin/ffprobe /out/ \
    && if [ -f workspace/bin/ffplay ]; then cp workspace/bin/ffplay /out/; fi \
    && file /out/*

# Binaries only, for `-o type=local`
FROM scratch AS export
COPY --from=build /out/ /

# Runnable image
FROM alpine:${ALPINE_VERSION}

# fontconfig config + a font so drawtext/subtitles work
RUN apk add --no-cache ca-certificates fontconfig font-dejavu

COPY --from=build /out/ /usr/local/bin/

RUN ffmpeg -hide_banner -decoders | grep -q ' ac4 '

ENTRYPOINT ["/usr/local/bin/ffmpeg"]
CMD ["-hide_banner", "-version"]
