#!/usr/bin/env python3
"""
Plex TV Database Editor with TMDB Integration
Supports TV shows with season/episode management and TMDB API lookup
Works on macOS and Linux
"""

import tkinter as tk
from tkinter import ttk, messagebox, filedialog, scrolledtext
import subprocess
import os
import sys
from datetime import datetime, timedelta
import shutil
import json
from pathlib import Path
import threading

# optional TMDB integration
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False
    requests = None


class TMDBClient:
    """Handle TheMovieDB API calls"""
    
    def __init__(self, api_key):
        self.api_key = api_key
        self.base_url = "https://api.themoviedb.org/3"
        
    def search_show(self, query):
        """Search for a TV show by name"""
        if not self.api_key or not HAS_REQUESTS:
            return None
        
        try:
            url = f"{self.base_url}/search/tv"
            params = {"api_key": self.api_key, "query": query}
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            return response.json().get("results", [])
        except Exception as e:
            print(f"TMDB search error: {e}")
            return None
    
    def get_season(self, tv_id, season_number):
        """Get episodes for a specific season"""
        if not self.api_key or not HAS_REQUESTS:
            return None
        
        try:
            url = f"{self.base_url}/tv/{tv_id}/season/{season_number}"
            params = {"api_key": self.api_key}
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"TMDB season error: {e}")
            return None
    
    def get_show_info(self, tv_id):
        """Get full show info including seasons"""
        if not self.api_key or not HAS_REQUESTS:
            return None
        
        try:
            url = f"{self.base_url}/tv/{tv_id}"
            params = {"api_key": self.api_key}
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"TMDB show info error: {e}")
            return None


