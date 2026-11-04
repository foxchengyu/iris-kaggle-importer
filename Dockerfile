FROM intersystemsdc/iris-community:latest

USER root
WORKDIR /opt/irisapp
COPY --chown=irisowner:irisowner . /opt/irisapp
# The base image starts IRIS from the working directory and writes its log
# there, so the directory itself must be writable by irisowner.
RUN chown -R irisowner:irisowner /opt/irisapp
USER irisowner

# Compile the ObjectScript sources into the USER namespace at build time so the
# container is ready to use as soon as it starts. The build fails if the
# compiler reports an error.
RUN iris start IRIS \
 && (iris session IRIS < /opt/irisapp/docker/load.script | tee /tmp/load.log) \
 && ! grep -qi "error" /tmp/load.log \
 && iris stop IRIS quietly

EXPOSE 52773 1972
