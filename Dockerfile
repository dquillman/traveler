FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt && pip install --no-cache-dir gunicorn
COPY . /app
RUN mkdir -p /app/media /app/staticfiles
EXPOSE 8000
CMD sh -c "python manage.py migrate && gunicorn config.wsgi:application --bind 0.0.0.0:8000 --workers 3 --timeout 60"
