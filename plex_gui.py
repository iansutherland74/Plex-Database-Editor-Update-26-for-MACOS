#!/usr/bin/env python3
"""
Plex Database Editor - GUI Version 2.1 Fixed
Clean interface with human-readable dates and configurable paths
Fixed double-click editing and window grab issues
"""

import tkinter as tk
from tkinter import ttk, messagebox, filedialog
import subprocess
import os
import sys
from datetime import datetime, timedelta
import shutil
import json
from pathlib import Path

# optional dependency for TMDB integration
try:
    import requests
except ImportError:
    requests = None  # will check later when needed


class PlexDatabaseEditor:
    def __init__(self, root):
        self.root = root
        self.root.title("Plex Database Editor v2.1")
        self.root.geometry("1000x700")
        
        # Configuration file path
        self.config_file = os.path.expanduser("~/.plex_editor_config.json")
        self.load_config()
        
        # Check if running as root
        if os.geteuid() != 0:
            response = messagebox.askyesno("Permission Required", 
                "This application should be run with sudo for full access.\n"
                "Continue anyway? (some features may not work)")
            if not response:
                sys.exit(1)
        
        self.movies = []
        self.setup_ui()
        
        # Validate paths before proceeding
        if self.validate_paths():
            self.check_plex_status()
            self.load_movies()
        else:
            self.show_settings()
    
    def load_config(self):
        """Load configuration from file or use defaults"""
        default_config = {
            "plex_sqlite": "/usr/lib/plexmediaserver/Plex SQLite",
            "db_path": "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db",
            "date_format": "%Y-%m-%d %H:%M:%S"
        }
        
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                    self.plex_sqlite = config.get("plex_sqlite", default_config["plex_sqlite"])
                    self.db_path = config.get("db_path", default_config["db_path"])
                    self.date_format = config.get("date_format", default_config["date_format"])
            except Exception as e:
                print(f"Error loading config: {e}")
                self.plex_sqlite = default_config["plex_sqlite"]
                self.db_path = default_config["db_path"]
                self.date_format = default_config["date_format"]
        else:
            self.plex_sqlite = default_config["plex_sqlite"]
            self.db_path = default_config["db_path"]
            self.date_format = default_config["date_format"]
    
    def save_config(self):
        """Save configuration to file"""
        config = {
            "plex_sqlite": self.plex_sqlite,
            "db_path": self.db_path,
            "date_format": self.date_format,
            "tmdb_api_key": getattr(self, 'tmdb_api_key', '')
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
        
        # File menu
        file_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="File", menu=file_menu)
        file_menu.add_command(label="Settings", command=self.show_settings, accelerator="Ctrl+,")
        file_menu.add_command(label="Create Backup", command=self.create_backup, accelerator="Ctrl+B")
        file_menu.add_separator()
        file_menu.add_command(label="Exit", command=self.root.quit, accelerator="Ctrl+Q")
        
        # Service menu
        service_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Service", menu=service_menu)
        service_menu.add_command(label="Check Status", command=self.check_plex_status)
        service_menu.add_command(label="Stop Plex", command=self.stop_plex)
        service_menu.add_command(label="Start Plex", command=self.start_plex)
        
        # Help menu
        help_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Help", menu=help_menu)
        help_menu.add_command(label="Date Format Help", command=self.show_date_help)
        help_menu.add_command(label="Keyboard Shortcuts", command=self.show_shortcuts)
        help_menu.add_command(label="About", command=self.show_about)
        
        # Main container
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # Status bar at top
        self.status_label = ttk.Label(main_frame, text="Ready", 
                                     relief=tk.SUNKEN, anchor=tk.W)
        self.status_label.grid(row=0, column=0, columnspan=3, sticky=(tk.W, tk.E), pady=5)
        
        # Plex service status
        status_frame = ttk.Frame(main_frame)
        status_frame.grid(row=1, column=0, columnspan=3, sticky=(tk.W, tk.E), pady=5)
        
        self.plex_status = ttk.Label(status_frame, text="Checking Plex status...", font=("", 10, "bold"))
        self.plex_status.pack(side=tk.LEFT, padx=5)
        
        ttk.Button(status_frame, text="Stop Plex", 
                  command=self.stop_plex).pack(side=tk.LEFT, padx=5)
        ttk.Button(status_frame, text="Start Plex", 
                  command=self.start_plex).pack(side=tk.LEFT, padx=5)
        ttk.Button(status_frame, text="Create Backup", 
                  command=self.create_backup).pack(side=tk.LEFT, padx=5)
        
        # Search and filter frame
        search_frame = ttk.LabelFrame(main_frame, text="Search & Filter", padding="5")
        search_frame.grid(row=2, column=0, columnspan=3, sticky=(tk.W, tk.E), pady=5)
        
        ttk.Label(search_frame, text="Search:").grid(row=0, column=0, padx=5)
        self.search_var = tk.StringVar()
        self.search_entry = ttk.Entry(search_frame, textvariable=self.search_var, width=40)
        self.search_entry.grid(row=0, column=1, padx=5)
        self.search_entry.bind('<KeyRelease>', self.filter_movies)
        
        ttk.Button(search_frame, text="Clear", 
                  command=self.clear_search).grid(row=0, column=2, padx=5)
        ttk.Button(search_frame, text="Refresh", 
                  command=self.load_movies).grid(row=0, column=3, padx=5)
        
        # Add movie count label
        self.count_label = ttk.Label(search_frame, text="", font=("", 10))
        self.count_label.grid(row=0, column=4, padx=20)
        
        # Movie list with scrollbar
        list_frame = ttk.LabelFrame(main_frame, text="Movies (Double-click date to edit)", padding="5")
        list_frame.grid(row=3, column=0, columnspan=3, sticky=(tk.W, tk.E, tk.N, tk.S), pady=5)
        
        # Treeview for movie list
        columns = ('ID', 'Title', 'Added Date', 'Epoch')
        self.tree = ttk.Treeview(list_frame, columns=columns, show='headings', height=20)
        
        # Define column headings and widths
        self.tree.heading('ID', text='ID')
        self.tree.heading('Title', text='Title')
        self.tree.heading('Added Date', text='Added Date')
        self.tree.heading('Epoch', text='Epoch (Hidden)')
        
        self.tree.column('ID', width=60)
        self.tree.column('Title', width=400)
        self.tree.column('Added Date', width=200)
        self.tree.column('Epoch', width=0, stretch=False)  # Hidden column
        
        # Hide the epoch column
        self.tree['displaycolumns'] = ('ID', 'Title', 'Added Date')
        
        # Scrollbar
        scrollbar = ttk.Scrollbar(list_frame, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        
        self.tree.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        scrollbar.grid(row=0, column=1, sticky=(tk.N, tk.S))
        
        # Double-click to edit - bind to the treeview
        self.tree.bind('<Double-Button-1>', self.edit_date)
        
        # Info label at bottom
        self.info_label = ttk.Label(main_frame, 
                                   text="Double-click a date to edit. Date format: " + self.date_format,
                                   font=("", 9), foreground="gray")
        self.info_label.grid(row=4, column=0, columnspan=3, pady=5)
        
        # Keyboard bindings
        self.root.bind('<Control-comma>', lambda e: self.show_settings())
        self.root.bind('<Control-b>', lambda e: self.create_backup())
        self.root.bind('<Control-q>', lambda e: self.root.quit())
        self.root.bind('<Control-r>', lambda e: self.load_movies())
        self.root.bind('<Control-f>', lambda e: self.search_entry.focus())
        
        # Configure style
        style = ttk.Style()
        style.configure("Accent.TButton", font=("", 10, "bold"))
        
        # Make grid expandable
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        main_frame.columnconfigure(0, weight=1)
        main_frame.rowconfigure(3, weight=1)
        list_frame.columnconfigure(0, weight=1)
        list_frame.rowconfigure(0, weight=1)
    
    def execute_sql(self, query):
        """Execute SQL using Plex SQLite"""
        try:
            print(f"\n=== Executing SQL ===")
            print(f"Command: {self.plex_sqlite}")
            print(f"Database: {self.db_path}")
            print(f"Query: {query}")
            
            result = subprocess.run(
                [self.plex_sqlite, self.db_path, query],
                capture_output=True,
                text=True,
                check=True
            )
            
            print(f"Return code: {result.returncode}")
            print(f"Stdout: '{result.stdout}'")
            print(f"Stderr: '{result.stderr}'")
            print(f"=== End SQL ===\n")
            
            return result.stdout
        except subprocess.CalledProcessError as e:
            print(f"!!! SQL ERROR !!!")
            print(f"Return code: {e.returncode}")
            print(f"Stderr: {e.stderr}")
            messagebox.showerror("SQL Error", f"Error executing query:\n{e.stderr}")
            return None
    
    def check_plex_status(self):
        """Check if Plex is running"""
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
            subprocess.run(['systemctl', 'stop', 'plexmediaserver'])
            self.check_plex_status()
            self.status_label.config(text="Plex stopped")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to stop Plex: {e}")
    
    def start_plex(self):
        """Start Plex service"""
        self.status_label.config(text="Starting Plex...")
        try:
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
    
    def load_movies(self):
        """Load movies from database"""
        self.status_label.config(text="Loading movies...")
        
        query = """
        SELECT id, title, added_at 
        FROM metadata_items 
        WHERE guid LIKE 'plex://movie/%' 
        ORDER BY added_at DESC 
        LIMIT 1000
        """
        
        result = self.execute_sql(query)
        if result:
            # Clear existing items
            for item in self.tree.get_children():
                self.tree.delete(item)
            
            self.movies = []
            lines = result.strip().split('\n')
            for line in lines:
                if '|' in line:
                    parts = line.split('|')
                    if len(parts) >= 3 and parts[0].isdigit():
                        movie_id = int(parts[0])
                        title = parts[1]
                        epoch = int(parts[2]) if parts[2].isdigit() else 0
                        
                        # Convert epoch to human-readable date
                        try:
                            date_str = datetime.fromtimestamp(epoch).strftime(self.date_format)
                        except:
                            date_str = 'Invalid Date'
                        
                        self.movies.append({
                            'id': movie_id,
                            'title': title,
                            'epoch': epoch,
                            'date': date_str
                        })
            
            self.display_movies(self.movies)
            self.status_label.config(text=f"Loaded {len(self.movies)} movies")
            self.count_label.config(text=f"Total: {len(self.movies)}")
    
    def display_movies(self, movies):
        """Display movies in treeview"""
        # Clear existing
        for item in self.tree.get_children():
            self.tree.delete(item)
        
        # Add movies
        for movie in movies:
            self.tree.insert('', 'end', values=(
                movie['id'],
                movie['title'],
                movie['date'],
                movie['epoch']  # Hidden column but still in values
            ))
    
    def filter_movies(self, event=None):
        """Filter movies based on search"""
        search_term = self.search_var.get().lower()
        if not search_term:
            self.display_movies(self.movies)
            self.count_label.config(text=f"Total: {len(self.movies)}")
        else:
            filtered = [m for m in self.movies if search_term in m['title'].lower()]
            self.display_movies(filtered)
            self.count_label.config(text=f"Showing: {len(filtered)} of {len(self.movies)}")
            self.status_label.config(text=f"Filtered to {len(filtered)} movies")
    
    def clear_search(self):
        """Clear search field"""
        self.search_var.set("")
        self.display_movies(self.movies)
        self.count_label.config(text=f"Total: {len(self.movies)}")
        self.status_label.config(text=f"Showing all {len(self.movies)} movies")
    
    def edit_date(self, event):
        """Edit date for selected movie"""
        print("\n*** DOUBLE-CLICK DETECTED ***")
        
        # Get the item that was clicked
        region = self.tree.identify_region(event.x, event.y)
        print(f"Click region: {region}")
        if region != "cell":
            print("Not a cell, ignoring")
            return
            
        # Get the item
        item_id = self.tree.identify_row(event.y)
        print(f"Item ID: {item_id}")
        if not item_id:
            print("No item found")
            return
        
        # Get the values from the clicked item
        item = self.tree.item(item_id)
        values = item.get('values')
        print(f"Values: {values}")
        if not values or len(values) < 4:
            print(f"Error: Invalid values from tree item: {values}")
            return
        
        try:
            movie_id = values[0]
            title = str(values[1])
            current_date = str(values[2])
            current_epoch = values[3]
            
            print(f"Calling create_edit_dialog for movie: {title}")
            # Create edit dialog
            self.create_edit_dialog(movie_id, title, current_date, current_epoch)
            
        except Exception as e:
            print(f"Error in edit_date: {e}")
            messagebox.showerror("Error", f"Failed to open edit dialog: {e}")
    
    def create_edit_dialog(self, movie_id, title, current_date, current_epoch):
        """Create the date edit dialog"""
        print("\n" + "="*60)
        print("OPENING EDIT DIALOG")
        print(f"Movie ID: {movie_id}")
        print(f"Title: {title}")
        print(f"Current Date: {current_date}")
        print(f"Current Epoch: {current_epoch}")
        print("="*60 + "\n")
        
        dialog = tk.Toplevel(self.root)
        dialog.title("Edit Date")
        print("Dialog window created")
        
        # Build the dialog content first
        
        # On-screen status message (visible even without console)
        status_frame = ttk.Frame(dialog, relief=tk.SUNKEN, borderwidth=1)
        status_frame.pack(fill='x', padx=10, pady=5)
        status_msg = ttk.Label(status_frame, 
                              text="Dialog opened successfully. Look for SAVE CHANGES button at bottom.",
                              font=("", 9), foreground="blue", wraplength=500)
        status_msg.pack(pady=3)
        
        # Simple warning text at top (no emoji or background color to avoid X11 errors)
        warning_label = ttk.Label(dialog, 
                                  text="WARNING: Make sure Plex Media Server is STOPPED before saving changes",
                                  font=("", 9, "bold"), foreground="red")
        warning_label.pack(pady=10)
        
        # Movie info
        ttk.Label(dialog, text=f"Movie: {title}", font=("", 11, "bold")).pack(pady=10)
        ttk.Label(dialog, text=f"Current Date: {current_date}").pack(pady=5)
        
        # Date input frame
        input_frame = ttk.Frame(dialog)
        input_frame.pack(pady=20)
        
        ttk.Label(input_frame, text="New Date:").grid(row=0, column=0, padx=5, pady=5)
        
        # Date entry with current value
        date_var = tk.StringVar(value=current_date)
        date_entry = ttk.Entry(input_frame, textvariable=date_var, width=30, font=("", 11))
        date_entry.grid(row=0, column=1, padx=5, pady=5)
        
        # Format help
        format_label = ttk.Label(input_frame, text=f"Format: {self.date_format}", 
                                font=("", 9), foreground="gray")
        format_label.grid(row=1, column=1, padx=5, pady=2)
        
        # Quick date buttons
        quick_frame = ttk.LabelFrame(dialog, text="Quick Dates", padding="10")
        quick_frame.pack(pady=10, padx=20, fill='x')
        
        button_frame = ttk.Frame(quick_frame)
        button_frame.pack()
        
        def set_date(date_str):
            date_var.set(date_str)
        
        # Quick date options
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
            btn = ttk.Button(button_frame, text=label, 
                           command=lambda d=date_val: set_date(d))
            btn.grid(row=row, column=col, padx=2, pady=2)
            col += 1
            if col > 2:  # 3 buttons per row
                col = 0
                row += 1
        
        # Result label
        result_label = ttk.Label(dialog, text="", foreground="green")
        result_label.pack(pady=5)
        
        def save_edit():
            new_date_str = date_var.get()
            
            # Update on-screen status
            status_msg.config(text="Checking if Plex is running...", foreground="blue")
            dialog.update()
            
            # Check if Plex is running
            if self.check_plex_status():
                status_msg.config(text="ERROR: Plex is running! Stop Plex first, then try again.", foreground="red")
                result_label.config(text="WARNING: Plex is running! Stop Plex first.", foreground="orange")
                response = messagebox.askyesno("Plex is Running", 
                    "Plex Media Server is currently running.\n"
                    "The database may be locked.\n\n"
                    "Do you want to stop Plex and try the update?")
                if response:
                    self.stop_plex()
                    status_msg.config(text="Plex stopped. Click SAVE CHANGES again.", foreground="green")
                    result_label.config(text="Plex stopped. Click Save again to update.", foreground="blue")
                return
            
            status_msg.config(text="Plex is stopped. Processing update...", foreground="blue")
            dialog.update()
            
            try:
                # Parse the date string to epoch
                new_datetime = datetime.strptime(new_date_str, self.date_format)
                new_epoch = int(new_datetime.timestamp())
                
                print(f"\n=== UPDATE DEBUG ===")
                print(f"Movie ID: {movie_id}")
                print(f"Title: {title}")
                print(f"Old epoch: {current_epoch}")
                print(f"New epoch: {new_epoch}")
                print(f"Old date: {current_date}")
                print(f"New date: {new_date_str}")
                
                status_msg.config(text=f"Updating database for movie ID {movie_id}...", foreground="blue")
                dialog.update()
                
                # Update the database
                query = f"UPDATE metadata_items SET added_at = {new_epoch} WHERE id = {movie_id}"
                print(f"Query: {query}")
                
                result = self.execute_sql(query)
                print(f"Query result: '{result}'")
                
                if result is not None:  # Check if not None (UPDATE returns empty string on success)
                    status_msg.config(text="Update sent. Verifying...", foreground="blue")
                    dialog.update()
                    
                    # Verify the update actually took effect
                    verify_query = f"SELECT added_at FROM metadata_items WHERE id = {movie_id}"
                    verify_result = self.execute_sql(verify_query)
                    print(f"Verification query result: '{verify_result}'")
                    
                    if verify_result and str(new_epoch) in verify_result:
                        status_msg.config(text="SUCCESS! Date updated and verified in database!", foreground="green")
                        result_label.config(text="SUCCESS: Date updated and verified!", foreground="green")
                        print("SUCCESS: Update verified successfully!")
                    else:
                        status_msg.config(text=f"WARNING: Update unclear. Expected {new_epoch}, got {verify_result}", foreground="orange")
                        result_label.config(text="WARNING: Update completed but verification unclear", foreground="orange")
                        print(f"WARNING: Verification unclear. Expected {new_epoch}, got: {verify_result}")
                    
                    self.load_movies()
                    dialog.after(2000, dialog.destroy)
                    self.status_label.config(text=f"Updated date for movie ID {movie_id}")
                else:
                    status_msg.config(text="ERROR: Database update failed!", foreground="red")
                    result_label.config(text="ERROR: Update failed - database error", foreground="red")
                    print("ERROR: Update failed - execute_sql returned None")
                    
            except ValueError as e:
                status_msg.config(text=f"ERROR: Invalid date format!", foreground="red")
                result_label.config(text=f"ERROR: Invalid date format. Use: {self.date_format}", foreground="red")
                print(f"ValueError: {e}")
            except Exception as e:
                status_msg.config(text=f"ERROR: {str(e)}", foreground="red")
                result_label.config(text=f"ERROR: {str(e)}", foreground="red")
                print(f"Exception: {e}")
        
        # Buttons - make them VERY prominent with lots of spacing
        button_frame = ttk.Frame(dialog)
        button_frame.pack(pady=30, padx=20)
        
        # Create a custom style for the save button (no emoji to avoid X11 errors)
        save_btn = ttk.Button(button_frame, text="SAVE CHANGES", command=save_edit, 
                            style="Accent.TButton", width=25)
        save_btn.pack(side=tk.LEFT, padx=15, pady=10)
        
        cancel_btn = ttk.Button(button_frame, text="Cancel", 
                              command=dialog.destroy, width=20)
        cancel_btn.pack(side=tk.LEFT, padx=15, pady=10)
        
        print("Buttons created: SAVE CHANGES and Cancel")
        
        # Add another status label at the very bottom to make sure it's visible
        bottom_status = ttk.Label(dialog, 
                                 text="Scroll down if you don't see the SAVE CHANGES button above",
                                 font=("", 8), foreground="gray")
        bottom_status.pack(pady=5)
        
        # Bind Enter key to save
        date_entry.bind('<Return>', lambda e: save_edit())
        dialog.bind('<Escape>', lambda e: dialog.destroy())
        
        # Set dialog properties after content is added
        dialog.geometry("600x550")  # Much larger to ensure buttons are visible
        dialog.transient(self.root)
        dialog.resizable(True, True)  # Make it resizable
        
        # Center the dialog
        dialog.update_idletasks()
        x = (dialog.winfo_screenwidth() // 2) - (300)
        y = (dialog.winfo_screenheight() // 2) - (275)
        dialog.geometry(f"600x550+{x}+{y}")
        
        # Now try to grab focus after window is fully built
        dialog.after(100, lambda: dialog.grab_set_safe())
        
        # Safe grab method
        def grab_set_safe():
            try:
                dialog.grab_set()
            except tk.TclError:
                pass  # Ignore if grab fails
        
        dialog.grab_set_safe = grab_set_safe
        
        # Focus the entry field
        date_entry.select_range(0, tk.END)
        date_entry.focus()
        
        print("Dialog setup complete - should be visible now")
        print("="*60 + "\n")
    
    def show_settings(self):
        """Show settings dialog"""
        dialog = tk.Toplevel(self.root)
        dialog.title("Settings")
        dialog.geometry("700x400")
        dialog.transient(self.root)
        
        # Center the dialog
        dialog.update_idletasks()
        x = (dialog.winfo_screenwidth() // 2) - (350)
        y = (dialog.winfo_screenheight() // 2) - (200)
        dialog.geometry(f"700x400+{x}+{y}")
        
        ttk.Label(dialog, text="Configuration Settings", 
                 font=("", 14, "bold")).pack(pady=10)
        
        # Settings frame
        settings_frame = ttk.Frame(dialog, padding="20")
        settings_frame.pack(fill='both', expand=True)
        
        # Plex SQLite path
        ttk.Label(settings_frame, text="Plex SQLite Path:").grid(row=0, column=0, sticky='w', pady=5)
        sqlite_var = tk.StringVar(value=self.plex_sqlite)
        sqlite_entry = ttk.Entry(settings_frame, textvariable=sqlite_var, width=60)
        sqlite_entry.grid(row=0, column=1, pady=5, padx=5)
        
        def browse_sqlite():
            filename = filedialog.askopenfilename(
                title="Select Plex SQLite executable",
                initialdir="/usr/lib/plexmediaserver/"
            )
            if filename:
                sqlite_var.set(filename)
        
        ttk.Button(settings_frame, text="Browse", 
                  command=browse_sqlite).grid(row=0, column=2, pady=5)
        
        # Database path
        ttk.Label(settings_frame, text="Database Path:").grid(row=1, column=0, sticky='w', pady=5)
        db_var = tk.StringVar(value=self.db_path)
        db_entry = ttk.Entry(settings_frame, textvariable=db_var, width=60)
        db_entry.grid(row=1, column=1, pady=5, padx=5)
        
        def browse_db():
            filename = filedialog.askopenfilename(
                title="Select Plex database",
                initialdir="/var/lib/plexmediaserver/",
                filetypes=[("Database files", "*.db"), ("All files", "*.*")]
            )
            if filename:
                db_var.set(filename)
        
        ttk.Button(settings_frame, text="Browse", 
                  command=browse_db).grid(row=1, column=2, pady=5)
        
        # Date format
        ttk.Label(settings_frame, text="Date Format:").grid(row=2, column=0, sticky='w', pady=5)
        format_var = tk.StringVar(value=self.date_format)
        format_combo = ttk.Combobox(settings_frame, textvariable=format_var, width=30)
        format_combo['values'] = (
            '%Y-%m-%d %H:%M:%S',
            '%Y/%m/%d %H:%M:%S',
            '%d-%m-%Y %H:%M:%S',
            '%d/%m/%Y %H:%M:%S',
            '%m/%d/%Y %H:%M:%S',
            '%Y-%m-%d',
            '%m/%d/%Y',
            '%d/%m/%Y'
        )
        format_combo.grid(row=2, column=1, pady=5, padx=5, sticky='w')
        
        # Current status
        status_frame = ttk.LabelFrame(settings_frame, text="Current Status", padding="10")
        status_frame.grid(row=3, column=0, columnspan=3, pady=20, sticky='ew')
        
        sqlite_exists = "[OK] Found" if os.path.exists(sqlite_var.get()) else "[ERROR] Not found"
        db_exists = "[OK] Found" if os.path.exists(db_var.get()) else "[ERROR] Not found"
        
        ttk.Label(status_frame, text=f"Plex SQLite: {sqlite_exists}").pack(anchor='w')
        ttk.Label(status_frame, text=f"Database: {db_exists}").pack(anchor='w')
        
        # Buttons
        button_frame = ttk.Frame(dialog)
        button_frame.pack(pady=10)
        
        def save_settings():
            self.plex_sqlite = sqlite_var.get()
            self.db_path = db_var.get()
            self.date_format = format_var.get()
            
            if not os.path.exists(self.plex_sqlite):
                messagebox.showwarning("Warning", "Plex SQLite executable not found at specified path")
            if not os.path.exists(self.db_path):
                messagebox.showwarning("Warning", "Database file not found at specified path")
            
            if self.save_config():
                messagebox.showinfo("Settings", "Settings saved successfully!")
                dialog.destroy()
                
                # Reload if paths are valid
                if self.validate_paths():
                    self.load_movies()
                    self.info_label.config(text="Double-click a date to edit. Date format: " + self.date_format)
        
        def reset_defaults():
            sqlite_var.set("/usr/lib/plexmediaserver/Plex SQLite")
            db_var.set("/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db")
            format_var.set("%Y-%m-%d %H:%M:%S")
        
        ttk.Button(button_frame, text="Save", command=save_settings, 
                  style="Accent.TButton").pack(side=tk.LEFT, padx=5)
        ttk.Button(button_frame, text="Reset Defaults", 
                  command=reset_defaults).pack(side=tk.LEFT, padx=5)
        ttk.Button(button_frame, text="Cancel", 
                  command=dialog.destroy).pack(side=tk.LEFT, padx=5)
        
        # Try to grab after a delay
        dialog.after(100, lambda: self.safe_grab(dialog))
    
    def safe_grab(self, window):
        """Safely try to grab a window"""
        try:
            window.grab_set()
        except tk.TclError:
            pass  # Ignore grab errors
    
    def show_date_help(self):
        """Show date format help"""
        help_text = """Date Format Codes:
        
%Y - 4-digit year (2024)
%y - 2-digit year (24)
%m - Month as number (01-12)
%B - Full month name (January)
%b - Abbreviated month (Jan)
%d - Day of month (01-31)
%H - Hour (00-23)
%I - Hour (01-12)
%M - Minute (00-59)
%S - Second (00-59)
%p - AM/PM

Examples:
%Y-%m-%d %H:%M:%S → 2024-10-08 14:30:45
%m/%d/%Y %I:%M %p → 10/08/2024 02:30 PM
%d-%b-%Y → 08-Oct-2024"""
        
        messagebox.showinfo("Date Format Help", help_text)
    
    def show_shortcuts(self):
        """Show keyboard shortcuts"""
        shortcuts = """Keyboard Shortcuts:
        
Ctrl+, - Open Settings
Ctrl+B - Create Backup
Ctrl+F - Focus Search
Ctrl+R - Refresh Movies
Ctrl+Q - Quit Application

In Dialogs:
Enter - Save/Confirm
Escape - Cancel/Close"""
        
        messagebox.showinfo("Keyboard Shortcuts", shortcuts)
    
    def show_about(self):
        """Show about dialog"""
        about_text = """Plex Database Editor v2.1
        
Safely modify Plex movie timestamps using
the official Plex SQLite executable.

Features:
• Human-readable date editing
• Configurable paths and date formats
• Automatic backups
• Real-time search and filtering
• Keyboard shortcuts

Created for easy Plex database management."""
        
        messagebox.showinfo("About", about_text)

if __name__ == "__main__":
    # Check if tkinter is available
    try:
        root = tk.Tk()
        app = PlexDatabaseEditor(root)
        root.mainloop()
    except Exception as e:
        print(f"Error starting GUI: {e}")
        print("\nMake sure you have tkinter installed:")
        print("  sudo apt-get install python3-tk")
        sys.exit(1)