FROM ubuntu:24.04
LABEL org.opencontainers.image.authors="DOMjudge team <team@domjudge.org>"

ENV DEBIAN_FRONTEND=noninteractive \
	CONTAINER_TIMEZONE=Europe/Amsterdam \
	DOMSERVER_BASEURL=http://domserver/ \
	JUDGEDAEMON_USERNAME=judgehost \
	JUDGEDAEMON_PASSWORD=password \
	DAEMON_ID=0 \
	DOMJUDGE_CREATE_WRITABLE_TEMP_DIR=0 \
	RUN_USER_UID_GID=62860

# Set up user
RUN useradd -m domjudge

# Install required packages for running of judgehost
RUN apt update \
	&& apt install --no-install-recommends --no-install-suggests -y \
	dumb-init \
	acl zip unzip supervisor sudo procps libcgroup-dev \
	php-cli php-zip php-gd php-curl php-mysql php-json \
	php-gmp php-xml php-mbstring php-bcmath python3 \
	gcc g++ openjdk-21-jre-headless openjdk-21-jdk-headless ghc fp-compiler \
	&& rm -rf /var/lib/apt/lists/*

# Install more languages
COPY judgehost/add_repositories.sh /add_repositories.sh
RUN chmod 700 /add_repositories.sh && /add_repositories.sh && rm -f /add_repositories.sh
RUN apt update \
	&& apt install --no-install-recommends --no-install-suggests -y \
	openjdk-17-jre-headless openjdk-17-jdk-headless pypy3 chipcie-kotlin \
	&& rm -rf /var/lib/apt/lists/*

# Add chroot and judgehost data
ADD chroot.tar.gz /
ADD judgehost.tar.gz /
RUN cp /opt/domjudge/judgehost/etc/sudoers-domjudge /etc/sudoers.d/

# Add scripts
COPY judgehost/scripts /scripts/

# Make the scripts available to the root user
ENV PATH="$PATH:/opt/domjudge/judgehost/bin"

# Run customizations
COPY judgehost/configure.sh /configure.sh
RUN chmod 700 /configure.sh && /configure.sh && rm -f /configure.sh

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/scripts/start.sh"]
