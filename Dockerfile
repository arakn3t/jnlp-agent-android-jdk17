FROM jenkins/inbound-agent:alpine as jnlp

#try jdk17 from July'25
FROM jenkins/agent:3309.v27b_9314fd1a_4‑7‑jdk17

ARG version
LABEL Description="This is a base image, which allows connecting Jenkins agents via JNLP protocols" Vendor="Jenkins project" Version="$version"

ARG user=jenkins

USER root


COPY --from=jnlp /usr/local/bin/jenkins-agent /usr/local/bin/jenkins-agent

RUN chmod +x /usr/local/bin/jenkins-agent && \
    ln -s /usr/local/bin/jenkins-agent /usr/local/bin/jenkins-slave

# FYI reduce RUN calls -> minimize image sizes, avoid creating layers with unnecessary cached files
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends curl gcc g++ gnupg unixodbc-dev openssl git && \
    apt-get install -y software-properties-common ca-certificates && \
    apt-get install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev libssl-dev libreadline-dev libffi-dev wget libbz2-dev libsqlite3-dev && \
    update-ca-certificates

# For maven install issue -> "error: error creating symbolic link '/usr/share/man/man1/mvn.1.gz.dpkg-tmp': No such file or directory"
RUN mkdir -p /usr/share/man/man1

RUN apt-get install -y \
    rsync \
    unzip \
    tar \
    gradle \
    maven \
    wget \
    openssh-client \
    ca-certificates-java \
    openjdk-17-jdk \
    xmllint \
    xpath \
    jq

# python
ENV PY_VERSION=3.9.18
RUN mkdir /python && cd /python && \
    wget "https://www.python.org/ftp/python/${PY_VERSION}/Python-${PY_VERSION}.tgz" && \
    tar -zxvf "Python-${PY_VERSION}.tgz" && \
    cd "Python-${PY_VERSION}" && \
    ls -lhR && \
    ./configure --enable-optimizations && \
    make install && \
    rm -rf /python

# mkdocs
# mkdocs-techdocs-core - backstage compat
# simplify doc generation, https://github.com/lukasgeiter/mkdocs-awesome-pages-plugin
# showing date created and updated on every page, https://github.com/timvink/mkdocs-git-revision-date-localized-plugin
RUN pip3 install \
    mkdocs \
    mkdocs-techdocs-core \
    mkdocs-awesome-pages-plugin \
    mkdocs-git-revision-date-localized-plugin

# plantuml
ENV PLANTUML_VERSION=1.2023.2
RUN apt-get update && apt-get install -y \
    graphviz \
    fontconfig
RUN wget "https://github.com/plantuml/plantuml/releases/download/v${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar" -O plantuml.jar
RUN cp plantuml.jar /usr/local/bin/plantuml.jar
RUN echo "#!/usr/bin/env bash\n\njava -Djava.awt.headless=true -jar /usr/local/bin/plantuml.jar -stdrpt:1 \$@" | tee -a /usr/local/bin/plantuml
RUN chmod +x /usr/local/bin/plantuml.jar && chmod +x /usr/local/bin/plantuml

# GitVersion
RUN wget https://github.com/GitTools/GitVersion/releases/download/5.12.0/gitversion-linux-x64-5.12.0.tar.gz
RUN tar -xvf gitversion-linux-x64-5.12.0.tar.gz
RUN mv gitversion /usr/local/bin
RUN chmod +x /usr/local/bin/gitversion

# Dependencies to execute Android builds
RUN apt-get update -qq
RUN dpkg --add-architecture i386 && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    libc6:i386 \
    libgcc1:i386 \
    libncurses5:i386 \
    libstdc++6:i386 \
    libz1:i386

SHELL ["/bin/bash", "-c"]

ENV ANDROID_HOME /opt/sdk
ENV ANDROID_SDK_ROOT /opt/sdk

RUN mkdir -p ${ANDROID_SDK_ROOT}
RUN chmod -Rf 777 ${ANDROID_SDK_ROOT}
RUN chown -Rf 1000:1000 ${ANDROID_SDK_ROOT}
RUN cd ${ANDROID_SDK_ROOT} && wget https://dl.google.com/android/repository/commandlinetools-linux-8512546_latest.zip -O sdk-tools.zip
RUN cd ${ANDROID_SDK_ROOT} && mkdir tmp && unzip sdk-tools.zip -d tmp && rm sdk-tools.zip
RUN cd ${ANDROID_SDK_ROOT} && mkdir -p cmdline-tools/latest && mv tmp/cmdline-tools/* cmdline-tools/latest

ENV PATH ${PATH}:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin

# Accept licenses before installing components, no need to echo y for each component
# License is valid for all the standard components in versions installed from this file
# Non-standard components: MIPS system images, preview versions, GDK (Google Glass) and Android Google TV require separate licenses, not accepted there
RUN yes | sdkmanager --update
RUN yes | sdkmanager --licenses
RUN sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0" "platforms;android-33" "build-tools;33.0.2"
RUN sdkmanager --install "ndk;25.1.8937393" "cmake;3.22.1"

# Please keep all sections in descending order!
# list all platforms, sort them in descending order, take the newest 8 versions and install them
RUN yes | sdkmanager $( sdkmanager --list 2>/dev/null| grep platforms | grep -v "\-ext" | awk -F' ' '{print $1}' | sort -nr -k2 -t- | head -8 | uniq )
# list all build-tools, sort them in descending order and install them
# skip rc versions, increase head count - versions are found twice (actual matches will now be ~5)
RUN yes | sdkmanager $( sdkmanager --list 2>/dev/null | grep build-tools | grep -v "\-rc" | awk -F' ' '{print $1}' | sort -nr -k2 -t\; | head -10 | uniq )
RUN yes | sdkmanager \
    "extras;android;m2repository" \
    "extras;google;m2repository"

USER ${user}

ENTRYPOINT ["/usr/local/bin/jenkins-agent"]