class PlexTVEditor:
    def __init__(self, root):
        self.root = root
        self.root.title("Plex TV Editor v1.0 - with TMDB")
        self.root.geometry("1100x750")
        
        # Configuration file path
        self.config_file = os.path.expanduser("~/.plex_tv_editor_config.json")
        self.load_config()
        
        # TMDB client
        self.tmdb = TMDBClient(self.tmdb_api_key) if self.tmdb_api_key else None
        
        # Check for admin privileges on macOS
        if sys.platform == 'darwin':
            # macOS doesn't require sudo for user-level Plex apps
            pass
        else:
            if os.geteuid() != 0:
                response = messagebox.askyesno("Permission Required", 
                    "This application should be run with sudo for full access.\n"
                    "Continue anyway? (some features may not work)")
                if not response:
                    sys.exit(1)
        
        self.shows = []
        self.episodes = []
        self.setup_ui()
        
        # Validate paths before proceeding
        if self.validate_paths():
            self.check_plex_status()
            self.load_shows()
        else:
            self.show_settings()
    
    def load_config(self):
        """Load configuration from file or use OS-specific defaults"""
        if sys.platform == 'darwin':
            default_config = {
                "plex_sqlite": "/Applications/Plex Media Server.app/Contents/Resources/Support/Plex SQLite",
                "db_path": os.path.expanduser("~/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"),
                "date_format": "%Y-%m-%d %H:%M:%S",
                "tmdb_api_key": ""
            }
        else:
            default_config = {
                "plex_sqlite": "/usr/lib/plexmediaserver/Plex SQLite",
                "db_path": "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db",
                "date_format": "%Y-%m-%d %H:%M:%S",
                "tmdb_api_key": ""
            }
        
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                    self.plex_sqlite = config.get("plex_sqlite", default_config["plex_sqlite"])
                    self.db_path = config.get("db_path", default_config["db_path"])
                    self.date_format = config.get("date_format", default_config["date_format"])
                    self.tmdb_api_key = config.get("tmdb_api_key", default_config["tmdb_api_key"])
            except Exception as e:
                print(f"Error loading config: {e}")
                self.plex_sqlite = default_config["plex_sqlite"]
                self.db_path = default_config["db_path"]
                self.date_format = default_config["date_format"]
                self.tmdb_api_key = default_config["tmdb_api_key"]
        else:
            self.plex_sqlite = default_config["plex_sqlite"]
            self.db_path = default_config["db_path"]
            self.date_format = default_config["date_format"]
            self.tmdb_api_key = default_config["tmdb_api_key"]
    
    def save_config(self):
        """Save configuration to file"""
        config = {
            "plex_sqlite": self.plex_sqlite,
            "db_path": self.db_path,
            "date_format": self.date_format,
            "tmdb_api_key": self.tmdb_api_key
        }
        try:
            with open(self.config_file, 'w') as f:
                json.dump(config, f, indent=2)
            return True
        except Exception as e:
            messagebox.showerror("Config Error", f"Failed to save config: {e}")
            return False
    
    def validate_paths(self):
        """Check if configured paths exist"""
        if not os.path.exists(self.plex_sqlite):
            return False
        if not os.path.exists(self.db_path):
            return False
        return True
    
    def setup_ui(self):
        """Create the user interface"""
        # Menu bar
        menubar = tk.Menu(self.root)
        self.root.config(menu=menubar)
        
        file_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="File", menu=file_menu)
        file_menu.add_command(label="Settings", command=self.show_settings, accelerator="Ctrl+,")
        file_menu.add_command(label="Create Backup", command=self.create_backup, accelerator="Ctrl+B")
        file_menu.add_separator()
        file_menu.add_command(label="Exit", command=self.root.quit, accelerator="Ctrl+Q")
        
        service_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Service", menu=service_menu)
        service_menu.add_command(label="Check Status", command=self.check_plex_status)
        service_menu.add_command(label="Stop Plex", command=self.stop_plex)
        service_menu.add_command(label="Start Plex", command=self.start_plex)
        
        help_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Help", menu=help_menu)
        help_menu.add_command(label="About", command=self.show_about)
        
        # Main container
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # Status bar
        self.status_label = ttk.Label(main_frame, text="Ready", relief=tk.SUNKEN, anchor=tk.W)
        self.status_label.grid(row=0, column=0, columnspan=3, sticky=(tk.W, tk.E), pady=5)
        
        # Plex service status
        status_frame = ttk.Frame(main_frame)
        status_frame.grid(row=1, column=0, columnspan=3, sticky=(tk.W, tk.E), pady=5)
        
        self.plex_status = ttk.Label(status_frame, text="Checking Plex status...", font=("", 10, "bold"))
        self.plex_status.pack(side=tk.LEFT, padx=5)
        
        ttk.Button(status_frame, text="Stop Plex", command=self.stop_plex).pack(side=tk.LEFT, padx=5)
        ttk.Button(status_frame, text="Start Plex", command=self.start_plex).pack(side=tk.LEFT, padx=5)
        ttk.Button(status_frame, text="Create Backup", command=self.create_backup).pack(side=tk.LEFT, padx=5)
        
        # Search and filter frame
        search_frame = ttk.LabelFrame(main_frame, text="TMDB Search", padding="5")
        search_frame.grid(row=2, column=0, columnspan=3, sticky=(tk.W, tk.E), pady=5)
        
        ttk.Label(search_frame, text="Show Name:").grid(row=0, column=0, padx=5)
        self.search_var = tk.StringVar()
        self.search_entry = ttk.Entry(search_frame, textvariable=self.search_var, width=40)
        self.search_entry.grid(row=0, column=1, padx=5)
        self.search_entry.bind('<Return>', lambda e: self.search_tmdb_show())
        
        ttk.Button(search_frame, text="Search TMDB", command=self.search_tmdb_show).grid(row=0, column=2, padx=5)
        ttk.Button(search_frame, text="Load Plex Shows", command=self.load_shows).grid(row=0, column=3, padx=5)
        
        self.count_label = ttk.Label(search_frame, text="", font=("", 10))
        self.count_label.grid(row=0, column=4, padx=20)
        
        # Shows/Episodes list
        list_frame = ttk.LabelFrame(main_frame, text="TV Shows & Episodes", padding="5")
        list_frame.grid(row=3, column=0, columnspan=3, sticky=(tk.W, tk.E, tk.N, tk.S), pady=5)
        
        columns = ('ID', 'Type', 'Title', 'Season', 'Episode', 'Added Date', 'Epoch')
        self.tree = ttk.Treeview(list_frame, columns=columns, show='headings', height=20)
        
        self.tree.heading('ID', text='ID')
        self.tree.heading('Type', text='Type')
        self.tree.heading('Title', text='Title')
        self.tree.heading('Season', text='S')
        self.tree.heading('Episode', text='E')
        self.tree.heading('Added Date', text='Added Date')
        self.tree.heading('Epoch', text='Epoch')
        
        self.tree.column('ID', width=50)
        self.tree.column('Type', width=50)
        self.tree.column('Title', width=300)
        self.tree.column('Season', width=30)
        self.tree.column('Episode', width=30)
        self.tree.column('Added Date', width=150)
        self.tree.column('Epoch', width=0, stretch=False)
        
        self.tree['displaycolumns'] = ('ID', 'Type', 'Title', 'Season', 'Episode', 'Added Date')
        
        scrollbar = ttk.Scrollbar(list_frame, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        
        self.tree.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        scrollbar.grid(row=0, column=1, sticky=(tk.N, tk.S))
        
        self.tree.bind('<Double-Button-1>', self.edit_date)
        
        # Info label
        self.info_label = ttk.Label(main_frame, text="Double-click a date to edit", font=("", 9), foreground="gray")
        self.info_label.grid(row=4, column=0, columnspan=3, pady=5)
        
        # Keyboard bindings
        self.root.bind('<Control-comma>', lambda e: self.show_settings())
        self.root.bind('<Control-b>', lambda e: self.create_backup())
        self.root.bind('<Control-q>', lambda e: self.root.quit())
        self.root.bind('<Control-r>', lambda e: self.load_shows())
        
        # Configure grid
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        main_frame.columnconfigure(0, weight=1)
        main_frame.rowconfigure(3, weight=1)
        list_frame.columnconfigure(0, weight=1)
        list_frame.rowconfigure(0, weight=1)
    
    def execute_sql(self, query):
        """Execute SQL using Plex SQLite"""
        try:
            result = subprocess.run(
                [self.plex_sqlite, self.db_path, query],
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            print(f"SQL ERROR: {e.stderr}")
            messagebox.showerror("SQL Error", f"Error executing query:\n{e.stderr}")
            return None
    
    def check_plex_status(self):
        """Check if Plex is running"""
        if sys.platform == 'darwin':
            # On macOS, check for Plex Media Server process
            result = subprocess.run(['pgrep', '-f', 'Plex Media Server'], capture_output=True)
        else:
            result = subprocess.run(['pgrep', '-x', 'Plex Media Serv'], capture_output=True)
        
        if result.returncode == 0:
            self.plex_status.config(text="WARNING: Plex is RUNNING", foreground="orange")
            return True
        else:
            self.plex_status.config(text="OK: Plex is STOPPED", foreground="green")
            return False
    
    def stop_plex(self):
        """Stop Plex service"""
        self.status_label.config(text="Stopping Plex...")
        try:
            if sys.platform == 'darwin':
                subprocess.run(['launchctl', 'stop', 'com.plexapp.mediaserver'], check=False)
            else:
                subprocess.run(['systemctl', 'stop', 'plexmediaserver'])
            self.check_plex_status()
            self.status_label.config(text="Plex stopped")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to stop Plex: {e}")
    
    def start_plex(self):
        """Start Plex service"""
        self.status_label.config(text="Starting Plex...")
        try:
            if sys.platform == 'darwin':
                subprocess.run(['launchctl', 'start', 'com.plexapp.mediaserver'], check=False)
            else:
                subprocess.run(['systemctl', 'start', 'plexmediaserver'])
            self.check_plex_status()
            self.status_label.config(text="Plex started")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to start Plex: {e}")
    
    def create_backup(self):
        """Create database backup"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_dir = os.path.dirname(self.db_path)
        backup_path = os.path.join(backup_dir, f"com.plexapp.plugins.library.db.backup.{timestamp}")
        
        try:
            shutil.copy2(self.db_path, backup_path)
            messagebox.showinfo("Backup Created", f"Backup saved to:\n{backup_path}")
            self.status_label.config(text=f"Backup created: {os.path.basename(backup_path)}")
        except Exception as e:
            messagebox.showerror("Backup Error", f"Failed to create backup:\n{e}")
    
    def load_shows(self):
        """Load TV shows and episodes from database"""
        self.status_label.config(text="Loading shows...")
        
        query = """
        SELECT id, title, added_at
        FROM metadata_items 
        WHERE type=2 
        ORDER BY added_at DESC 
        LIMIT 100
        """
        
        result = self.execute_sql(query)
        if result:
            for item in self.tree.get_children():
                self.tree.delete(item)
            
            self.shows = []
            lines = result.strip().split('\n')
            for line in lines:
                if '|' in line:
                    parts = line.split('|')
                    if len(parts) >= 3 and parts[0].isdigit():
                        show_id = int(parts[0])
                        title = parts[1]
                        epoch = int(parts[2]) if parts[2].isdigit() else 0
                        
                        try:
                            date_str = datetime.fromtimestamp(epoch).strftime(self.date_format)
                        except:
                            date_str = 'Invalid Date'
                        
                        self.shows.append({
                            'id': show_id,
                            'title': title,
                            'epoch': epoch,
                            'date': date_str
                        })
                        
                        self.tree.insert('', 'end', values=(
                            show_id, 'Show', title, '', '', date_str, epoch
                        ))
            
            self.status_label.config(text=f"Loaded {len(self.shows)} shows")
            self.count_label.config(text=f"Total: {len(self.shows)}")
    
    def search_tmdb_show(self):
        """Search TMDB for a show"""
        if not self.tmdb or not self.tmdb.api_key:
            messagebox.showerror("TMDB Error", "TMDB API key not configured. Please add it in Settings.")
            return
        
        query = self.search_var.get().strip()
        if not query:
            messagebox.showwarning("Input Error", "Please enter a show name to search")
            return
        
        self.status_label.config(text=f"Searching TMDB for '{query}'...")
        self.root.update()
        
        # Search in background
        def search_thread():
            results = self.tmdb.search_show(query)
            if results:
                self.root.after(0, lambda: self.show_tmdb_results(results))
            else:
                self.root.after(0, lambda: messagebox.showinfo("No Results", f"No shows found for '{query}'"))
            self.root.after(0, lambda: self.status_label.config(text="Ready"))
        
        thread = threading.Thread(target=search_thread, daemon=True)
        thread.start()
    
    def show_tmdb_results(self, results):
        """Display TMDB search results in a new window"""
        result_window = tk.Toplevel(self.root)
        result_window.title("TMDB Search Results")
        result_window.geometry("600x400")
        
        ttk.Label(result_window, text="Select a show:", font=("", 11, "bold")).pack(pady=10)
        
        # Listbox with results
        listbox_frame = ttk.Frame(result_window)
        listbox_frame.pack(fill='both', expand=True, padx=10, pady=10)
        
        scrollbar = ttk.Scrollbar(listbox_frame)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        listbox = tk.Listbox(listbox_frame, yscrollcommand=scrollbar.set)
        listbox.pack(side=tk.LEFT, fill='both', expand=True)
        scrollbar.config(command=listbox.yview)
        
        for show in results[:20]:
            display_text = f"{show.get('name', 'Unknown')} ({show.get('first_air_date', 'N/A')[:4]})"
            listbox.insert(tk.END, display_text)
        
        def on_select():
            selection = listbox.curselection()
            if selection:
                show = results[selection[0]]
                show_id = show.get('id')
                show_name = show.get('name')
                self.load_tmdb_show(show_id, show_name)
                result_window.destroy()
        
        ttk.Button(listbox_frame, text="Select", command=on_select).pack(pady=5)
    
    def load_tmdb_show(self, tmdb_id, show_name):
        """Load seasons and episodes from TMDB show"""
        self.status_label.config(text=f"Loading {show_name} from TMDB...")
        self.root.update()
        
        def load_thread():
            show_info = self.tmdb.get_show_info(tmdb_id)
            if show_info:
                self.root.after(0, lambda: self.display_tmdb_show(show_info))
            else:
                self.root.after(0, lambda: messagebox.showerror("Error", f"Failed to load {show_name}"))
            self.root.after(0, lambda: self.status_label.config(text="Ready"))
        
        thread = threading.Thread(target=load_thread, daemon=True)
        thread.start()
    
    def display_tmdb_show(self, show_info):
        """Display TMDB show seasons and episodes"""
        for item in self.tree.get_children():
            self.tree.delete(item)
        
        show_name = show_info.get('name', 'Unknown')
        show_id = show_info.get('id', 0)
        
        self.tree.insert('', 'end', values=(
            show_id, 'Show', show_name, '', '', '', 0
        ))
        
        seasons = show_info.get('seasons', [])
        for season in seasons:
            season_num = season.get('season_number', 0)
            if season_num == 0:
                continue
            
            self.tree.insert('', 'end', values=(
                show_id, 'Season', show_name, season_num, '', '', 0
            ))
        
        self.status_label.config(text=f"Loaded {show_name} with {len([s for s in seasons if s.get('season_number', 0) > 0])} seasons")
    
    def edit_date(self, event):
        """Edit date for selected item"""
        item_id = self.tree.identify_row(event.y)
        if not item_id:
            return
        
        values = self.tree.item(item_id)['values']
        if not values or len(values) < 7:
            return
        
        try:
            item_db_id = values[0]
            item_type = values[1]
            title = str(values[2])
            current_date = str(values[5])
            current_epoch = values[6]
            
            self.create_edit_dialog(item_db_id, title, current_date, current_epoch)
        except Exception as e:
            messagebox.showerror("Error", f"Failed to open edit dialog: {e}")
    
    def create_edit_dialog(self, item_id, title, current_date, current_epoch):
        """Create the date edit dialog"""
        dialog = tk.Toplevel(self.root)
        dialog.title("Edit Date")
        dialog.geometry("600x500")
        dialog.transient(self.root)
        
        # Center
        dialog.update_idletasks()
        x = (dialog.winfo_screenwidth() // 2) - 300
        y = (dialog.winfo_screenheight() // 2) - 250
        dialog.geometry(f"600x500+{x}+{y}")
        
        ttk.Label(dialog, text=f"Item: {title}", font=("", 11, "bold")).pack(pady=10)
        ttk.Label(dialog, text=f"Current Date: {current_date}").pack(pady=5)
        
        # Date input
        input_frame = ttk.Frame(dialog)
        input_frame.pack(pady=20)
        
        ttk.Label(input_frame, text="New Date:").grid(row=0, column=0, padx=5, pady=5)
        date_var = tk.StringVar(value=current_date)
        date_entry = ttk.Entry(input_frame, textvariable=date_var, width=30, font=("", 11))
        date_entry.grid(row=0, column=1, padx=5, pady=5)
        
        ttk.Label(input_frame, text=f"Format: {self.date_format}", font=("", 9), foreground="gray").grid(row=1, column=1, padx=5, pady=2)
        
        # Quick date buttons
        quick_frame = ttk.LabelFrame(dialog, text="Quick Dates", padding="10")
        quick_frame.pack(pady=10, padx=20, fill='x')
        
        button_frame = ttk.Frame(quick_frame)
        button_frame.pack()
        
        def set_date(date_str):
            date_var.set(date_str)
        
        now = datetime.now()
        dates = [
            ("Now", now.strftime(self.date_format)),
            ("Today", now.replace(hour=0, minute=0, second=0).strftime(self.date_format)),
            ("Yesterday", (now - timedelta(days=1)).strftime(self.date_format)),
            ("1 Week Ago", (now - timedelta(weeks=1)).strftime(self.date_format)),
            ("1 Month Ago", (now - timedelta(days=30)).strftime(self.date_format)),
            ("1 Year Ago", (now - timedelta(days=365)).strftime(self.date_format))
        ]
        
        row = 0
        col = 0
        for label, date_val in dates:
            btn = ttk.Button(button_frame, text=label, command=lambda d=date_val: set_date(d))
            btn.grid(row=row, column=col, padx=2, pady=2)
            col += 1
            if col > 2:
                col = 0
                row += 1
        
        result_label = ttk.Label(dialog, text="", foreground="green")
        result_label.pack(pady=5)
        
        def save_edit():
            new_date_str = date_var.get()
            
            if self.check_plex_status():
                result_label.config(text="ERROR: Plex is running! Stop Plex first.", foreground="red")
                response = messagebox.askyesno("Plex is Running", 
                    "Plex Media Server is running. Stop it and try again?")
                if response:
                    self.stop_plex()
                return
            
            try:
                new_datetime = datetime.strptime(new_date_str, self.date_format)
                new_epoch = int(new_datetime.timestamp())
                
                query = f"UPDATE metadata_items SET added_at = {new_epoch} WHERE id = {item_id}"
                result = self.execute_sql(query)
                
                if result is not None:
                    result_label.config(text="SUCCESS! Date updated.", foreground="green")
                    self.load_shows()
                    dialog.after(1500, dialog.destroy)
                else:
                    result_label.config(text="ERROR: Update failed", foreground="red")
                    
            except ValueError as e:
                result_label.config(text=f"ERROR: Invalid date format", foreground="red")
            except Exception as e:
                result_label.config(text=f"ERROR: {str(e)}", foreground="red")
        
        button_frame = ttk.Frame(dialog)
        button_frame.pack(pady=30)
        
        ttk.Button(button_frame, text="SAVE CHANGES", command=save_edit, width=25).pack(side=tk.LEFT, padx=15)
        ttk.Button(button_frame, text="Cancel", command=dialog.destroy, width=20).pack(side=tk.LEFT, padx=15)
        
        date_entry.focus()
        date_entry.select_range(0, tk.END)
    
    def show_settings(self):
        """Show settings dialog"""
        dialog = tk.Toplevel(self.root)
        dialog.title("Settings")
        dialog.geometry("700x500")
        dialog.transient(self.root)
        
        dialog.update_idletasks()
        x = (dialog.winfo_screenwidth() // 2) - 350
        y = (dialog.winfo_screenheight() // 2) - 250
        dialog.geometry(f"700x500+{x}+{y}")
        
        ttk.Label(dialog, text="Configuration Settings", font=("", 14, "bold")).pack(pady=10)
        
        settings_frame = ttk.Frame(dialog, padding="20")
        settings_frame.pack(fill='both', expand=True)
        
        # Plex SQLite path
        ttk.Label(settings_frame, text="Plex SQLite Path:").grid(row=0, column=0, sticky='w', pady=5)
        sqlite_var = tk.StringVar(value=self.plex_sqlite)
        sqlite_entry = ttk.Entry(settings_frame, textvariable=sqlite_var, width=60)
        sqlite_entry.grid(row=0, column=1, pady=5, padx=5)
        
        def browse_sqlite():
            filename = filedialog.askopenfilename(title="Select Plex SQLite executable")
            if filename:
                sqlite_var.set(filename)
        
        ttk.Button(settings_frame, text="Browse", command=browse_sqlite).grid(row=0, column=2, pady=5)
        
        # Database path
        ttk.Label(settings_frame, text="Database Path:").grid(row=1, column=0, sticky='w', pady=5)
        db_var = tk.StringVar(value=self.db_path)
        db_entry = ttk.Entry(settings_frame, textvariable=db_var, width=60)
        db_entry.grid(row=1, column=1, pady=5, padx=5)
        
        def browse_db():
            filename = filedialog.askopenfilename(
                title="Select Plex database",
                filetypes=[("Database files", "*.db"), ("All files", "*.*")]
            )
            if filename:
                db_var.set(filename)
        
        ttk.Button(settings_frame, text="Browse", command=browse_db).grid(row=1, column=2, pady=5)
        
        # Date format
        ttk.Label(settings_frame, text="Date Format:").grid(row=2, column=0, sticky='w', pady=5)
        format_var = tk.StringVar(value=self.date_format)
        format_combo = ttk.Combobox(settings_frame, textvariable=format_var, width=30)
        format_combo['values'] = (
            '%Y-%m-%d %H:%M:%S',
            '%Y/%m/%d %H:%M:%S',
            '%d-%m-%Y %H:%M:%S',
            '%d/%m/%Y %H:%M:%S',
            '%m/%d/%Y %H:%M:%S'
        )
        format_combo.grid(row=2, column=1, pady=5, padx=5, sticky='w')
        
        # TMDB API Key
        ttk.Label(settings_frame, text="TMDB API Key:").grid(row=3, column=0, sticky='w', pady=5)
        tmdb_var = tk.StringVar(value=self.tmdb_api_key)
        tmdb_entry = ttk.Entry(settings_frame, textvariable=tmdb_var, width=60, show='*')
        tmdb_entry.grid(row=3, column=1, pady=5, padx=5)
        
        ttk.Label(settings_frame, text="Get key at: themoviedb.org/settings/api", font=("", 8), foreground="gray").grid(row=4, column=1, sticky='w')
        
        # Status
        status_frame = ttk.LabelFrame(settings_frame, text="Current Status", padding="10")
        status_frame.grid(row=5, column=0, columnspan=3, pady=20, sticky='ew')
        
        sqlite_exists = "[OK]" if os.path.exists(sqlite_var.get()) else "[ERROR]"
        db_exists = "[OK]" if os.path.exists(db_var.get()) else "[ERROR]"
        
        ttk.Label(status_frame, text=f"Plex SQLite: {sqlite_exists}").pack(anchor='w')
        ttk.Label(status_frame, text=f"Database: {db_exists}").pack(anchor='w')
        ttk.Label(status_frame, text=f"TMDB API: {'OK' if tmdb_var.get() else 'NOT SET'}").pack(anchor='w')
        
        # Buttons
        button_frame = ttk.Frame(dialog)
        button_frame.pack(pady=10)
        
        def save_settings():
            self.plex_sqlite = sqlite_var.get()
            self.db_path = db_var.get()
            self.date_format = format_var.get()
            self.tmdb_api_key = tmdb_var.get()
            self.tmdb = TMDBClient(self.tmdb_api_key) if self.tmdb_api_key else None
            
            if self.save_config():
                messagebox.showinfo("Settings", "Settings saved successfully!")
                dialog.destroy()
                if self.validate_paths():
                    self.load_shows()
        
        ttk.Button(button_frame, text="Save", command=save_settings).pack(side=tk.LEFT, padx=5)
        ttk.Button(button_frame, text="Cancel", command=dialog.destroy).pack(side=tk.LEFT, padx=5)
    
    def show_about(self):
        """Show about dialog"""
        about_text = """Plex TV Editor v1.0

Edit TV show and episode timestamps in Plex
with TheMovieDB (TMDB) integration.

Works on macOS and Linux.
Supports bulk edits and season management.
"""
        messagebox.showinfo("About", about_text)


if __name__ == "__main__":
    try:
        root = tk.Tk()
        app = PlexTVEditor(root)
        root.mainloop()
    except Exception as e:
        print(f"Error starting GUI: {e}")
        import traceback
        traceback.print_exc()
