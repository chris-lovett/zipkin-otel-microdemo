#!/usr/bin/env python3
"""
Advanced load generator for zipkin-otel-microdemo
Generates realistic traffic patterns with configurable scenarios
"""

import argparse
import random
import time
import requests
import threading
from datetime import datetime, timedelta
from collections import defaultdict
import sys

class LoadGenerator:
    def __init__(self, base_url, duration=60, users=5, scenario="mixed"):
        self.base_url = base_url.rstrip('/')
        self.duration = duration
        self.users = users
        self.scenario = scenario
        self.stats = defaultdict(lambda: {"success": 0, "error": 0, "total_time": 0})
        self.lock = threading.Lock()
        
    def log(self, user_id, message, color=""):
        colors = {
            "green": "\033[0;32m",
            "yellow": "\033[1;33m",
            "red": "\033[0;31m",
            "blue": "\033[0;34m",
            "reset": "\033[0m"
        }
        color_code = colors.get(color, "")
        reset = colors["reset"] if color else ""
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"{color_code}[{timestamp}] [User {user_id}] {message}{reset}")
    
    def record_stat(self, endpoint, success, duration):
        with self.lock:
            self.stats[endpoint]["success" if success else "error"] += 1
            self.stats[endpoint]["total_time"] += duration
    
    def make_request(self, method, path, user_id, **kwargs):
        url = f"{self.base_url}{path}"
        start = time.time()
        try:
            response = requests.request(method, url, timeout=10, **kwargs)
            duration = time.time() - start
            success = 200 <= response.status_code < 300
            
            self.record_stat(path, success, duration)
            
            status_color = "green" if success else "red"
            self.log(user_id, 
                    f"{method} {path} -> {response.status_code} ({duration:.2f}s)",
                    status_color)
            return response
        except Exception as e:
            duration = time.time() - start
            self.record_stat(path, False, duration)
            self.log(user_id, f"{method} {path} -> ERROR: {e}", "red")
            return None
    
    def browse_products(self, user_id):
        """Simulate browsing products"""
        self.log(user_id, "Browsing products...", "blue")
        
        # List products
        self.make_request("GET", "/products", user_id)
        time.sleep(random.uniform(0.5, 1.5))
        
        # View 1-3 product details
        for _ in range(random.randint(1, 3)):
            product_id = random.randint(1, 10)
            self.make_request("GET", f"/products/{product_id}", user_id)
            time.sleep(random.uniform(0.5, 2))
    
    def add_to_cart(self, user_id):
        """Simulate adding items to cart"""
        self.log(user_id, "Adding items to cart...", "blue")
        
        # Browse first
        self.make_request("GET", "/products", user_id)
        time.sleep(random.uniform(0.5, 1))
        
        # Add 1-3 items
        for _ in range(random.randint(1, 3)):
            product_id = random.randint(1, 10)
            quantity = random.randint(1, 3)
            
            self.make_request("POST", f"/cart/user{user_id}/items", user_id,
                            json={"product_id": str(product_id), "quantity": quantity},
                            headers={"Content-Type": "application/json"})
            time.sleep(random.uniform(0.5, 1.5))
    
    def checkout(self, user_id):
        """Simulate checkout process"""
        self.log(user_id, "Starting checkout...", "blue")
        
        # Add item to cart first
        product_id = random.randint(1, 10)
        self.make_request("POST", f"/cart/user{user_id}/items", user_id,
                        json={"product_id": str(product_id), "quantity": 2},
                        headers={"Content-Type": "application/json"})
        time.sleep(random.uniform(0.5, 1))
        
        # Checkout
        self.make_request("POST", "/checkout", user_id,
                        json={"user_id": f"user{user_id}"},
                        headers={"Content-Type": "application/json"})
    
    def heavy_browser(self, user_id, end_time):
        """User who mostly browses (70% browse, 20% cart, 10% checkout)"""
        while time.time() < end_time:
            action = random.random()
            if action < 0.7:
                self.browse_products(user_id)
            elif action < 0.9:
                self.add_to_cart(user_id)
            else:
                self.checkout(user_id)
            time.sleep(random.uniform(2, 5))
    
    def heavy_buyer(self, user_id, end_time):
        """User who frequently checks out (30% browse, 30% cart, 40% checkout)"""
        while time.time() < end_time:
            action = random.random()
            if action < 0.3:
                self.browse_products(user_id)
            elif action < 0.6:
                self.add_to_cart(user_id)
            else:
                self.checkout(user_id)
            time.sleep(random.uniform(3, 7))
    
    def mixed_user(self, user_id, end_time):
        """Balanced user (50% browse, 30% cart, 20% checkout)"""
        while time.time() < end_time:
            action = random.random()
            if action < 0.5:
                self.browse_products(user_id)
            elif action < 0.8:
                self.add_to_cart(user_id)
            else:
                self.checkout(user_id)
            time.sleep(random.uniform(2, 6))
    
    def spike_traffic(self, user_id, end_time):
        """Generate spike traffic with minimal delays"""
        while time.time() < end_time:
            action = random.random()
            if action < 0.4:
                self.browse_products(user_id)
            elif action < 0.7:
                self.add_to_cart(user_id)
            else:
                self.checkout(user_id)
            time.sleep(random.uniform(0.1, 0.5))  # Very short delays
    
    def run_user(self, user_id, end_time):
        """Run a user session based on scenario"""
        self.log(user_id, f"Starting session (scenario: {self.scenario})", "green")
        
        try:
            if self.scenario == "browse":
                self.heavy_browser(user_id, end_time)
            elif self.scenario == "buy":
                self.heavy_buyer(user_id, end_time)
            elif self.scenario == "spike":
                self.spike_traffic(user_id, end_time)
            else:  # mixed
                self.mixed_user(user_id, end_time)
        except KeyboardInterrupt:
            pass
        
        self.log(user_id, "Session complete", "green")
    
    def print_stats(self):
        """Print statistics"""
        print("\n" + "="*60)
        print("LOAD TEST STATISTICS")
        print("="*60)
        
        total_requests = 0
        total_success = 0
        total_errors = 0
        
        for endpoint, stats in sorted(self.stats.items()):
            success = stats["success"]
            error = stats["error"]
            total = success + error
            avg_time = stats["total_time"] / total if total > 0 else 0
            
            total_requests += total
            total_success += success
            total_errors += error
            
            print(f"\n{endpoint}")
            print(f"  Requests: {total}")
            print(f"  Success:  {success} ({success/total*100:.1f}%)")
            print(f"  Errors:   {error} ({error/total*100:.1f}%)")
            print(f"  Avg Time: {avg_time:.3f}s")
        
        print("\n" + "-"*60)
        print(f"TOTAL REQUESTS: {total_requests}")
        print(f"SUCCESS: {total_success} ({total_success/total_requests*100:.1f}%)")
        print(f"ERRORS:  {total_errors} ({total_errors/total_requests*100:.1f}%)")
        print("="*60 + "\n")
    
    def run(self):
        """Run the load test"""
        print(f"\n{'='*60}")
        print("ZIPKIN OTEL MICRODEMO - ADVANCED LOAD GENERATOR")
        print(f"{'='*60}")
        print(f"Base URL:  {self.base_url}")
        print(f"Duration:  {self.duration}s")
        print(f"Users:     {self.users}")
        print(f"Scenario:  {self.scenario}")
        print(f"{'='*60}\n")
        
        end_time = time.time() + self.duration
        threads = []
        
        # Start user threads
        for i in range(1, self.users + 1):
            thread = threading.Thread(target=self.run_user, args=(i, end_time))
            thread.start()
            threads.append(thread)
            time.sleep(0.1)  # Stagger starts slightly
        
        # Wait for all threads
        try:
            for thread in threads:
                thread.join()
        except KeyboardInterrupt:
            print("\n\nStopping load test...")
            sys.exit(0)
        
        self.print_stats()
        
        print("Check Zipkin UI for distributed traces:")
        print("https://zipkin-tracing-demo.apps.rosa.cluster1.6cxo.p3.openshiftapps.com\n")

def main():
    parser = argparse.ArgumentParser(description="Advanced load generator for zipkin-otel-microdemo")
    parser.add_argument("--url", default="https://frontend-tracing-demo.apps.rosa.cluster1.6cxo.p3.openshiftapps.com",
                       help="Frontend URL")
    parser.add_argument("--duration", type=int, default=60,
                       help="Test duration in seconds (default: 60)")
    parser.add_argument("--users", type=int, default=5,
                       help="Number of concurrent users (default: 5)")
    parser.add_argument("--scenario", choices=["mixed", "browse", "buy", "spike"], default="mixed",
                       help="Traffic scenario (default: mixed)")
    
    args = parser.parse_args()
    
    generator = LoadGenerator(args.url, args.duration, args.users, args.scenario)
    generator.run()

if __name__ == "__main__":
    main()

# Made with Bob
