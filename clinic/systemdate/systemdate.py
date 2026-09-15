#!/usr/bin/env python3
"""
Simple HTTP service to provide system date information.
Replaces the CGI script /cgi-bin/systemdate
"""

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from datetime import datetime

class DateHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Get current datetime
        now = datetime.now()

        # Format date as "MM/DD/YY HH:MM:SS AM/PM TIMEZONE"
        date_str = now.strftime("%m/%d/%y %I:%M:%S %p %Z")

        # Get timezone offset as +HHMM or -HHMM
        offset = now.strftime("%z")

        # Build JSON response
        response = {
            "date": date_str,
            "offset": offset
        }

        # Send response
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())

    def log_message(self, format, *args):
        # Optional: customize logging or suppress it
        pass

def run(port=8765):
    server_address = ('0.0.0.0', port)
    httpd = HTTPServer(server_address, DateHandler)
    print(f'Starting systemdate service on port {port}...')
    httpd.serve_forever()

if __name__ == '__main__':
    run()
