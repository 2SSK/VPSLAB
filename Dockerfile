FROM ubuntu:24.04@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54

ARG DEBIAN_FRONTEND=noninteractive

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        systemd \
        systemd-sysv \
        dbus \
        openssh-server \
        sudo \
        cron \
        ca-certificates \
        curl \
        wget \
        iproute2 \
        iputils-ping \
        iptables \
        nftables \
        net-tools \
        procps \
        psmisc \
        less \
        vim-tiny \
        bash-completion \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY rootfs/ /

RUN userdel -r ubuntu \
    && useradd --create-home --shell /bin/bash deploy \
    && chmod 0440 /etc/sudoers.d/deploy \
    && visudo -c \
    && rm -f /etc/ssh/ssh_host_* /usr/sbin/policy-rc.d \
    && : > /etc/machine-id

STOPSIGNAL SIGRTMIN+3

ENTRYPOINT ["/usr/local/sbin/vps-init"]
CMD ["/sbin/init"]
