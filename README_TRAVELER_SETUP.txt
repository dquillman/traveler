TRAVELER QUICK SETUP
1) Create/activate your virtualenv (skip if already done):
   python -m venv venv
   venv\Scripts\activate
2) Install dependencies:
   pip install -r requirements.txt
3) Make DB migrations:
   python manage.py makemigrations
   python manage.py migrate
4) (Optional) Backfill coordinates for existing stays:
   python manage.py backfill_coords
5) Run the site:
   python manage.py runserver
   # Home: http://127.0.0.1:8000/
   # Map : http://127.0.0.1:8000/map/
