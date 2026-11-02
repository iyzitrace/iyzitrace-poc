# A stand-in for the customer's queue managers: IBM MQ Advanced for Developers 9.4.5.1 (not for
# production; the container needs LICENSE=accept). The image exists for amd64 only.
FROM icr.io/ibm-messaging/mq:9.4.5.1-r1@sha256:28cd7e9dc413eced83b21e02cd3683966f19ef22867bbc7ca8c1ed19d062f986
# The operating-system group and user of docs/07-ibm-mq.md step 1 (the image has no useradd).
USER 0
RUN echo 'iyzmon:x:1500:' >> /etc/group \
 && echo 'iyzmon:x:1500:1500:IyziTrace monitoring:/nonexistent:/sbin/nologin' >> /etc/passwd
USER 1001
# Run once, when the queue manager is created, after the image's developer defaults.
COPY test/ibm-mq/mq/90-lab.mqsc /etc/mqm/90-lab.mqsc
COPY collectors/ibm-mq/monitor-authorities.mqsc /etc/mqm/91-monitor-authorities.mqsc
