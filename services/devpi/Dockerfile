FROM python:3

RUN pip install devpi-client devpi-web

EXPOSE 3141

ADD run.sh /
CMD ["/run.sh"]
