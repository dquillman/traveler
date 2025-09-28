FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt && pip install --no-cache-dir gunicorn
COPY . /app
RUN mkdir -p /app/media /app/staticfiles
# Render and similar platforms provide a dynamic $PORT.
EXPOSE 8000
ENV PORT=8000
CMD sh -c "python manage.py collectstatic --noinput && python manage.py migrate --noinput && gunicorn config.wsgi:application --bind 0.0.0.0:$PORT --workers 3 --timeout 120"
