FROM ubuntu:18.04
RUN DEBIAN_FRONTEND=noninteractive apt-get update
RUN apt-get install -y curl gnupg netcat
RUN cd /opt/
RUN curl -O https://repo.percona.com/apt/percona-release_latest.bionic_all.deb
RUN dpkg -i percona-release_latest.bionic_all.deb
RUN apt-get update
RUN apt-get install -y percona-xtrabackup-24
RUN mkdir -p /var/lib/mysql
VOLUME /xtrabackup
