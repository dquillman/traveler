import os
import shutil
from datetime import datetime

# Template content for stay_list.html without the map and with a table listing stays.
template_content = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Traveler • Stays</title>
  <link rel="icon" href="/static/favicon.ico" sizes="any">
  <style>
    :root { --bg:#0f1220; --card:#161a2b; --ink:#e8ebff; --muted:#9aa4d2; --line:#272b41; --accent:#b9c6ff; }
    *{box-sizing:border-box}
    body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Arial; margin:0; background:var(--bg); color:var(--ink); }
    header { padding:14px 18px; background:#101425; color:#fff; display:flex; align-items:center; gap:16px; }
    header .brand { font-weight:700; }
    header nav a { color:var(--accent); text-decoration:none; margin-right:14px; }
    .wrap { max-width:1200px; margin:0 auto; padding:16px; }
    table { width:100%; border-collapse:collapse; background:var(--card); border-radius:14px; overflow:hidden; border:1px solid var(--line); margin-top:16px; }
    th, td { padding:10px 12px; border-bottom:1px solid var(--line); }
    th { text-align:left; color:var(--muted); font-weight:600; background:#12162a; }
    td a { color: var(--accent); text-decoration: none; }
    .muted { color: var(--muted); }
  </style>
</head>
<body>
  <header>
    <div class="brand">Traveler</div>
    <nav>
      <a href="/stays/">Stays</a>
      <a href="/stays/add/">Add</a>
      <a href="/stays/charts/">Charts</a>
      <a href="/stays/import/">Import</a>
      <a href="/stays/export/">Export</a>
      <a href="/appearance/">Appearance</a>
    </nav>
  </header>
  <div class="wrap">
    <h1>Stays</h1>
    <table>
      <thead>
        <tr>
          <th>Park</th>
          <th>City</th>
          <th>State</th>
          <th>Rating</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        {% for stay in stays %}
        <tr>
          <td>{{ stay.park|default:"Stay "|add:stay.pk }}</td>
          <td>{{ stay.city }}</td>
          <td>{{ stay.state }}</td>
          <td>{{ stay.rating }}</td>
          <td>
            <a href="{% url 'stays:detail' stay.pk %}">View</a> |
            <a href="{% url 'stays:edit' stay.pk %}">Edit</a>
          </td>
        </tr>
        {% empty %}
        <tr>
          <td colspan="5" class="muted">No stays found.</td>
        </tr>
        {% endfor %}
      </tbody>
    </table>
  </div>
</body>
</html>
"""



def backup_and_write(file_path):
    if os.path.exists(file_path):
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = f"{file_path}.bak.{timestamp}"
        shutil.copy2(file_path, backup_path)
        print(f"Backed up {file_path} to {backup_path}")
    else:
        # ensure directory exists
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(template_content)
    print(f"Wrote new template to {file_path}")


def main():
    # potential template locations
    possible_paths = [
        os.path.join('templates', 'stays', 'stay_list.html'),
        os.path.join('stays', 'templates', 'stays', 'stay_list.html'),
    ]

    for path in possible_paths:
        backup_and_write(path)


if __name__ == '__main__':
    main()
