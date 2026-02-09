FROM busybox:latest

# Install required tools for netadmin
RUN apk add --no-cache \
    bash \
    grep \
    sed \
    awk \
    iproute2 \
    iptables \
    iputils

# Copy netadmin files
COPY src/ /jffs/scripts/netadmin/
COPY docs/ /opt/netadmin/docs/

# Set permissions
RUN chmod +x /jffs/scripts/netadmin/hooks/* \
    && chmod +x /jffs/scripts/netadmin/core/*.sh \
    && chmod +x /jffs/scripts/netadmin/cli/* \
    && chmod +x /jffs/scripts/netadmin/profiles/*.sh

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD /jffs/scripts/netadmin/cli/netadmin wan-state --json | grep -q "ready"

WORKDIR /jffs/scripts/netadmin
CMD ["sh", "-c", "echo 'netadmin v3.0 container - ready for deployment'"]
