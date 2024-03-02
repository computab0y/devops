FROM owasp/zap2docker-stable

USER root

RUN chown -R :0 /home/zap && \
    chmod -R g+w /home/zap && \
    chown -R :0 /zap && \
    chmod -R g+w /zap
    
USER 1001
