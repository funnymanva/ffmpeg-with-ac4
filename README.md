# Static FFmpeg 9.1 with Dolby AC-4 decoding

Builds a **static** FFmpeg 9.1 for **Linux** and **macOS** with a native Dolby AC-4
decoder patched in, so ATSC 3.0 / DVB AC-4 audio can be transcoded to AC-3 (or anything
else):

```bash
ffmpeg -i input.ts -map 0 -c:v copy -c:a ac3 -b:a 448k output.ts
```

Upstream FFmpeg can demux and mux AC-4 but still has no decoder. `ffmpeg_ac4.patch`
adds one, ported to the FFmpeg 9.1 API.

Based on [markus-perl/ffmpeg-build-script](https://github.com/markus-perl/ffmpeg-build-script)
and [AkashiSN/ffmpeg-build-script](https://github.com/AkashiSN/ffmpeg-build-script).

## Disclaimer And Data Privacy Notice

This script downloads packages with different licenses from many sources, which may
track your usage. These sources are outside the control of this project. With
`--enable-gpl-and-non-free` it creates a **non-free, non-redistributable** binary.

Use this script at your own risk.

## Building

| Target | Where it builds | Output |
|---|---|---|
| Linux (arm64 / amd64), fully static (musl) | in a container: Apple `container`, Podman or Docker | `dist/linux-<arch>/` |
| macOS (arm64 or x86_64) | natively on a Mac | `workspace/bin/` |

A container runs Linux, so it can only produce Linux binaries. macOS binaries have to be
built natively on macOS.

### Which method to use

**For Linux binaries**, try these in order:

1. **`./build-linux`** (container build, recommended). It produces fully static musl
   binaries and needs nothing on the host except one container engine. It uses the first
   engine it finds, in this order:
   1. Apple `container` (macOS)
   2. Podman (4.0 or newer)
   3. Docker (with the `buildx` plugin)
2. **`./build-ffmpeg --build --full-static`** directly on a Linux host. Use this if none
   of those engines is available or you can't install one (for example, no root and an
   older Podman). It links against the host's glibc instead of musl (see
   [Notes on static linking](#notes-on-static-linking)).

**For macOS binaries**, run `./build-ffmpeg --build` natively on a Mac. There is no
container option for macOS.

### Requirements at a glance

| Method | Host needs | Root? |
|---|---|---|
| `build-linux` + Apple `container` | Apple Silicon Mac, macOS 15+ (26 recommended), `container` installed and started | no |
| `build-linux` + Podman | Podman ≥ 4.0 (rootless is fine) | no |
| `build-linux` + Docker | Docker with `buildx` and permission to use the Docker daemon | daemon access |
| native Linux | gcc/g++, make, ninja, perl, python3, gperf, curl or wget, tar, xz, bzip2, patch, file, m4 | no |
| native macOS | Xcode Command Line Tools, ninja (cmake and meson recommended) | no |

Resources, measured on the 4-core, 2 GB Ubuntu 24.04 LXC test machine:

* **Disk:** about 5 GB free. Downloaded sources and build trees in `packages/` take about
  1.6 GB and `workspace/` about 250 MB. A container build also keeps images and build
  cache, about 3.3 GB with Podman.
* **RAM:** at least 2 GB. Plan on about 1 GB per parallel compile job. The scripts limit
  the job count to match (see `NUMJOBS` below).
* **Time:** about 80 minutes for the Podman build there with 2 jobs. Machines with more
  cores and memory are much faster.
* **Network:** every source is downloaded during the build, so outbound HTTPS is needed.

### Linux, in a container

```bash
./build-linux            # host architecture
./build-linux amd64      # x86_64 (on Apple Silicon this runs under Rosetta and is slower)
./build-linux arm64 amd64
```

`build-linux` uses Apple's [`container`](https://github.com/apple/container) if it is
installed, otherwise Podman, then Docker. Only one of them is needed. Override the
choice with `ENGINE=podman` or `ENGINE=docker`.

Engine-specific setup:

* **Apple `container`:** run `container system start` once. On a new installation it
  asks to install a Linux kernel. By default its builder VM also requires Rosetta, even
  for arm64 builds. If Rosetta isn't installed and you only build arm64, put this in
  `~/.config/container/config.toml`:

  ```toml
  [build]
  rosetta = false
  ```

  amd64 builds on Apple Silicon need Rosetta (`softwareupdate --install-rosetta`) and are
  much slower.
* **Podman:** works rootless. In unprivileged LXC containers (no `/dev/net/tun`),
  `build-linux` switches to host networking automatically (see `PODMAN_NETWORK` below).
* **Docker:** needs the `buildx` plugin (`docker buildx version`). To build for a
  different architecture you also need QEMU binfmt emulation, e.g.
  `docker run --privileged --rm tonistiigi/binfmt --install all`.

The binaries are built against musl on Alpine and linked with `-static`, so they have no
runtime dependencies and run on any Linux distribution of that architecture.

Environment variables:

* `BUILD_OPTIONS`: options for `build-ffmpeg` (default `--enable-gpl-and-non-free --full-static`)
* `BUILD_CPUS` / `BUILD_MEMORY`: resources for the Apple container builder (default all CPUs / `8G`)
* `NUMJOBS`: parallel compile jobs for Podman/Docker builds. The default is the lower of the
  CPU count and the host's RAM in GB. `build-linux` works this out on the host because
  `/proc/meminfo` inside a container can show the whole physical machine. In an LXC
  container or VM that would lead to too many jobs and the OOM killer.
* `PODMAN_NETWORK`: network mode for `podman build`. If `/dev/net/tun` is missing, which is
  typical in unprivileged LXC containers, rootless Podman networking cannot start, so
  `build-linux` uses `--network host` automatically.

Tested with rootless Podman 4.9.3 in an unprivileged Ubuntu 24.04 LXC container (x86_64,
4 cores, 2 GB RAM, no root). The resulting `static-pie` musl binaries decode the AC-4
samples to AC-3 and verify HTTPS certificates. Podman 4.0 or newer is required for
`-o type=local`.

You can also call the container engine directly:

```bash
container build --arch arm64 --target export -o type=local,dest=dist/linux-arm64 .
podman build --platform linux/amd64 --network host --build-arg NUMJOBS=2 \
  --target export -o type=local,dest=dist/linux-amd64 .
docker buildx build --platform linux/amd64 --target export -o type=local,dest=dist/linux-amd64 .
```

When you call the engine directly, you have to pass `--build-arg NUMJOBS=...` and the
network option yourself if the host needs them. Apple's `container` writes the files to
`dest/out.tar/linux_<arch>/`, while `build-linux` puts them directly in `dist/linux-<arch>/`.

### Runnable container image

The default Dockerfile target is a small Alpine image with `ffmpeg` as its entrypoint:

```bash
container build -t ffmpeg-ac4 .
container run --rm -v "$PWD:/work" -w /work ffmpeg-ac4 -i input.ts -c:a ac3 output.ac3
```

### macOS, native

Requirements: Xcode Command Line Tools (`xcode-select --install`, which provides the
compiler, make, perl, python3, gperf and curl) and

```bash
brew install cmake meson ninja
```

Only `ninja` is strictly required. If `cmake` (>= 3.24) or `meson` (>= 1.11) is missing,
the script downloads its own copy into `packages/`. This automatic download was tested
on Linux; the macOS build above was tested with the Homebrew versions.

Then:

```bash
SKIPINSTALL=yes ./build-ffmpeg --build --enable-gpl-and-non-free
```

The binaries end up in `workspace/bin/` (`ffmpeg`, `ffprobe`, `ffplay`). Copy them
wherever you want them; `dist/macos-arm64/` is just a copy of a previous build.

All third-party libraries are linked statically. The binaries link only to macOS
system libraries and frameworks, never to Homebrew. The script prints `otool -L` at the
end to confirm this. The default minimum macOS version is 11.0. Set
`MACOSX_DEPLOYMENT_TARGET` to change it.

### Linux, natively (without a container)

You can run `./build-ffmpeg --build` directly on a Linux host. Building needs no root,
but installing the packages below does (an administrator can do it once). On
Debian/Ubuntu:

```bash
sudo apt install build-essential ninja-build perl python3 gperf wget patch xz-utils bzip2 file m4
```

On Alpine, install the package list from the `Dockerfile`. Other distributions need the
same tools. For `--full-static` on glibc you also need the static libc and libstdc++
archives (`libc.a`, `libstdc++.a`). Debian/Ubuntu ship them in `libc6-dev` and
`libstdc++-*-dev`. On Fedora/RHEL they are `glibc-static` and `libstdc++-static`
(untested).

If `cmake` (>= 3.24) or `meson` (>= 1.11) is missing or too old, as on Ubuntu 24.04,
the script downloads a recent version into `packages/` automatically. `git` is not
needed.

```bash
SKIPINSTALL=yes ./build-ffmpeg --build --enable-gpl-and-non-free --full-static
```

The binaries end up in `workspace/bin/`.

This was tested on Ubuntu 24.04 x86_64 (glibc, 4 cores, 2 GB RAM, no root). It produced
a fully static x86_64 binary that decodes AC-4 and resolves HTTPS hosts. Parallel jobs
are limited to about one per GB of RAM so that large C++ sources don't trigger the OOM
killer. Set `NUMJOBS` to override this.

With glibc, `--full-static` works, but musl (Alpine, which the container build uses)
remains the more robust choice for static binaries because of NSS (see below). Without
`--full-static`, libc is linked dynamically and VAAPI is enabled if `libva` is installed.

## Checking a build

```bash
B=dist/linux-amd64            # or workspace/bin
file $B/ffmpeg                # Linux: "statically linked" or "static-pie linked"
otool -L $B/ffmpeg            # macOS: only /usr/lib and /System/Library entries
$B/ffmpeg -hide_banner -decoders | grep ac4
$B/ffmpeg -i sample.ac4 -c:a ac3 -b:a 448k out.ac3
```

## Cleaning up

* `./build-ffmpeg --cleanup` removes `packages/` and `workspace/`.
* Container builds leave images and build cache behind:
  * Podman: `podman system prune -a`
  * Docker: `docker builder prune`
  * Apple `container`: `container image prune` and `container builder delete`

## Usage

```
Usage: build-ffmpeg [OPTIONS]
Options:
  -h, --help                     Display usage information
      --version                  Display version information
  -b, --build                    Starts the build process
      --enable-gpl-and-non-free  Enable GPL and non-free codecs  - https://ffmpeg.org/legal.html
  -c, --cleanup                  Remove all working dirs
      --full-static              Build a full static FFmpeg binary (eg. libc, pthreads etc...) **only Linux**
```

Set `SKIPINSTALL=yes` to skip the "install to /usr/bin" prompt, or `AUTOINSTALL=yes` to
install without asking. `NUMJOBS` overrides the number of parallel jobs.

Downloads are cached in `packages/`. A finished dependency is skipped on the next run
until you delete its `packages/<name>.done` file or run `--cleanup`.

## Updating versions

All dependency versions are listed at the top of `build-ffmpeg`. If you bump
`FFMPEG_VERSION`, check that `ffmpeg_ac4.patch` still applies (`patch -p1 --dry-run`).

## Included libraries

* `AC4`: Dolby AC-4 decoder (patch)
* `x264`, `x265`: H.264 / HEVC encoders (GPL)
* `libsvtav1`, `aom`, `dav1d`: AV1
* `libvpx`: VP8 / VP9
* `xvidcore`: MPEG-4 Part 2 (GPL)
* `vid.stab`: video stabilisation (GPL)
* `fdk_aac`: Fraunhofer FDK AAC (non-free)
* `mp3lame`, `opus`, `vorbis`, `theora`, `speex`, `gsm`, `opencore-amr`
* `libass`, `freetype`, `fontconfig`, `fribidi`, `harfbuzz`: subtitles / drawtext
* `libbluray`, `libxml2` (DASH), `libwebp`, `srt`, `openssl`, `gmp`
* `libdrm` (Linux)
* macOS: VideoToolbox and AudioToolbox hardware/system codecs
* Linux (not full-static): VAAPI if `libva` is installed, NVENC/CUVID if `nvcc` is found

## AC-4 decoder notes

* It decodes mono, stereo and 5.1 channel-based AC-4 (including ATSC 3.0 broadcast
  streams). Use `-presentation N` to select a presentation.
* Immersive / object-based presentations (for example 5.1.4 "IMS") are not supported and
  fail to decode. That is a limitation of the original patch, not of this port.

## Notes on static linking

* glibc does **not recommend** static linking because of NSS (Name Service Switch). See
  https://sourceware.org/glibc/wiki/FAQ#Even_statically_linked_programs_need_some_shared_libraries_which_is_not_acceptable_for_me.__What_can_I_do.3F
  This is why the container build uses musl (Alpine).
* VAAPI cannot be statically linked.
* OpenSSL is configured with `/etc/ssl` as its directory so a static binary can find the
  system CA certificates.
