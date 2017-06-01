FROM debian:sid

RUN echo "deb-src http://deb.debian.org/debian sid main" >> /etc/apt/sources.list
RUN apt update && \
    apt build-dep -y qemu && \
    apt install -y libcapstone-dev less git
