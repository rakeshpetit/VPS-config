FROM tailscale/tailscale:v1.102.5 AS tailscale

FROM node:22-bookworm-slim

# Pi moved from @mariozechner/ to @earendil-works/ (the old package is deprecated at 0.73.1).
ARG PI_VERSION=1.5.2
ARG PI_WEB_VERSION=0.17.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git gh jq ripgrep \
      python3 python3-pip python3-venv build-essential \
 && rm -rf /var/lib/apt/lists/*

COPY --from=tailscale /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale /usr/local/bin/tailscale /usr/local/bin/tailscale

# Real pi and pi-web live under /opt/pi. pi-web (agegr/pi-web) pins its own copy of
# the Pi packages as exact dependencies, so keep PI_VERSION equal to the version
# its package.json pins. /usr/local/bin/pi is the secret-loading wrapper.
# pi-web ships the preview-mode secrets of its published build, which let a request
# skip its Host and password checks. It would rotate them at every start, but the
# rootfs is read-only, so rotate them once here: the values are then unique to
# this image instead of public.
RUN npm install -g --prefix /opt/pi \
      @earendil-works/pi-coding-agent@${PI_VERSION} \
      @agegr/pi-web@${PI_WEB_VERSION} \
 && node -e "const d='/opt/pi/lib/node_modules/@agegr/pi-web/.next'; const r=require('/opt/pi/lib/node_modules/@agegr/pi-web/bin/rotate-preview-secrets').rotatePreviewSecrets(d); if(!r.ok){console.error('preview secret rotation failed',r);process.exit(1)}" \
 && npm cache clean --force

COPY pi-wrapper.sh /usr/local/bin/pi
COPY git-credential-pi-token.sh /usr/local/bin/git-credential-pi-token
COPY pi-web-wrapper.sh /usr/local/bin/pi-web-wrapper
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/pi /usr/local/bin/pi-web-wrapper /usr/local/bin/git-credential-pi-token /usr/local/bin/entrypoint.sh \
 && git config --system credential.helper /usr/local/bin/git-credential-pi-token

# uid/gid 1000 matches the owner of the host-side secret files. node:22 ships a
# "node" user at 1000, so replace it.
RUN userdel -r node \
 && useradd --uid 1000 --create-home --shell /bin/bash pi \
 && mkdir -p /workspace /var/lib/tailscale \
 && chown pi:pi /workspace /var/lib/tailscale

USER pi
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
