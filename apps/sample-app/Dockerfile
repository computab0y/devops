FROM python:3.11-alpine
WORKDIR /app
COPY app.py .
ENV PORT=8080
EXPOSE 8080
USER 1001
CMD ["python", "app.py"]
